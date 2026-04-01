#!/bin/bash
# ==========================================================
# Alba — Claude Code always-on launcher with watchdog
# Usage: start-alba.sh [start|stop|status]
# ==========================================================

SESSION="alba-agent"
CLAUDE="$(which claude 2>/dev/null || echo '/usr/local/bin/claude')"
WATCHDOG_INTERVAL=120
LOG_TAG="alba-agent"
MAX_RAM_MB=6000
MAX_CONSECUTIVE_FAILS=3
RESTART_COUNT_FILE="/tmp/alba-restart-count"

log() { logger -t "$LOG_TAG" "$1" 2>/dev/null; echo "[$(date '+%H:%M:%S')] $1"; }

get_claude_pid() {
    pgrep -f "claude.*channels.*telegram" 2>/dev/null | head -1
}

get_ram_mb() {
    local pid="$1"
    if [ -n "$pid" ]; then
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}'
    else
        echo "0"
    fi
}

increment_restart_count() {
    local count=0
    [ -f "$RESTART_COUNT_FILE" ] && count=$(cat "$RESTART_COUNT_FILE")
    count=$((count + 1))
    echo "$count" > "$RESTART_COUNT_FILE"
    echo "$count"
}

kill_orphans() {
    pkill -f "claude.*channels.*telegram" 2>/dev/null
    pkill -f "bun.*telegram" 2>/dev/null
    sleep 1
}

# --- stop ---
if [ "$1" = "stop" ]; then
    tmux kill-session -t "$SESSION" 2>/dev/null
    kill_orphans
    log "Stopped"
    exit 0
fi

# --- status ---
if [ "$1" = "status" ]; then
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        CPID=$(get_claude_pid)
        if [ -n "$CPID" ]; then
            RAM=$(get_ram_mb "$CPID")
            RESTARTS=$(cat "$RESTART_COUNT_FILE" 2>/dev/null || echo "0")
            echo "HEALTHY — Claude PID $CPID (${RAM}MB RAM), restarts: $RESTARTS"
        else
            echo "STARTING — tmux session exists but Claude not found yet"
        fi
    else
        echo "STOPPED — no tmux session"
    fi
    exit 0
fi

# --- start ---
tmux kill-session -t "$SESSION" 2>/dev/null
kill_orphans
sleep 1

launch_claude() {
    log "Launching Alba..."
    tmux kill-session -t "$SESSION" 2>/dev/null
    kill_orphans
    sleep 1

    # Load environment (safely handle values with spaces)
    if [ -f "$HOME/.alba/.env" ]; then
        set -a
        source "$HOME/.alba/.env"
        set +a
    fi

    # Launch with channels
    # Add more --channels flags as needed:
    #   --channels 'plugin:slack@claude-plugins-official'
    #   --channels 'plugin:imessage@claude-plugins-official'
    tmux new-session -d -s "$SESSION" \
        "$CLAUDE --dangerously-skip-permissions \
         --channels 'plugin:telegram@claude-plugins-official' \
         --channels 'plugin:discord@claude-plugins-official'"

    # Wait for trust dialog and accept
    sleep 6
    tmux send-keys -t "$SESSION" Enter
    sleep 15

    CPID=$(get_claude_pid)
    if [ -n "$CPID" ]; then
        local count=$(increment_restart_count)
        log "Alba started (PID $CPID, restart #$count)"
    else
        log "WARNING: Claude process not found after launch"
    fi
}

is_healthy() {
    tmux has-session -t "$SESSION" 2>/dev/null || return 1
    CPID=$(get_claude_pid)
    [ -z "$CPID" ] && return 1
    RAM=$(get_ram_mb "$CPID")
    if [ "$RAM" -gt "$MAX_RAM_MB" ]; then
        log "RAM too high (${RAM}MB > ${MAX_RAM_MB}MB)"
        return 1
    fi
    return 0
}

# Initial launch
launch_claude

# --- watchdog loop ---
log "Watchdog started (check every ${WATCHDOG_INTERVAL}s, max RAM ${MAX_RAM_MB}MB)"
FAIL_COUNT=0

while true; do
    sleep "$WATCHDOG_INTERVAL"
    if is_healthy; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "Health check failed ($FAIL_COUNT/$MAX_CONSECUTIVE_FAILS)"
        if [ "$FAIL_COUNT" -ge "$MAX_CONSECUTIVE_FAILS" ]; then
            log "Restarting Alba..."
            FAIL_COUNT=0
            launch_claude
        fi
    fi
done
