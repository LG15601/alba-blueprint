#!/bin/bash
# Alba — Delegation Gate (PreToolUse: subagent)
# Enforces hard limits on subagent spawns:
#   1. Max concurrent children
#   2. Max delegation depth
#   3. Blocked tools per agent type
# Fail-open on errors — never block work due to gate malfunction.
# Exit 2 + deny JSON = block. Exit 0 = allow.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DELEGATION_CONFIG:-$(cd "$SCRIPT_DIR/.." && pwd)/config/delegation-limits.json}"
STATE_FILE="${DELEGATION_STATE:-$HOME/.alba/delegation-state.json}"
LOG_FILE="${DELEGATION_LOG:-$HOME/logs/delegation.log}"
LOCK_DIR="/tmp/alba-delegation.lock"
LOCK_STALE_SECONDS=60

# --- Logging ---
log_denial() {
    local reason="$1"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] DENIED: $reason" >> "$LOG_FILE"
}

# --- Lock management (mkdir-based, from M004 pattern) ---
acquire_lock() {
    local retries=5
    local wait=1
    while [ "$retries" -gt 0 ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_DIR/pid"
            return 0
        fi
        # Stale detection: if lock dir older than LOCK_STALE_SECONDS, remove it
        if [ -d "$LOCK_DIR" ]; then
            local lock_age
            if [ "$(uname)" = "Darwin" ]; then
                lock_age=$(( $(date +%s) - $(stat -f '%m' "$LOCK_DIR" 2>/dev/null || echo 0) ))
            else
                lock_age=$(( $(date +%s) - $(stat -c '%Y' "$LOCK_DIR" 2>/dev/null || echo 0) ))
            fi
            if [ "$lock_age" -gt "$LOCK_STALE_SECONDS" ]; then
                rm -rf "$LOCK_DIR"
                continue
            fi
        fi
        retries=$((retries - 1))
        sleep "$wait"
    done
    # Failed to acquire after retries — fail-open
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

# --- Output helpers ---
deny() {
    local reason="$1"
    log_denial "$reason"
    cat <<EOF
{"hookSpecificOutput":{"decision":"block","reason":"$reason"}}
EOF
    release_lock 2>/dev/null || true
    exit 2
}

allow() {
    cat <<EOF
{"hookSpecificOutput":{"decision":"allow"}}
EOF
    exit 0
}

# --- Read stdin ---
INPUT=$(cat)

# Validate we got something
if [ -z "$INPUT" ]; then
    allow
fi

# Extract fields — fail-open on jq errors
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || { allow; }
if [ -z "$TOOL_NAME" ]; then
    allow
fi

# Only gate subagent/Agent tool calls
case "$TOOL_NAME" in
    subagent|Agent) ;;
    *) allow ;;
esac

TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null) || ""
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || "unknown"

# --- Load config ---
# Defaults if config missing or malformed
DEFAULT_MAX_CHILDREN=3
DEFAULT_MAX_DEPTH=2
DEFAULT_STALE_TTL=3600

if [ -f "$CONFIG_FILE" ] && jq . "$CONFIG_FILE" >/dev/null 2>&1; then
    MAX_CHILDREN=$(jq -r '.maxConcurrentChildren // 3' "$CONFIG_FILE")
    MAX_DEPTH=$(jq -r '.maxDepth // 2' "$CONFIG_FILE")
    STALE_TTL=$(jq -r '.staleTTL // 3600' "$CONFIG_FILE")
    BLOCKED_TOOLS_JSON=$(jq -r '.blockedTools // {}' "$CONFIG_FILE")
else
    MAX_CHILDREN=$DEFAULT_MAX_CHILDREN
    MAX_DEPTH=$DEFAULT_MAX_DEPTH
    STALE_TTL=$DEFAULT_STALE_TTL
    BLOCKED_TOOLS_JSON="{}"
fi

# --- Acquire lock ---
if ! acquire_lock; then
    # Can't get lock — fail-open
    allow
fi

# Ensure lock released on exit
trap 'release_lock 2>/dev/null || true' EXIT

# --- Load state ---
mkdir -p "$(dirname "$STATE_FILE")"
if [ ! -f "$STATE_FILE" ] || ! jq . "$STATE_FILE" >/dev/null 2>&1; then
    echo '{"children":[]}' > "$STATE_FILE"
fi

STATE=$(cat "$STATE_FILE")

# --- Purge stale entries ---
NOW=$(date +%s)
STATE=$(echo "$STATE" | jq --argjson now "$NOW" --argjson ttl "$STALE_TTL" '
    .children = [.children[] | select((.timestamp // 0) > ($now - $ttl))]
')

# --- Check 1: Concurrent children ---
CURRENT_COUNT=$(echo "$STATE" | jq '.children | length')
if [ "$CURRENT_COUNT" -ge "$MAX_CHILDREN" ]; then
    # Write purged state before denying
    echo "$STATE" | jq . > "$STATE_FILE"
    deny "Concurrent child limit reached: $CURRENT_COUNT/$MAX_CHILDREN active children. Wait for existing subagents to complete before spawning new ones."
fi

# --- Check 2: Depth ---
# Find current session's depth in the parent chain
CURRENT_DEPTH=$(echo "$STATE" | jq --arg sid "$SESSION_ID" '
    [.children[] | select(.session_id == $sid)] | first // null |
    if . == null then 0 else (.depth // 0) end
')
CHILD_DEPTH=$((CURRENT_DEPTH + 1))

if [ "$CHILD_DEPTH" -gt "$MAX_DEPTH" ]; then
    echo "$STATE" | jq . > "$STATE_FILE"
    deny "Max delegation depth exceeded: depth $CHILD_DEPTH would exceed limit of $MAX_DEPTH. Reduce nesting — a subagent should not spawn further subagents at this depth."
fi

# --- Check 3: Blocked tools per agent type ---
# Extract agent type from tool_input (the 'agent' field in subagent calls)
AGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.agent // empty' 2>/dev/null) || ""

if [ -n "$AGENT_TYPE" ] && [ "$BLOCKED_TOOLS_JSON" != "{}" ]; then
    # Get blocked tools for this agent type
    BLOCKED_LIST=$(echo "$BLOCKED_TOOLS_JSON" | jq -r --arg at "$AGENT_TYPE" '.[$at] // [] | .[]' 2>/dev/null)

    if [ -n "$BLOCKED_LIST" ]; then
        # Check if any requested allowed_tools match blocked patterns
        REQUESTED_TOOLS=$(echo "$INPUT" | jq -r '.tool_input.allowed_tools // [] | .[]' 2>/dev/null) || ""

        while IFS= read -r blocked; do
            [ -z "$blocked" ] && continue
            # Convert glob pattern to regex for matching
            blocked_regex=$(echo "$blocked" | sed 's/\*/.*/' | sed 's/(/\\(/g' | sed 's/)/\\)/g')
            while IFS= read -r requested; do
                [ -z "$requested" ] && continue
                if echo "$requested" | grep -qE "^${blocked_regex}$"; then
                    echo "$STATE" | jq . > "$STATE_FILE"
                    deny "Blocked tool for agent type '$AGENT_TYPE': tool '$requested' matches blocked pattern '$blocked'."
                fi
            done <<< "$REQUESTED_TOOLS"
        done <<< "$BLOCKED_LIST"
    fi
fi

# --- All checks passed — register child and allow ---
CHILD_ID="child-${SESSION_ID}-$(date +%s)-$$"
STATE=$(echo "$STATE" | jq --arg cid "$CHILD_ID" --arg sid "$SESSION_ID" --argjson depth "$CHILD_DEPTH" --argjson ts "$NOW" '
    .children += [{"id": $cid, "session_id": $sid, "depth": $depth, "timestamp": $ts}]
')
echo "$STATE" | jq . > "$STATE_FILE"

release_lock
trap - EXIT

allow
