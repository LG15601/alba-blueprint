#!/bin/bash
# ==========================================================
# Alba — Claude Code always-on launcher with watchdog
# Usage: start-alba.sh [start|stop|status|restart]
# ==========================================================
set -u  # Error on unset variables (but not -e, watchdog must not exit)

# ---- PATH for launchd (brew tools not in default launchd PATH) ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SESSION="alba-agent"
CLAUDE="$(command -v claude 2>/dev/null || echo '/opt/homebrew/bin/claude')"
WATCHDOG_INTERVAL=120         # seconds between health checks
MAX_RAM_MB=6000               # restart if RSS exceeds this
MAX_CONSECUTIVE_FAILS=3       # health check failures before restart
MAX_RESTARTS_PER_HOUR=10      # circuit breaker — stop restarting if too many
ALBA_PROJECT_DIR="$HOME/AZW/alba-blueprint"
LOG_FILE="$HOME/logs/alba-agent.log"
LOG_TAG="alba-agent"
PIDFILE="/tmp/alba-watchdog.pid"
RESTART_HISTORY_FILE="/tmp/alba-restart-history"
START_TIME_FILE="/tmp/alba-start-time"

# ---- Keepalive config ----
KEEPALIVE_INTERVAL=20         # seconds between idle-prompt nudge checks
IDLE_PROMPT_PATTERN='❯'       # prompt character indicating idle REPL
NUDGE_COUNT_FILE="/tmp/alba-nudge-count"

# ---- Alert config ----
ALERT_COOLDOWN=600            # seconds between repeated alerts of the same type
ALERT_DIR="/tmp"              # directory for rate-limit timestamp files

# ---- Shared structured logging ----
SCRIPT_DIR_LOG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_LOG/alba-log.sh"
source "$SCRIPT_DIR_LOG/alba-alert.sh"

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    alba_log INFO watchdog "$1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "$msg" >> "$LOG_FILE"
}

# ---- Log rotation (keep last 500 lines) ----
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 1000 ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "Log rotated (kept last 500 lines)"
    fi
}

# ---- PID management ----
check_already_running() {
    if [ -f "$PIDFILE" ]; then
        local old_pid
        old_pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            # Another watchdog is running — only allow stop/status/restart
            if [ "${1:-}" = "stop" ] || [ "${1:-}" = "status" ] || [ "${1:-}" = "restart" ]; then
                return 0
            fi
            log "ERROR: Another watchdog already running (PID $old_pid). Use 'stop' first."
            exit 1
        fi
    fi
}

write_pid() {
    echo $$ > "$PIDFILE"
}

cleanup_pid() {
    rm -f "$PIDFILE"
}

# ---- Process detection ----
get_claude_pid() {
    pgrep -f "claude.*channels.*telegram" 2>/dev/null | head -1
}

get_any_claude_pid() {
    # Broader match: any Claude process (with or without telegram channel)
    pgrep -f "claude.*--dangerously-skip-permissions" 2>/dev/null | head -1
}

get_ram_mb() {
    local pid="$1"
    if [ -n "$pid" ]; then
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}'
    else
        echo "0"
    fi
}

get_uptime_display() {
    if [ ! -f "$START_TIME_FILE" ]; then
        echo "unknown"
        return
    fi
    local start_ts now elapsed days hours mins
    start_ts=$(cat "$START_TIME_FILE" 2>/dev/null || echo "0")
    now=$(date +%s)
    elapsed=$((now - start_ts))
    if [ "$elapsed" -lt 0 ]; then
        echo "unknown"
        return
    fi
    days=$((elapsed / 86400))
    hours=$(( (elapsed % 86400) / 3600 ))
    mins=$(( (elapsed % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
        echo "${days}d ${hours}h"
    elif [ "$hours" -gt 0 ]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# ---- Circuit breaker: too many restarts = stop trying ----
record_restart() {
    echo "$(date +%s)" >> "$RESTART_HISTORY_FILE"
}

restarts_last_hour() {
    local now cutoff count
    now=$(date +%s)
    cutoff=$((now - 3600))
    count=0
    if [ -f "$RESTART_HISTORY_FILE" ]; then
        while IFS= read -r ts; do
            if [ "$ts" -ge "$cutoff" ] 2>/dev/null; then
                count=$((count + 1))
            fi
        done < "$RESTART_HISTORY_FILE"
    fi
    echo "$count"
}

prune_restart_history() {
    local now cutoff
    now=$(date +%s)
    cutoff=$((now - 3600))
    if [ -f "$RESTART_HISTORY_FILE" ]; then
        awk -v c="$cutoff" '$1 >= c' "$RESTART_HISTORY_FILE" > "${RESTART_HISTORY_FILE}.tmp" \
            && mv "${RESTART_HISTORY_FILE}.tmp" "$RESTART_HISTORY_FILE"
    fi
}

# ---- Kill ----
kill_orphans() {
    pkill -f "claude.*channels.*telegram" 2>/dev/null
    pkill -f "bun.*telegram" 2>/dev/null
    sleep 1
}

# ---- Keepalive: nudge idle REPL ----
nudge_if_idle() {
    # Capture tmux pane, strip ANSI escape codes, get last non-empty line
    local pane_raw last_line
    pane_raw=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null) || return 1
    last_line=$(echo "$pane_raw" \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -v '^[[:space:]]*$' \
        | tail -1)

    # Only nudge if the last line is just the prompt character (with optional whitespace)
    # This avoids nudging during active output, tool calls, or multi-line responses
    if echo "$last_line" | grep -qE "^[[:space:]]*${IDLE_PROMPT_PATTERN}[[:space:]]*$"; then
        tmux send-keys -t "$SESSION" Enter 2>/dev/null
        # Increment nudge counter (safe under set -e)
        local count=0
        if [ -f "$NUDGE_COUNT_FILE" ]; then
            count=$(cat "$NUDGE_COUNT_FILE" 2>/dev/null || echo "0")
        fi
        count=$((count + 1))
        echo "$count" > "$NUDGE_COUNT_FILE"
        log "KEEPALIVE: nudged (idle prompt detected, nudge #${count})"
        return 0
    fi
    return 1
}

# ---- Preflight checks ----
preflight() {
    local ok=true

    if ! command -v tmux >/dev/null 2>&1; then
        log "FATAL: tmux not found in PATH ($PATH)"
        ok=false
    fi

    if ! command -v "$CLAUDE" >/dev/null 2>&1 && [ ! -x "$CLAUDE" ]; then
        log "FATAL: claude not found ($CLAUDE)"
        ok=false
    fi

    if [ ! -d "$ALBA_PROJECT_DIR" ]; then
        log "FATAL: project directory missing ($ALBA_PROJECT_DIR)"
        ok=false
    fi

    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

    if [ "$ok" = false ]; then
        exit 1
    fi
}

# ---- Launch ----
launch_claude() {
    local restart_count
    restart_count=$(restarts_last_hour)

    if [ "$restart_count" -ge "$MAX_RESTARTS_PER_HOUR" ]; then
        log "CIRCUIT BREAKER: $restart_count restarts in last hour (max $MAX_RESTARTS_PER_HOUR). Sleeping 10min."
        sleep 600
        prune_restart_history
        return 1
    fi

    log "Launching Alba... (restarts this hour: $restart_count)"
    tmux kill-session -t "$SESSION" 2>/dev/null
    kill_orphans
    sleep 1

    # Load environment (safely handle values with spaces)
    if [ -f "$HOME/.alba/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        source "$HOME/.alba/.env"
        set +a
    fi

    # Launch with channels
    tmux new-session -d -s "$SESSION" \
        "cd '$ALBA_PROJECT_DIR' && '$CLAUDE' --dangerously-skip-permissions --channels 'plugin:telegram@claude-plugins-official' ; echo '[ALBA EXITED with code '\$?']' ; sleep infinity"

    # Wait for Claude to initialize
    sleep 10
    # Accept any startup dialog (settings update prompt)
    tmux send-keys -t "$SESSION" Enter 2>/dev/null
    sleep 15

    local cpid
    cpid=$(get_claude_pid)
    if [ -n "$cpid" ]; then
        record_restart
        date +%s > "$START_TIME_FILE"
        log "Alba started (PID $cpid, RAM $(get_ram_mb "$cpid")MB)"
        return 0
    else
        log "WARNING: Claude process not found after launch"
        # Capture what's in the tmux pane for debugging
        local pane_content
        pane_content=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | tail -5)
        log "tmux pane: $pane_content"
        return 1
    fi
}

# ---- Health check ----
is_healthy() {
    # Check 1: tmux session exists
    if ! tmux has-session -t "$SESSION" 2>/dev/null; then
        log "UNHEALTHY: tmux session '$SESSION' not found"
        return 1
    fi

    # Check 2: Claude process exists
    local cpid
    cpid=$(get_claude_pid)
    if [ -z "$cpid" ]; then
        log "UNHEALTHY: Claude process not found (session exists but no claude PID)"
        return 1
    fi

    # Check 3: RAM within limits
    local ram
    ram=$(get_ram_mb "$cpid")
    if [ "$ram" -gt "$MAX_RAM_MB" ]; then
        log "UNHEALTHY: RAM too high (${ram}MB > ${MAX_RAM_MB}MB) — will restart"
        return 1
    fi

    # Check 4: OAuth not expired (detect auth failures in tmux output)
    local pane
    pane=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null | tail -20)
    if echo "$pane" | grep -q "OAuth token has expired\|Please run /login"; then
        log "AUTH EXPIRED: OAuth token expired — restart won't fix this. Run: tmux attach -t $SESSION → /login"
        # Touch a signal file so external monitoring can detect this
        echo "$(date '+%Y-%m-%d %H:%M:%S') OAuth token expired" > /tmp/alba-auth-expired
        send_alert "auth" "OAuth token expired — manual /login required"
        # Don't return unhealthy — restarting won't help. Just keep logging.
        return 0
    fi

    # Clear auth-expired signal if we're past it
    rm -f /tmp/alba-auth-expired 2>/dev/null

    return 0
}

# ==== Command handling ====

case "${1:-start}" in
    stop)
        log "Stopping Alba..."
        tmux kill-session -t "$SESSION" 2>/dev/null
        kill_orphans
        # Kill the watchdog too
        if [ -f "$PIDFILE" ]; then
            wpid=$(cat "$PIDFILE" 2>/dev/null)
            if [ -n "$wpid" ] && [ "$wpid" != "$$" ]; then
                kill "$wpid" 2>/dev/null
            fi
            rm -f "$PIDFILE"
        fi
        rm -f "$NUDGE_COUNT_FILE"
        rm -f "$START_TIME_FILE"
        rm -f "${ALERT_DIR}"/alba-last-alert-* 2>/dev/null
        log "Stopped"
        exit 0
        ;;
    status)
        # Priority: STOPPED → DEGRADED → AUTH_EXPIRED → TELEGRAM_DEAD → BUSY → HEALTHY
        if ! tmux has-session -t "$SESSION" 2>/dev/null; then
            echo "STOPPED — no tmux session"
            exit 0
        fi

        # Session exists — check for any Claude process (broad match)
        cpid=$(get_any_claude_pid)
        if [ -z "$cpid" ]; then
            echo "DEGRADED — tmux session exists but Claude process not found"
            exit 0
        fi

        # Claude is running — gather common stats
        ram=$(get_ram_mb "$cpid")
        restarts=$(restarts_last_hour)
        uptime_str=$(get_uptime_display)

        # AUTH_EXPIRED check
        if [ -f /tmp/alba-auth-expired ]; then
            echo "AUTH_EXPIRED — Claude PID $cpid running but OAuth token expired (uptime: $uptime_str). Run: tmux attach -t $SESSION → /login"
            exit 0
        fi

        # TELEGRAM_DEAD: Claude is running but no telegram channel process
        telegram_pid=$(pgrep -f "claude.*channels.*telegram" 2>/dev/null | head -1 || true)
        if [ -z "$telegram_pid" ]; then
            echo "TELEGRAM_DEAD — Claude PID $cpid running but Telegram channel not connected (uptime: $uptime_str)"
            exit 0
        fi

        # BUSY vs HEALTHY: check if idle prompt is showing
        pane_raw=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)
        last_line=$(echo "$pane_raw" \
            | sed 's/\x1b\[[0-9;]*m//g' \
            | grep -v '^[[:space:]]*$' \
            | tail -1)

        nudges=0
        if [ -f "$NUDGE_COUNT_FILE" ]; then
            nudges=$(cat "$NUDGE_COUNT_FILE" 2>/dev/null || echo "0")
        fi

        if echo "$last_line" | grep -qE "^[[:space:]]*${IDLE_PROMPT_PATTERN}[[:space:]]*$"; then
            echo "HEALTHY — Claude PID $cpid idle ($uptime_str uptime, ${ram}MB RAM, restarts/hour: $restarts, nudges: $nudges)"
        else
            echo "BUSY — Claude PID $cpid actively processing ($uptime_str uptime, ${ram}MB RAM, restarts/hour: $restarts)"
        fi
        exit 0
        ;;
    restart)
        log "Restart requested..."
        tmux kill-session -t "$SESSION" 2>/dev/null
        kill_orphans
        sleep 2
        # Fall through to start
        ;;
    start)
        ;;
    *)
        echo "Usage: start-alba.sh [start|stop|status|restart]"
        exit 1
        ;;
esac

# ==== Start + watchdog ====

preflight
check_already_running "${1:-start}"
write_pid
trap cleanup_pid EXIT

# Initial launch
launch_claude
rotate_log

# Watchdog loop
log "Watchdog started (PID $$, check every ${WATCHDOG_INTERVAL}s, max RAM ${MAX_RAM_MB}MB, max restarts/hour $MAX_RESTARTS_PER_HOUR)"
FAIL_COUNT=0

while true; do
    # Sub-loop: sleep in KEEPALIVE_INTERVAL increments, nudging each time
    elapsed=0
    while [ "$elapsed" -lt "$WATCHDOG_INTERVAL" ]; do
        sleep "$KEEPALIVE_INTERVAL"
        elapsed=$((elapsed + KEEPALIVE_INTERVAL))
        nudge_if_idle
    done

    if is_healthy; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "Health check failed ($FAIL_COUNT/$MAX_CONSECUTIVE_FAILS)"

        if [ "$FAIL_COUNT" -ge "$MAX_CONSECUTIVE_FAILS" ]; then
            log "Restarting Alba..."
            FAIL_COUNT=0
            launch_claude
            rotate_log
        fi
    fi
done
