#!/bin/bash
# Alba — Session Start Hook
# Runs at every Claude Code session start

ALBA_DIR="$HOME/.alba"
LOG_DIR="$ALBA_DIR/logs"
SESSIONS_LOG="$LOG_DIR/sessions.jsonl"

mkdir -p "$LOG_DIR"

# Log session start
echo "{\"event\":\"start\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" >> "$SESSIONS_LOG"

# Load environment
[ -f "$ALBA_DIR/.env" ] && export $(grep -v '^#' "$ALBA_DIR/.env" | xargs)

# Reset tool call counter for self-improvement loop
echo "0" > /tmp/alba-tool-counter 2>/dev/null

# Clean old session logs (keep 7 days)
find "$LOG_DIR" -name "*.jsonl" -mtime +7 -delete 2>/dev/null

exit 0
