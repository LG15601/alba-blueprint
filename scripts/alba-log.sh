#!/usr/bin/env bash
# alba-log.sh — Shared structured logging library for all Alba components
#
# Usage:
#   source scripts/alba-log.sh
#   alba_log INFO watchdog "Health check passed"
#   alba_log ERROR hook "Failed to inject context" '{"hook":"inject-context"}'
#   alba_log_bg INFO hook "Non-blocking write"
#
# Environment:
#   ALBA_LOGS_DB  — override DB path (default: ~/.alba/alba-logs.db)
#
# Design constraints (see KNOWLEDGE.md):
#   - NEVER writes to stdout (subshell capture contamination)
#   - All sqlite3 calls fail-open with fallback to text log
#   - Uses /usr/bin/sqlite3 absolute path for cron compatibility

ALBA_LOGS_DB="${ALBA_LOGS_DB:-$HOME/.alba/alba-logs.db}"
ALBA_LOGS_FALLBACK="${ALBA_LOGS_FALLBACK:-$HOME/.alba/logs/alba-fallback.log}"

alba_log() {
    local level="${1:-INFO}"
    local source="${2:-unknown}"
    local message="${3:-}"
    local metadata="${4:-}"
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Validate level
    case "$level" in
        DEBUG|INFO|WARN|ERROR|CRITICAL) ;;
        *) level="INFO" ;;
    esac

    # Attempt structured write to SQLite
    /usr/bin/sqlite3 "$ALBA_LOGS_DB" <<SQL > /dev/null 2>&1 || {
PRAGMA busy_timeout = 3000;
PRAGMA journal_mode = WAL;
INSERT INTO logs (timestamp, level, source, message, metadata)
VALUES ('$timestamp', '$level', '$(echo "$source" | sed "s/'/''/g")', '$(echo "$message" | sed "s/'/''/g")', '$(echo "$metadata" | sed "s/'/''/g")');
SQL
        # Fallback: append to text log
        mkdir -p "$(dirname "$ALBA_LOGS_FALLBACK")" 2>/dev/null
        echo "[$timestamp] $level $source: $message" >> "$ALBA_LOGS_FALLBACK" 2>/dev/null
    }

    return 0
}

# Background variant for latency-sensitive hooks.
# Output redirected to avoid stream-inheritance hangs (KNOWLEDGE.md M004).
alba_log_bg() {
    ( alba_log "$@" ) > /dev/null 2>&1 &
}
