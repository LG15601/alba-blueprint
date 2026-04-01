#!/bin/bash
# Alba — Session Stop Hook
# Runs when Claude Code session ends
# Triggers self-improvement protocol

ALBA_DIR="$HOME/.alba"
LOG_DIR="$ALBA_DIR/logs"
SESSIONS_LOG="$LOG_DIR/sessions.jsonl"

mkdir -p "$LOG_DIR"

# Log session end
echo "{\"event\":\"stop\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" >> "$SESSIONS_LOG"

# Get tool call count for this session
TOOL_COUNT=$(cat /tmp/alba-tool-counter 2>/dev/null || echo "0")

# Log session stats
echo "{\"event\":\"stats\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"tool_calls\":$TOOL_COUNT}" >> "$SESSIONS_LOG"

exit 0
