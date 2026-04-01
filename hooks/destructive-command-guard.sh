#!/bin/bash
# Alba — Destructive Command Guard (PreToolUse: Bash)
# BLOCKS critical commands (exit 2), WARNS on risky ones (exit 0 + context).

# Read the command from stdin (hook input)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# CRITICAL — BLOCK these (exit 2 = deny)
BLOCK_PATTERNS=(
    "rm -rf /"
    "rm -rf ~"
    "rm -rf /\*"
    "sudo rm -rf"
    ":(){ :|:& };:"
    "dd if=/dev.*/dev/[sh]d"
    "mkfs\."
    "chmod -R 777 /"
)

for PATTERN in "${BLOCK_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$PATTERN"; then
        cat <<EOF
{"hookSpecificOutput":{"decision":"block","reason":"BLOCKED: Destructive command detected ('$PATTERN'). This command is never allowed in autonomous mode."}}
EOF
        exit 2
    fi
done

# WARNING — Flag these but allow (exit 0 + context)
WARN_PATTERNS=(
    "git push.*--force"
    "git push.*-f "
    "git reset --hard"
    "git checkout -- \."
    "git clean -fd"
    "DROP TABLE"
    "DROP DATABASE"
    "DELETE FROM"
    "truncate "
    "kill -9"
    "pkill -9"
    "docker system prune -a"
    "sudo "
)

for PATTERN in "${WARN_PATTERNS[@]}"; do
    if echo "$COMMAND" | grep -qiE "$PATTERN"; then
        cat <<EOF
{"hookSpecificOutput":{"additionalContext":"WARNING: Risky command detected ('$PATTERN'). Proceeding, but double-check this is intentional. Consider a safer alternative."}}
EOF
        exit 0
    fi
done

exit 0
