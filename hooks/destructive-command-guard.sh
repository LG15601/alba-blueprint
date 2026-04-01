#!/bin/bash
# Alba — Destructive Command Guard (PreToolUse: Bash)
# Warns before dangerous commands. Advisory only — never blocks.

# Read the command from stdin (hook input)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# Patterns that warrant a warning
DANGEROUS_PATTERNS=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf \*"
    "sudo rm"
    "git push.*--force"
    "git push.*-f "
    "git reset --hard"
    "git checkout -- \."
    "git clean -fd"
    "DROP TABLE"
    "DROP DATABASE"
    "DELETE FROM.*WHERE 1"
    "truncate "
    "kill -9"
    "pkill -9"
    ":(){ :|:& };:"
    "dd if=/dev"
    "mkfs\."
    "chmod -R 777"
    "docker system prune -a"
)

for PATTERN in "${DANGEROUS_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$PATTERN"; then
        cat <<EOF
{"hookSpecificOutput":{"additionalContext":"WARNING: This command matches a destructive pattern ('$PATTERN'). Double-check before proceeding. Consider: is there a safer alternative?"}}
EOF
        exit 0
    fi
done

exit 0
