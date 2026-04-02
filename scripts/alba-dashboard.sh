#!/usr/bin/env bash
# alba-dashboard.sh — Terminal dashboard showing green/yellow/red status per subsystem
#
# Pure read-only: no writes, no alerts, no log entries.
# Gracefully handles missing components (no Claude process, missing DBs, etc.)
#
# Usage:
#   bash scripts/alba-dashboard.sh          # show dashboard once
#   bash scripts/alba-dashboard.sh --watch   # refresh every 10s

set -u

# Explicit PATH for cron/launchd
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# Load env
[ -f "$HOME/.alba/.env" ] && { set -a; source "$HOME/.alba/.env"; set +a; }

# DB paths (consistent with alba-log.sh / alba-monitor.sh)
ALBA_LOGS_DB="${ALBA_LOGS_DB:-$HOME/.alba/alba-logs.db}"
ALBA_MEMORY_DB="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
ESCALATION_DIR="${ESCALATION_DIR:-/tmp}"

# ---- Colors ----
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ---- Helpers ----

# status_icon <status>  →  colored ● with label
# status: ok | warning | critical
status_icon() {
    case "$1" in
        ok)       printf "${GREEN}●${RESET} %-10s" "OK" ;;
        warning)  printf "${YELLOW}●${RESET} %-10s" "WARNING" ;;
        critical) printf "${RED}●${RESET} %-10s" "CRITICAL" ;;
        *)        printf "○ %-10s" "UNKNOWN" ;;
    esac
}

# human_bytes <bytes>  →  e.g. "142MB"
human_mb() {
    local mb="$1"
    if [ "$mb" -ge 1024 ]; then
        echo "$((mb / 1024))GB"
    else
        echo "${mb}MB"
    fi
}

# ---- Section renderers ----
# Each outputs one formatted line. No side effects.

render_process() {
    local pid
    pid=$(pgrep -f 'claude.*--dangerously-skip-permissions' 2>/dev/null | head -1)
    if [ -z "$pid" ]; then
        printf "  Claude Process:  "
        status_icon "critical"
        printf "NOT RUNNING\n"
        return
    fi

    local rss_mb
    rss_mb=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    rss_mb="${rss_mb:-0}"

    # Uptime from start-time marker
    local uptime_str=""
    if [ -f "/tmp/alba-start-time" ]; then
        local start_epoch now_epoch diff_s
        start_epoch=$(cat /tmp/alba-start-time 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        if [ "$start_epoch" -gt 0 ] 2>/dev/null; then
            diff_s=$((now_epoch - start_epoch))
            local hours=$((diff_s / 3600))
            local mins=$(( (diff_s % 3600) / 60 ))
            uptime_str="  up ${hours}h${mins}m"
        fi
    fi

    # Color coding: same thresholds as alba-monitor.sh
    local status="ok"
    if [ "$rss_mb" -gt 5500 ]; then
        status="critical"
    elif [ "$rss_mb" -gt 4000 ]; then
        status="warning"
    fi

    printf "  Claude Process:  "
    status_icon "$status"
    printf "PID %s  RAM %s%s\n" "$pid" "$(human_mb "$rss_mb")" "$uptime_str"
}

render_disk() {
    local pct
    pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    pct="${pct:-0}"

    local status="ok"
    if [ "$pct" -gt 95 ]; then
        status="critical"
    elif [ "$pct" -gt 80 ]; then
        status="warning"
    fi

    printf "  Disk Usage:      "
    status_icon "$status"
    printf "%s%%\n" "$pct"
}

render_db() {
    local db_path="$1"
    local label="$2"
    local warn_mb="$3"
    local crit_mb="$4"

    if [ ! -f "$db_path" ]; then
        printf "  %-17s" "$label:"
        status_icon "ok"
        printf "not found\n"
        return
    fi

    local bytes mb
    bytes=$(stat -f%z "$db_path" 2>/dev/null || echo 0)
    mb=$((bytes / 1048576))

    local status="ok"
    if [ "$mb" -gt "$crit_mb" ]; then
        status="critical"
    elif [ "$mb" -gt "$warn_mb" ]; then
        status="warning"
    fi

    printf "  %-17s" "$label:"
    status_icon "$status"
    printf "%s\n" "$(human_mb "$mb")"
}

render_error_rate() {
    local count=0
    if [ -f "$ALBA_LOGS_DB" ]; then
        count=$(/usr/bin/sqlite3 "$ALBA_LOGS_DB" "PRAGMA busy_timeout = 3000; SELECT COUNT(*) FROM logs WHERE level IN ('ERROR','CRITICAL') AND timestamp > datetime('now','-5 minutes');" 2>/dev/null | tail -1)
        count="${count:-0}"
    fi

    local status="ok"
    if [ "$count" -gt 50 ]; then
        status="critical"
    elif [ "$count" -gt 10 ]; then
        status="warning"
    fi

    printf "  Error Rate:      "
    status_icon "$status"
    printf "%s errors (5min)\n" "$count"
}

render_context_pressure() {
    local counter_file="${COUNTER_FILE:-/tmp/alba-tool-counter}"
    local count=0
    if [ -f "$counter_file" ]; then
        count=$(cat "$counter_file" 2>/dev/null || echo 0)
        count=$((count + 0)) 2>/dev/null || count=0
    fi

    local status="ok"
    if [ "$count" -ge 100 ]; then
        status="critical"
    elif [ "$count" -ge 50 ]; then
        status="warning"
    fi

    printf "  Context Pressure:"
    status_icon "$status"
    printf "%s tool calls\n" "$count"
}

render_escalations() {
    local active=0
    local details=""
    for f in "${ESCALATION_DIR}"/alba-monitor-escalation-*; do
        [ -f "$f" ] || continue
        local metric count
        metric=$(basename "$f" | sed 's/alba-monitor-escalation-//')
        count=$(cat "$f" 2>/dev/null || echo 0)
        if [ "$count" -gt 0 ]; then
            active=$((active + 1))
            details="${details} ${metric}(${count})"
        fi
    done

    if [ "$active" -gt 0 ]; then
        printf "  Escalations:     "
        status_icon "warning"
        printf "%d active:%s\n" "$active" "$details"
    else
        printf "  Escalations:     "
        status_icon "ok"
        printf "no active escalations\n"
    fi
}

render_recent_alerts() {
    if [ ! -f "$ALBA_LOGS_DB" ]; then
        return
    fi

    local rows
    rows=$(/usr/bin/sqlite3 -separator '|' "$ALBA_LOGS_DB" \
        "PRAGMA busy_timeout = 3000; SELECT timestamp, level, message FROM logs WHERE level IN ('ERROR','CRITICAL') ORDER BY timestamp DESC LIMIT 3;" 2>/dev/null | grep -v '^[0-9]*$')

    if [ -z "$rows" ]; then
        return
    fi

    printf "\n  ${DIM}Recent alerts:${RESET}\n"
    while IFS='|' read -r ts level msg; do
        local color="$YELLOW"
        [ "$level" = "CRITICAL" ] && color="$RED"
        printf "    ${DIM}%s${RESET} ${color}%-8s${RESET} %s\n" "$ts" "$level" "$msg"
    done <<< "$rows"
}

# ---- Main ----

render_dashboard() {
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    printf "\n  ${BOLD}═══ Alba System Dashboard ═══${RESET}  %s\n\n" "$now"

    render_process
    render_disk
    render_db "$ALBA_LOGS_DB"   "Logs DB"   100 500
    render_db "$ALBA_MEMORY_DB" "Memory DB" 200 1024
    render_error_rate
    render_context_pressure
    render_escalations
    render_recent_alerts

    printf "\n"
}

main() {
    if [ "${1:-}" = "--watch" ]; then
        while true; do
            clear
            render_dashboard
            sleep 10
        done
    else
        render_dashboard
    fi
}

main "$@"
