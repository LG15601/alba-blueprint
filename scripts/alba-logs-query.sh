#!/usr/bin/env bash
# alba-logs-query.sh — Query structured logs from alba-logs.db
#
# Usage:
#   alba-logs-query.sh last [N]          — show last N entries (default 20)
#   alba-logs-query.sh errors [N]        — show last N ERROR/CRITICAL entries
#   alba-logs-query.sh source <name> [N] — filter by source
#   alba-logs-query.sh tail              — continuous polling (2s interval)

set -uo pipefail

ALBA_LOGS_DB="${ALBA_LOGS_DB:-$HOME/.alba/alba-logs.db}"

if [ ! -f "$ALBA_LOGS_DB" ]; then
    echo "ERROR: Log database not found: $ALBA_LOGS_DB" >&2
    exit 1
fi

format_rows() {
    # Input: pipe-separated timestamp|level|source|message
    while IFS='|' read -r ts level source msg; do
        [ -z "$ts" ] && continue
        echo "$ts $level $source: $msg"
    done
}

cmd="${1:-last}"
shift 2>/dev/null || true

case "$cmd" in
    last)
        limit="${1:-20}"
        /usr/bin/sqlite3 "$ALBA_LOGS_DB" \
            "SELECT timestamp, level, source, message FROM logs ORDER BY id DESC LIMIT $limit;" \
            2>/dev/null | format_rows
        ;;

    errors)
        limit="${1:-20}"
        /usr/bin/sqlite3 "$ALBA_LOGS_DB" \
            "SELECT timestamp, level, source, message FROM logs WHERE level IN ('ERROR','CRITICAL') ORDER BY id DESC LIMIT $limit;" \
            2>/dev/null | format_rows
        ;;

    source)
        name="${1:-}"
        if [ -z "$name" ]; then
            echo "Usage: alba-logs-query.sh source <name> [N]" >&2
            exit 1
        fi
        limit="${2:-20}"
        /usr/bin/sqlite3 "$ALBA_LOGS_DB" \
            "SELECT timestamp, level, source, message FROM logs WHERE source = '$name' ORDER BY id DESC LIMIT $limit;" \
            2>/dev/null | format_rows
        ;;

    tail)
        last_id=$(/usr/bin/sqlite3 "$ALBA_LOGS_DB" "SELECT COALESCE(MAX(id), 0) FROM logs;" 2>/dev/null)
        echo "# Tailing alba-logs.db (Ctrl+C to stop)..."
        while true; do
            /usr/bin/sqlite3 "$ALBA_LOGS_DB" \
                "SELECT timestamp, level, source, message FROM logs WHERE id > $last_id ORDER BY id ASC;" \
                2>/dev/null | format_rows
            new_max=$(/usr/bin/sqlite3 "$ALBA_LOGS_DB" "SELECT COALESCE(MAX(id), 0) FROM logs;" 2>/dev/null)
            [ "$new_max" -gt "$last_id" ] 2>/dev/null && last_id="$new_max"
            sleep 2
        done
        ;;

    *)
        echo "Usage: alba-logs-query.sh {last|errors|source|tail} [args...]" >&2
        exit 1
        ;;
esac
