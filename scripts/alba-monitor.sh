#!/usr/bin/env bash
# alba-monitor.sh — Proactive system monitoring with threshold detection and escalation
#
# Checks: memory, disk, DB size, error rate, process liveness.
# Fires send_alert() on WARNING/CRITICAL, escalates via send_alert_escalated()
# when a metric stays CRITICAL for ESCALATION_THRESHOLD consecutive runs.
#
# Designed to run from cron/launchd every 60s.
#
# Usage:
#   bash scripts/alba-monitor.sh          # run all checks once
#   bash scripts/alba-monitor.sh --check memory   # run single check

set -u

# Explicit PATH for cron/launchd
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# Load env
[ -f "$HOME/.alba/.env" ] && { set -a; source "$HOME/.alba/.env"; set +a; }

# Source shared libraries from same directory
_MONITOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_MONITOR_DIR/alba-log.sh"
source "$_MONITOR_DIR/alba-alert.sh"

# DB paths
ALBA_LOGS_DB="${ALBA_LOGS_DB:-$HOME/.alba/alba-logs.db}"
ALBA_MEMORY_DB="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"

# Escalation config
ESCALATION_DIR="${ESCALATION_DIR:-/tmp}"
ESCALATION_THRESHOLD="${ESCALATION_THRESHOLD:-5}"

# ---- Metric check functions ----
# Each prints: status value
# status: ok | warning | critical

check_memory() {
    local pid
    pid=$(pgrep -f 'claude.*--dangerously-skip-permissions' 2>/dev/null | head -1)
    if [ -z "$pid" ]; then
        alba_log INFO alba-monitor "No Claude process found — skipping memory check"
        echo "ok 0"
        return
    fi
    local rss_mb
    rss_mb=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}')
    if [ -z "$rss_mb" ] || [ "$rss_mb" -eq 0 ]; then
        echo "ok 0"
        return
    fi
    if [ "$rss_mb" -gt 5500 ]; then
        echo "critical $rss_mb"
    elif [ "$rss_mb" -gt 4000 ]; then
        echo "warning $rss_mb"
    else
        echo "ok $rss_mb"
    fi
}

check_disk() {
    local pct
    pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [ "$pct" -gt 95 ]; then
        echo "critical $pct"
    elif [ "$pct" -gt 80 ]; then
        echo "warning $pct"
    else
        echo "ok $pct"
    fi
}

check_db_size() {
    local worst_status="ok"
    local worst_val=0

    # alba-logs.db: warning >100MB, critical >500MB
    if [ -f "$ALBA_LOGS_DB" ]; then
        local logs_bytes logs_mb
        logs_bytes=$(stat -f%z "$ALBA_LOGS_DB" 2>/dev/null || echo 0)
        logs_mb=$((logs_bytes / 1048576))
        if [ "$logs_mb" -gt 500 ]; then
            worst_status="critical"
            worst_val=$logs_mb
        elif [ "$logs_mb" -gt 100 ]; then
            if [ "$worst_status" != "critical" ]; then
                worst_status="warning"
                worst_val=$logs_mb
            fi
        fi
    fi

    # alba-memory.db: warning >200MB, critical >1024MB
    if [ -f "$ALBA_MEMORY_DB" ]; then
        local mem_bytes mem_mb
        mem_bytes=$(stat -f%z "$ALBA_MEMORY_DB" 2>/dev/null || echo 0)
        mem_mb=$((mem_bytes / 1048576))
        if [ "$mem_mb" -gt 1024 ]; then
            worst_status="critical"
            worst_val=$mem_mb
        elif [ "$mem_mb" -gt 200 ]; then
            if [ "$worst_status" != "critical" ]; then
                worst_status="warning"
                worst_val=$mem_mb
            fi
        fi
    fi

    echo "$worst_status $worst_val"
}

check_error_rate() {
    if [ ! -f "$ALBA_LOGS_DB" ]; then
        echo "ok 0"
        return
    fi
    local count
    count=$(/usr/bin/sqlite3 "$ALBA_LOGS_DB" "PRAGMA busy_timeout = 3000; SELECT COUNT(*) FROM logs WHERE level IN ('ERROR','CRITICAL') AND timestamp > datetime('now','-5 minutes');" 2>/dev/null | tail -1)
    count="${count:-0}"
    if [ "$count" -gt 50 ]; then
        echo "critical $count"
    elif [ "$count" -gt 10 ]; then
        echo "warning $count"
    else
        echo "ok $count"
    fi
}

check_process() {
    local pid
    pid=$(pgrep -f 'claude.*--dangerously-skip-permissions' 2>/dev/null | head -1)
    if [ -z "$pid" ]; then
        echo "critical 0"
    else
        echo "ok $pid"
    fi
}

check_context_pressure() {
    local counter_file="${COUNTER_FILE:-/tmp/alba-tool-counter}"
    local count=0
    if [ -f "$counter_file" ]; then
        count=$(cat "$counter_file" 2>/dev/null || echo 0)
        # Sanitize to integer
        count=$((count + 0)) 2>/dev/null || count=0
    fi

    if [ "$count" -ge 100 ]; then
        echo "critical $count"
    elif [ "$count" -ge 50 ]; then
        echo "warning $count"
    else
        echo "ok $count"
    fi
}

# ---- Escalation tracking ----

track_escalation() {
    local metric_name="$1"
    local status="$2"
    local message="$3"
    local esc_file="${ESCALATION_DIR}/alba-monitor-escalation-${metric_name}"

    if [ "$status" = "critical" ]; then
        local count=0
        if [ -f "$esc_file" ]; then
            count=$(cat "$esc_file" 2>/dev/null || echo 0)
        fi
        count=$((count + 1))
        echo "$count" > "$esc_file"
        if [ "$count" -ge "$ESCALATION_THRESHOLD" ]; then
            send_alert_escalated "monitor-${metric_name}" "SUSTAINED CRITICAL: ${message} (${count} consecutive checks)"
            alba_log CRITICAL alba-monitor "Escalated ${metric_name} — ${count} consecutive critical checks"
        fi
    else
        # Reset escalation counter
        echo "0" > "$esc_file"
    fi
}

# ---- Run a single metric check ----

run_check() {
    local name="$1"
    local result status value
    result=$("check_${name}")
    status=$(echo "$result" | awk '{print $1}')
    value=$(echo "$result" | awk '{print $2}')

    # Log result
    local log_level="INFO"
    case "$status" in
        warning)  log_level="WARN" ;;
        critical) log_level="ERROR" ;;
    esac

    alba_log "$log_level" alba-monitor "${name}=${value} status=${status}"

    # Alert on warning/critical
    if [ "$status" = "warning" ]; then
        send_alert "monitor-${name}" "WARNING: ${name}=${value}"
    elif [ "$status" = "critical" ]; then
        send_alert "monitor-${name}" "CRITICAL: ${name}=${value}"
        track_escalation "$name" "$status" "${name}=${value}"
    else
        # Clear escalation on recovery
        track_escalation "$name" "$status" ""
    fi

    echo "$status"
}

# ---- Main ----

main() {
    local checks=("memory" "disk" "db_size" "error_rate" "process" "context_pressure")
    local single_check=""

    # Parse args
    while [ $# -gt 0 ]; do
        case "$1" in
            --check) single_check="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -n "$single_check" ]; then
        run_check "$single_check"
    else
        for check in "${checks[@]}"; do
            run_check "$check"
        done
    fi
}

# Only run main when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
