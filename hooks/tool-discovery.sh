#!/bin/bash
# Alba — Tool Discovery Hook (PostToolUse: Bash)
# Detects new tool installations and flags for registry update

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Check if this is an installation command
if echo "$COMMAND" | grep -qE "(brew install|npm install -g|pip install|claude mcp add|npx skills add)"; then
    cat <<'EOF'
{"hookSpecificOutput":{"additionalContext":"[TOOL DISCOVERY] A new tool was just installed. Remember to update ~/.alba/tool-registry.json with the new tool's name, version, path, and purpose."}}
EOF
fi

exit 0
