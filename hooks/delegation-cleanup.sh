#!/bin/bash
# Alba — Delegation Cleanup (PostToolUse + SubagentStop)
# Decrements active children when subagents finish.
# Handles two event types:
#   - PostToolUse: session_id in tool_output or top-level
#   - SubagentStop: session_id identifies the stopping subagent
# Always exits 0 — cleanup should never block.

set -uo pipefail
# Note: no set -e — we must never exit non-zero

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DELEGATION_CONFIG:-$(cd "$SCRIPT_DIR/.." && pwd)/config/delegation-limits.json}"
STATE_FILE="${DELEGATION_STATE:-$HOME/.alba/delegation-state.json}"
LOG_FILE="${DELEGATION_LOG:-$HOME/logs/delegation.log}"
LOCK_DIR="/tmp/alba-delegation.lock"
LOCK_STALE_SECONDS=60

# --- Logging ---
log_cleanup() {
    local msg="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] CLEANUP: $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Lock management (mkdir-based, same as gate hook) ---
acquire_lock() {
    local retries=5
    local wait=1
    while [ "$retries" -gt 0 ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_DIR/pid"
            return 0
        fi
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
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

# --- Read stdin (non-blocking safe) ---
INPUT=""
if read -t 1 -r FIRST_LINE 2>/dev/null; then
    REST=$(cat 2>/dev/null) || true
    INPUT="${FIRST_LINE}${REST}"
fi

# Nothing to do if no input
if [ -z "$INPUT" ]; then
    exit 0
fi

# --- Extract session_id ---
# Try multiple paths: .session_id, .tool_output.session_id, .subagent.session_id
SESSION_ID=""
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.tool_output.session_id // empty' 2>/dev/null) || true
fi
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.subagent.session_id // empty' 2>/dev/null) || true
fi

# No session_id — nothing to clean up
if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# --- Load staleTTL from config ---
DEFAULT_STALE_TTL=3600
if [ -f "$CONFIG_FILE" ] && jq . "$CONFIG_FILE" >/dev/null 2>&1; then
    STALE_TTL=$(jq -r '.staleTTL // 3600' "$CONFIG_FILE" 2>/dev/null) || STALE_TTL=$DEFAULT_STALE_TTL
else
    STALE_TTL=$DEFAULT_STALE_TTL
fi

# --- Acquire lock ---
if ! acquire_lock; then
    log_cleanup "Failed to acquire lock for session $SESSION_ID — skipping cleanup"
    exit 0
fi
trap 'release_lock 2>/dev/null || true' EXIT

# --- Load state ---
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
if [ ! -f "$STATE_FILE" ] || ! jq . "$STATE_FILE" >/dev/null 2>&1; then
    echo '{"children":[]}' > "$STATE_FILE"
    log_cleanup "State file missing or corrupt — reset to empty"
    release_lock
    trap - EXIT
    exit 0
fi

STATE=$(cat "$STATE_FILE")

# --- Count before removal ---
BEFORE_COUNT=$(echo "$STATE" | jq '.children | length' 2>/dev/null) || BEFORE_COUNT=0

# --- Remove matching child entries by session_id ---
STATE=$(echo "$STATE" | jq --arg sid "$SESSION_ID" '
    .children = [.children[] | select(.session_id != $sid)]
')

# --- Purge stale entries ---
NOW=$(date +%s)
STATE=$(echo "$STATE" | jq --argjson now "$NOW" --argjson ttl "$STALE_TTL" '
    .children = [.children[] | select((.timestamp // 0) > ($now - $ttl))]
')

AFTER_COUNT=$(echo "$STATE" | jq '.children | length' 2>/dev/null) || AFTER_COUNT=0

# --- Write updated state ---
echo "$STATE" | jq . > "$STATE_FILE"

REMOVED=$((BEFORE_COUNT - AFTER_COUNT))
if [ "$REMOVED" -gt 0 ]; then
    log_cleanup "Removed $REMOVED entries for session $SESSION_ID ($BEFORE_COUNT → $AFTER_COUNT active)"
fi

release_lock
trap - EXIT
exit 0
