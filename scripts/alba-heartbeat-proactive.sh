#!/usr/bin/env bash
# alba-heartbeat-proactive.sh — Proactive heartbeat runner
#
# Evaluates HEARTBEAT.md checklist: parses check IDs, dispatches each
# to a handler function, logs aggregate results to SQLite.
#
# All checks are pure shell — zero LLM cost on idle.
#
# Usage:
#   bash scripts/alba-heartbeat-proactive.sh                         # default checklist
#   bash scripts/alba-heartbeat-proactive.sh --heartbeat-file /path  # custom checklist
#
# Environment:
#   ALBA_LOGS_DB        — logs database (default: ~/.alba/alba-logs.db)
#   ALBA_MEMORY_DB      — memory database (default: ~/.alba/alba-memory.db)
#   HEARTBEAT_FILE      — checklist path (default: ~/.alba/HEARTBEAT.md)

set -euo pipefail

# ── Cron-compatible PATH ─────────────────────────────────────
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export HOME="${HOME:-$(eval echo ~)}"

# ── Source shared libraries ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/alba-log.sh"

if [ -f "$SCRIPT_DIR/alba-alert.sh" ]; then
    source "$SCRIPT_DIR/alba-alert.sh"
fi

# ── Configuration ────────────────────────────────────────────
ALBA_LOGS_DB="${ALBA_LOGS_DB:-$HOME/.alba/alba-logs.db}"
ALBA_MEMORY_DB="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-$HOME/.alba/HEARTBEAT.md}"

# ── Parse CLI args ───────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --heartbeat-file) HEARTBEAT_FILE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ── Logging helper (never stdout) ────────────────────────────
_hb_log() {
    alba_log "$1" heartbeat "$2" "${3:-}" 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────
# Check handlers
# Each returns 0 on pass, 1 on triggered (problem found).
# MUST NOT write to stdout (subshell capture contamination).
# Status details go to stderr or structured log only.
# ────────────────────────────────────────────────────────────

handler_disk() {
    local pct
    pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [ "$pct" -ge 90 ]; then
        _hb_log WARN "Disk usage at ${pct}%"
        return 1
    fi
    _hb_log INFO "Disk OK: ${pct}%"
    return 0
}

handler_ram() {
    local pid rss_mb
    pid=$(pgrep -f 'claude.*--dangerously-skip-permissions' 2>/dev/null | head -1 || true)
    if [ -z "$pid" ]; then
        _hb_log INFO "RAM check: no Claude process — skipping"
        return 0
    fi
    rss_mb=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    rss_mb="${rss_mb:-0}"
    if [ "$rss_mb" -gt 5500 ]; then
        _hb_log WARN "Claude RSS high: ${rss_mb}MB"
        return 1
    fi
    _hb_log INFO "RAM OK: Claude RSS ${rss_mb}MB"
    return 0
}

handler_alba_process() {
    local pid
    pid=$(pgrep -f 'claude.*--dangerously-skip-permissions' 2>/dev/null | head -1 || true)
    if [ -z "$pid" ]; then
        _hb_log WARN "Alba process not found"
        return 1
    fi
    _hb_log INFO "Alba process running (pid: $pid)"
    return 0
}

handler_tmux_session() {
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t alba 2>/dev/null; then
        _hb_log INFO "tmux session 'alba' alive"
        return 0
    fi
    _hb_log WARN "tmux session 'alba' not found"
    return 1
}

handler_standing_orders() {
    if [ ! -f "$SCRIPT_DIR/alba-standing-orders.sh" ]; then
        _hb_log WARN "Standing orders script not found"
        return 1
    fi

    local output
    output=$(ALBA_MEMORY_DB="$ALBA_MEMORY_DB" bash "$SCRIPT_DIR/alba-standing-orders.sh" --check 2>/dev/null) || {
        _hb_log WARN "Standing orders --check failed"
        return 1
    }

    # Count due orders from output
    local due_count
    due_count=$(echo "$output" | grep -c '^DUE:' || true)

    if [ "$due_count" -gt 0 ]; then
        _hb_log INFO "Standing orders: $due_count due"
    else
        _hb_log INFO "Standing orders: none due"
    fi
    return 0
}

handler_memory_db() {
    if [ ! -f "$ALBA_MEMORY_DB" ]; then
        _hb_log WARN "Memory DB not found: $ALBA_MEMORY_DB"
        return 1
    fi
    if ! /usr/bin/sqlite3 "$ALBA_MEMORY_DB" "SELECT 1;" >/dev/null 2>&1; then
        _hb_log WARN "Memory DB unreadable: $ALBA_MEMORY_DB"
        return 1
    fi
    _hb_log INFO "Memory DB OK"
    return 0
}

handler_goals() {
    # Check for blocked or overdue goals in the goals table
    # Gracefully handle missing table (migration may not be applied yet)
    local table_exists
    table_exists=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='goals';" 2>/dev/null || echo "0")

    if [ "$table_exists" != "1" ]; then
        _hb_log INFO "Goals table not found — migration 007 may not be applied yet"
        return 0
    fi

    local blocked overdue today
    today=$(date +%Y-%m-%d)

    blocked=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT COUNT(*) FROM goals WHERE status = 'blocked';" 2>/dev/null || echo "0")

    overdue=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT COUNT(*) FROM goals WHERE status = 'active' AND target_date IS NOT NULL AND target_date < '$today';" 2>/dev/null || echo "0")

    if [ "$blocked" -gt 0 ] || [ "$overdue" -gt 0 ]; then
        _hb_log WARN "Goals: $blocked blocked, $overdue overdue"
        return 1
    fi

    _hb_log INFO "Goals OK: 0 blocked, 0 overdue"
    return 0
}

handler_telegram() {
    _hb_log INFO "Telegram check: TODO stub — not yet wired"
    return 0
}

handler_email() {
    _hb_log INFO "Email check: TODO stub — not yet wired"
    return 0
}

# ── API Keys Health Check ────────────────────────────────────
handler_api_keys() {
    # Source .env for API keys
    if [ -f "$HOME/.alba/.env" ]; then
        set -a; source "$HOME/.alba/.env" 2>/dev/null; set +a
    fi

    local failed=0
    local checked=0
    local dead_keys=""

    # ElevenLabs
    if [ -n "${ELEVENLABS_API_KEY:-}" ]; then
        checked=$((checked + 1))
        local el_status
        el_status=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
            -H "xi-api-key: $ELEVENLABS_API_KEY" \
            https://api.elevenlabs.io/v1/user 2>/dev/null || echo "000")
        if [ "$el_status" = "401" ] || [ "$el_status" = "403" ]; then
            failed=$((failed + 1)); dead_keys="$dead_keys ElevenLabs($el_status)"
        fi
    fi

    # Supabase
    if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ]; then
        checked=$((checked + 1))
        local sb_status
        sb_status=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
            -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
            https://api.supabase.com/v1/projects 2>/dev/null || echo "000")
        if [ "$sb_status" = "401" ] || [ "$sb_status" = "403" ]; then
            failed=$((failed + 1)); dead_keys="$dead_keys Supabase($sb_status)"
        fi
    fi

    # Brave Search
    if [ -n "${BRAVE_API_KEY:-}" ]; then
        checked=$((checked + 1))
        local br_status
        br_status=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
            -H "X-Subscription-Token: $BRAVE_API_KEY" \
            "https://api.search.brave.com/res/v1/web/search?q=test&count=1" 2>/dev/null || echo "000")
        if [ "$br_status" = "401" ] || [ "$br_status" = "403" ]; then
            failed=$((failed + 1)); dead_keys="$dead_keys Brave($br_status)"
        fi
    fi

    # GitHub
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        checked=$((checked + 1))
        local gh_status
        gh_status=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
            -H "Authorization: Bearer $GITHUB_TOKEN" \
            https://api.github.com/user 2>/dev/null || echo "000")
        if [ "$gh_status" = "401" ] || [ "$gh_status" = "403" ]; then
            failed=$((failed + 1)); dead_keys="$dead_keys GitHub($gh_status)"
        fi
    fi

    # Qonto
    if [ -n "${QONTO_SLUG:-}" ] && [ -n "${QONTO_SECRET_KEY:-}" ]; then
        checked=$((checked + 1))
        local qt_status
        qt_status=$(curl -s -o /dev/null -w "%{http_code}" -m 5 \
            -H "Authorization: ${QONTO_SLUG}:${QONTO_SECRET_KEY}" \
            https://thirdparty.qonto.com/v2/organization 2>/dev/null || echo "000")
        if [ "$qt_status" = "401" ] || [ "$qt_status" = "403" ]; then
            failed=$((failed + 1)); dead_keys="$dead_keys Qonto($qt_status)"
        fi
    fi

    if [ "$failed" -gt 0 ]; then
        _hb_log WARN "API keys DEAD:$dead_keys ($failed/$checked failed)"
        return 1
    fi

    _hb_log INFO "API keys OK: $checked checked, 0 failed"
    return 0
}

# ────────────────────────────────────────────────────────────
# Dispatcher — maps check ID to handler
# ────────────────────────────────────────────────────────────

dispatch_check() {
    local check_id="$1"

    case "$check_id" in
        disk)             handler_disk ;;
        ram)              handler_ram ;;
        alba-process)     handler_alba_process ;;
        tmux-session)     handler_tmux_session ;;
        standing-orders)  handler_standing_orders ;;
        memory-db)        handler_memory_db ;;
        goals)            handler_goals ;;
        telegram)         handler_telegram ;;
        email)            handler_email ;;
        api-keys)         handler_api_keys ;;
        *)
            _hb_log WARN "Unknown check ID: $check_id"
            return 1
            ;;
    esac
}

# ────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────

main() {
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        echo "ERROR: Heartbeat file not found: $HEARTBEAT_FILE" >&2
        exit 1
    fi

    _hb_log INFO "Heartbeat starting — file: $HEARTBEAT_FILE"

    local total=0
    local passed=0
    local triggered=0

    # Parse check IDs from HEARTBEAT.md
    # Match lines like "- [ ] [check-id] Description"
    local check_ids
    check_ids=$(grep -oE '\[([a-z][a-z0-9-]*)\]' "$HEARTBEAT_FILE" | \
                grep -v '^\[ \]$' | \
                grep -v '^\[x\]$' | \
                sed 's/\[//g; s/\]//g' | \
                sort -u)

    if [ -z "$check_ids" ]; then
        _hb_log WARN "No check IDs found in $HEARTBEAT_FILE"
        echo "No check IDs found in heartbeat file."
        exit 0
    fi

    while IFS= read -r check_id; do
        [ -z "$check_id" ] && continue
        total=$((total + 1))

        if dispatch_check "$check_id"; then
            passed=$((passed + 1))
        else
            triggered=$((triggered + 1))
        fi
    done <<< "$check_ids"

    _hb_log INFO "Heartbeat complete: $passed/$total passed, $triggered triggered" \
        "{\"passed\":$passed,\"triggered\":$triggered,\"total\":$total}"

    echo "Heartbeat: $passed/$total passed, $triggered triggered"
}

main
