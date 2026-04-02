#!/usr/bin/env bash
# pre-compact.sh — PreCompact hook: logs compaction event to alba-logs.db
#
# Reads tool call count from /tmp/alba-tool-counter and logs a compaction event.
# Fail-open: always exits 0, never blocks compaction.
# Must not write to stdout except hook JSON output (subshell capture safety).

set -u

# Source logging library
_HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SCRIPTS_DIR="$(dirname "$_HOOK_DIR")/scripts"
# Support both repo-relative and installed paths
if [ -f "$_SCRIPTS_DIR/alba-log.sh" ]; then
    source "$_SCRIPTS_DIR/alba-log.sh"
elif [ -f "$HOME/.alba/scripts/alba-log.sh" ]; then
    source "$HOME/.alba/scripts/alba-log.sh"
else
    # Fail-open: can't log, just exit
    exit 0
fi

# Read tool counter (read-only)
COUNTER_FILE="${COUNTER_FILE:-/tmp/alba-tool-counter}"
count=0
if [ -f "$COUNTER_FILE" ]; then
    count=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    count=$((count + 0)) 2>/dev/null || count=0
fi

# Log compaction event
alba_log INFO pre-compact "compaction triggered tool_calls=$count"

exit 0
