#!/bin/bash
# Alba — Self-Improvement Check (PostToolUse)
# Counts tool calls. Every 15, injects a self-assessment reminder.
# At 75+ and 100+ tool calls, adds context pressure warnings.

COUNTER_FILE="${COUNTER_FILE:-/tmp/alba-tool-counter}"

# Increment counter
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Build additionalContext with self-check and pressure warnings
additionalContext=""

# Every 15 tool calls, nudge self-assessment
if [ $((COUNT % 15)) -eq 0 ] && [ "$COUNT" -gt 0 ]; then
    additionalContext="[ALBA SELF-CHECK #${COUNT}] Quick assessment: Am I on track? Am I being efficient? Should I delegate? Is my approach still correct? If stuck, try a different approach."
fi

# Context pressure warnings (additive — can stack with self-check)
if [ "$COUNT" -ge 100 ]; then
    if [ -n "$additionalContext" ]; then
        additionalContext="${additionalContext} [CONTEXT PRESSURE HIGH] ${COUNT} tool calls. Strongly recommend /compact to free context."
    else
        additionalContext="[CONTEXT PRESSURE HIGH] ${COUNT} tool calls. Strongly recommend /compact to free context."
    fi
elif [ "$COUNT" -ge 75 ]; then
    if [ -n "$additionalContext" ]; then
        additionalContext="${additionalContext} [CONTEXT PRESSURE] Tool calls at ${COUNT}. Context is growing — consider /compact if responses are getting truncated."
    else
        additionalContext="[CONTEXT PRESSURE] Tool calls at ${COUNT}. Context is growing — consider /compact if responses are getting truncated."
    fi
fi

# Emit hook output if we have anything to say
if [ -n "$additionalContext" ]; then
    cat <<EOF
{"hookSpecificOutput":{"additionalContext":"${additionalContext}"}}
EOF
fi

exit 0
