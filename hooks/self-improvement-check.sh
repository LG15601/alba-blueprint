#!/bin/bash
# Alba — Self-Improvement Check (PostToolUse)
# Counts tool calls. Every 15, injects a self-assessment reminder.

COUNTER_FILE="/tmp/alba-tool-counter"

# Increment counter
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Every 15 tool calls, nudge self-assessment
if [ $((COUNT % 15)) -eq 0 ] && [ "$COUNT" -gt 0 ]; then
    cat <<EOF
{"hookSpecificOutput":{"additionalContext":"[ALBA SELF-CHECK #${COUNT}] Quick assessment: Am I on track? Am I being efficient? Should I delegate? Is my approach still correct? If stuck, try a different approach."}}
EOF
fi

exit 0
