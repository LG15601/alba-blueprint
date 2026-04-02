#!/usr/bin/env bash
# alba-standing-orders.sh — Standing orders engine
#
# Parses ~/.alba/standing-orders.md for scheduled HH:MM entries,
# checks which are due (±15 min window, not already executed),
# executes them, and records results in SQLite.
#
# Usage:
#   bash scripts/alba-standing-orders.sh              # execute due orders
#   bash scripts/alba-standing-orders.sh --check      # dry-run: list due orders
#
# Environment:
#   ALBA_LOGS_DB        — logs database (default: ~/.alba/alba-logs.db)
#   ALBA_MEMORY_DB      — memory database (default: ~/.alba/alba-memory.db)
#   STANDING_ORDERS_FILE — orders file (default: ~/.alba/standing-orders.md)
#
# Constraints (KNOWLEDGE.md):
#   - var=$((var + 1)) not ((var++)) under set -e
#   - sqlite3 PRAGMA output to /dev/null
#   - mkdir-based locking (no flock on macOS)
#   - Never write to stdout from captured functions

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
ALBA_MEMORY_DB="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
STANDING_ORDERS_FILE="${STANDING_ORDERS_FILE:-$HOME/.alba/standing-orders.md}"
CHECK_MODE=false
LOCK_DIR="/tmp/alba-standing-orders.lock"
LOCK_STALE_SECONDS=1800  # 30 minutes
TIME_WINDOW_MINUTES=15

if [ "${1:-}" = "--check" ]; then
    CHECK_MODE=true
fi

# ── Logging helpers (never write to stdout) ──────────────────
_so_log() {
    alba_log "$1" standing-orders "$2" "${3:-}" 2>/dev/null || true
}

# ── Locking (mkdir-based, macOS-compatible) ──────────────────
acquire_lock() {
    # Check for stale lock
    if [ -d "$LOCK_DIR" ]; then
        local lock_age
        if [ "$(uname)" = "Darwin" ]; then
            lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0) ))
        else
            lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0) ))
        fi
        if [ "$lock_age" -gt "$LOCK_STALE_SECONDS" ]; then
            _so_log WARN "Removing stale lock (age: ${lock_age}s)"
            rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR"
        fi
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        _so_log WARN "Another instance is running (lock exists)"
        echo "LOCKED: Another instance is running" >&2
        exit 0
    fi
}

release_lock() {
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

# ── Slug generator ───────────────────────────────────────────
# Converts a description to a stable order_id slug
make_slug() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-60
}

# ── Time window matching ────────────────────────────────────
# Returns 0 if current time is within ±TIME_WINDOW_MINUTES of target HH:MM
is_in_window() {
    local target_hhmm="$1"
    local now_minutes="$2"

    local target_hour target_min target_minutes
    target_hour=$(echo "$target_hhmm" | cut -d: -f1 | sed 's/^0//')
    target_min=$(echo "$target_hhmm" | cut -d: -f2 | sed 's/^0//')
    target_hour="${target_hour:-0}"
    target_min="${target_min:-0}"
    target_minutes=$((target_hour * 60 + target_min))

    local diff=$((now_minutes - target_minutes))
    # Handle midnight wrap
    if [ "$diff" -gt 720 ]; then
        diff=$((diff - 1440))
    elif [ "$diff" -lt -720 ]; then
        diff=$((diff + 1440))
    fi

    # Absolute value
    if [ "$diff" -lt 0 ]; then
        diff=$(( -diff ))
    fi

    [ "$diff" -le "$TIME_WINDOW_MINUTES" ]
}

# ── Check if already executed in current window ──────────────
already_executed() {
    local order_id="$1"
    local scheduled_time="$2"

    # Look for execution within the last TIME_WINDOW_MINUTES*2 minutes
    local window_seconds=$((TIME_WINDOW_MINUTES * 2 * 60))
    local cutoff
    cutoff=$(date -u -v-${window_seconds}S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
             date -u -d "${window_seconds} seconds ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
             echo "1970-01-01T00:00:00Z")

    local count
    count=$(/usr/bin/sqlite3 "$ALBA_MEMORY_DB" \
        "SELECT COUNT(*) FROM standing_order_executions WHERE order_id = '$order_id' AND scheduled_time = '$scheduled_time' AND executed_at > '$cutoff';" 2>/dev/null || echo "0")

    [ "$count" -gt 0 ]
}

# ── Record execution ─────────────────────────────────────────
record_execution() {
    local order_id="$1"
    local scheduled_time="$2"
    local result="$3"
    local duration_ms="$4"
    local exit_code="$5"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Sanitize result for SQL (escape single quotes, truncate to 1000 chars)
    local safe_result
    safe_result=$(echo "$result" | head -c 1000 | sed "s/'/''/g")

    /usr/bin/sqlite3 "$ALBA_MEMORY_DB" <<SQL > /dev/null 2>&1 || true
PRAGMA busy_timeout = 3000;
INSERT INTO standing_order_executions (order_id, scheduled_time, executed_at, result, duration_ms, exit_code)
VALUES ('$order_id', '$scheduled_time', '$timestamp', '$safe_result', $duration_ms, $exit_code);
SQL
}

# ── Parse standing orders file ───────────────────────────────
# Extracts lines matching "- HH:MM — Description" pattern
# Outputs: HH:MM|||description (one per line)
parse_orders() {
    local file="$1"
    if [ ! -f "$file" ]; then
        _so_log ERROR "Standing orders file not found: $file"
        return 1
    fi

    # Match lines like "- 07:00 — Morning briefing (...)"
    # Uses perl for reliable UTF-8 em-dash handling (macOS sed chokes on multi-byte)
    grep -E '^\s*-\s+[0-9]{2}:[0-9]{2}' "$file" | \
        perl -CSD -pe 's/^\s*-\s+(\d{2}:\d{2})\s*[\x{2014}\x{2013}\-]+\s*/$1|||/' || true
}

# ── Main ─────────────────────────────────────────────────────
main() {
    # Validate DB exists (or at least the table)
    if [ ! -f "$ALBA_MEMORY_DB" ]; then
        echo "ERROR: Memory database not found: $ALBA_MEMORY_DB" >&2
        echo "Run: bash scripts/alba-memory-init.sh" >&2
        exit 1
    fi

    # Check table exists
    if ! /usr/bin/sqlite3 "$ALBA_MEMORY_DB" "SELECT 1 FROM standing_order_executions LIMIT 0;" >/dev/null 2>&1; then
        echo "ERROR: standing_order_executions table not found. Run migrations." >&2
        exit 1
    fi

    if [ "$CHECK_MODE" = false ]; then
        acquire_lock
        trap release_lock EXIT
    fi

    # Current time in minutes since midnight
    local now_hour now_min now_minutes
    now_hour=$(date +%H | sed 's/^0//')
    now_min=$(date +%M | sed 's/^0//')
    now_hour="${now_hour:-0}"
    now_min="${now_min:-0}"
    now_minutes=$((now_hour * 60 + now_min))

    _so_log INFO "Starting scan (mode: $([ "$CHECK_MODE" = true ] && echo 'check' || echo 'execute'), time: $(date +%H:%M))"

    local due_count=0
    local exec_count=0
    local skip_count=0

    # Parse orders and process each
    local orders
    orders=$(parse_orders "$STANDING_ORDERS_FILE") || exit 1

    if [ -z "$orders" ]; then
        _so_log INFO "No scheduled orders found in $STANDING_ORDERS_FILE"
        echo "No scheduled orders found."
        exit 0
    fi

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        local hhmm description order_id
        hhmm=$(echo "$line" | awk -F'\\|\\|\\|' '{print $1}')
        description=$(echo "$line" | awk -F'\\|\\|\\|' '{print $2}')
        order_id=$(make_slug "$description")

        # Check if in time window
        if ! is_in_window "$hhmm" "$now_minutes"; then
            continue
        fi

        # Check if already executed
        if already_executed "$order_id" "$hhmm"; then
            skip_count=$((skip_count + 1))
            if [ "$CHECK_MODE" = true ]; then
                echo "SKIP: $hhmm — $description (already executed)"
            fi
            _so_log DEBUG "Skipping $order_id — already executed in window"
            continue
        fi

        due_count=$((due_count + 1))

        if [ "$CHECK_MODE" = true ]; then
            echo "DUE:  $hhmm — $description"
            continue
        fi

        # Execute the order
        _so_log INFO "Executing order: $order_id ($hhmm — $description)"

        local start_ms result exit_code end_ms duration_ms
        start_ms=$(($(date +%s) * 1000))

        # For now, shell-type orders log execution but don't run arbitrary commands.
        # The description is recorded; actual dispatch will be wired in future tasks.
        result="Standing order triggered: $description"
        exit_code=0

        end_ms=$(($(date +%s) * 1000))
        duration_ms=$((end_ms - start_ms))

        record_execution "$order_id" "$hhmm" "$result" "$duration_ms" "$exit_code"
        exec_count=$((exec_count + 1))

        _so_log INFO "Completed order: $order_id (exit: $exit_code, ${duration_ms}ms)"

    done <<< "$orders"

    # Summary
    if [ "$CHECK_MODE" = true ]; then
        echo "---"
        echo "Due: $due_count | Skipped (already run): $skip_count"
    else
        _so_log INFO "Scan complete: $exec_count executed, $skip_count skipped, $due_count due"
        echo "Standing orders: $exec_count executed, $skip_count skipped"
    fi
}

main "$@"
