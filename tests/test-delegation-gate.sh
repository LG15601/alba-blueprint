#!/bin/bash
# TAP test suite for delegation-gate.sh
# Tests all limit enforcement scenarios.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/delegation-gate.sh"

# --- Setup temp environment ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE" /tmp/alba-delegation.lock' EXIT

TEMP_CONFIG="$TMPDIR_BASE/config/delegation-limits.json"
TEMP_STATE="$TMPDIR_BASE/state/delegation-state.json"
TEMP_LOG="$TMPDIR_BASE/logs/delegation.log"
TEMP_LOGS_DB="$TMPDIR_BASE/alba-logs-test.db"

mkdir -p "$(dirname "$TEMP_CONFIG")" "$(dirname "$TEMP_STATE")" "$(dirname "$TEMP_LOG")"

# Init logs table in test DB
sqlite3 "$TEMP_LOGS_DB" "CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, timestamp TEXT, level TEXT, source TEXT, message TEXT, metadata TEXT);" 2>/dev/null

# Default test config
write_config() {
    cat > "$TEMP_CONFIG" <<'CONF'
{
  "maxConcurrentChildren": 3,
  "maxDepth": 2,
  "staleTTL": 3600,
  "blockedTools": {
    "planner": ["Bash(*)", "Edit(*)", "Write(*)"],
    "worker": ["Bash(rm *)", "Bash(sudo *)"]
  },
  "allowedAgentTypes": ["scout", "worker", "planner", "reviewer"]
}
CONF
}

reset_state() {
    echo '{"children":[]}' > "$TEMP_STATE"
}

# Helper: run hook with given JSON input, capture output and exit code
run_hook() {
    local input="$1"
    local exit_code=0
    local output
    output=$(echo "$input" | \
        DELEGATION_CONFIG="$TEMP_CONFIG" \
        DELEGATION_STATE="$TEMP_STATE" \
        DELEGATION_LOG="$TEMP_LOG" \
        ALBA_LOGS_DB="$TEMP_LOGS_DB" \
        bash "$HOOK" 2>/dev/null) || exit_code=$?
    echo "$output"
    return "$exit_code"
}

# TAP header
echo "1..14"

TEST_NUM=0
pass() { TEST_NUM=$((TEST_NUM + 1)); echo "ok $TEST_NUM - $1"; }
fail() { TEST_NUM=$((TEST_NUM + 1)); echo "not ok $TEST_NUM - $1"; }

# ============================================================
# Test 1: Allow spawn under limit
# ============================================================
write_config
reset_state
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-1"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && echo "$OUTPUT" | jq -e '.hookSpecificOutput.decision == "allow"' >/dev/null 2>&1; then
    pass "Allow spawn under limit"
else
    fail "Allow spawn under limit (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 2: Allow exactly 3 children (at limit)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW},
  {"id":"c2","session_id":"s2","depth":0,"timestamp":$NOW}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-3"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Allow 3rd child (at limit)"
else
    fail "Allow 3rd child (at limit) (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 3: Reject 4th concurrent child
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW},
  {"id":"c2","session_id":"s2","depth":0,"timestamp":$NOW},
  {"id":"c3","session_id":"s3","depth":0,"timestamp":$NOW}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-4"}') && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "Concurrent child limit"; then
    pass "Reject 4th concurrent child"
else
    fail "Reject 4th concurrent child (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 4: Allow at depth 2 (max)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-deep","depth":1,"timestamp":$NOW}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-deep"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Allow at depth 2 (within limit)"
else
    fail "Allow at depth 2 (within limit) (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 5: Reject at depth 3 (exceeds maxDepth=2)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-tooDeep","depth":2,"timestamp":$NOW}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-tooDeep"}') && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "depth"; then
    pass "Reject at depth 3 (exceeds maxDepth)"
else
    fail "Reject at depth 3 (exceeds maxDepth) (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 6: Reject blocked tools for agent type
# ============================================================
write_config
reset_state
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"planner","task":"plan stuff","allowed_tools":["Bash(ls)","Edit(foo)"]},"session_id":"sess-bt"}') && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "Blocked tool"; then
    pass "Reject blocked tools for planner"
else
    fail "Reject blocked tools for planner (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# Test 7: Stale entry cleanup
# ============================================================
write_config
OLD_TS=$(( $(date +%s) - 7200 ))  # 2 hours ago, beyond 3600 staleTTL
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"stale1","session_id":"s-old","depth":0,"timestamp":$OLD_TS},
  {"id":"stale2","session_id":"s-old2","depth":0,"timestamp":$OLD_TS},
  {"id":"stale3","session_id":"s-old3","depth":0,"timestamp":$OLD_TS}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"do stuff"},"session_id":"sess-fresh"}') && RC=$? || RC=$?
# Should allow because stale entries are purged, count goes to 0
if [ "$RC" -eq 0 ]; then
    # Verify state was cleaned
    REMAINING=$(jq '.children | length' "$TEMP_STATE")
    if [ "$REMAINING" -eq 1 ]; then
        pass "Stale entry cleanup (purged 3 stale, added 1 fresh)"
    else
        fail "Stale entry cleanup (expected 1 child, got $REMAINING)"
    fi
else
    fail "Stale entry cleanup (rc=$RC, should have allowed after purge)"
fi

# ============================================================
# Test 8: Denial logged to delegation.log
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW},
  {"id":"c2","session_id":"s2","depth":0,"timestamp":$NOW},
  {"id":"c3","session_id":"s3","depth":0,"timestamp":$NOW}
]}
EOF
rm -f "$TEMP_LOG"
sqlite3 "$TEMP_LOGS_DB" "DELETE FROM logs;" 2>/dev/null
run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker"},"session_id":"sess-log"}' >/dev/null 2>&1 || true
if sqlite3 "$TEMP_LOGS_DB" "SELECT COUNT(*) FROM logs WHERE message LIKE '%DENIED%';" 2>/dev/null | grep -qE '^[1-9]'; then
    pass "Denial logged to alba-logs.db"
else
    fail "Denial logged to delegation.log (log missing or no DENIED entry)"
fi

# ============================================================
# Test 9: Error message contains limit name and counts
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW},
  {"id":"c2","session_id":"s2","depth":0,"timestamp":$NOW},
  {"id":"c3","session_id":"s3","depth":0,"timestamp":$NOW}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker"},"session_id":"sess-msg"}' 2>/dev/null) || true
if echo "$OUTPUT" | grep -q "3/3"; then
    pass "Error message contains counts (3/3)"
else
    fail "Error message contains counts (output=$OUTPUT)"
fi

# ============================================================
# Test 10: Fail-open on empty stdin
# ============================================================
write_config
reset_state
OUTPUT=$(echo "" | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LOGS_DB="$TEMP_LOGS_DB" \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Fail-open on empty stdin"
else
    fail "Fail-open on empty stdin (rc=$RC)"
fi

# ============================================================
# Test 11: Fail-open on missing tool_name
# ============================================================
write_config
reset_state
OUTPUT=$(run_hook '{"tool_input":{"agent":"worker"},"session_id":"s1"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Fail-open on missing tool_name"
else
    fail "Fail-open on missing tool_name (rc=$RC)"
fi

# ============================================================
# Test 12: Fail-open on missing config (uses defaults)
# ============================================================
rm -f "$TEMP_CONFIG"
reset_state
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-nc"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Fail-open on missing config (uses defaults)"
else
    fail "Fail-open on missing config (rc=$RC)"
fi

# ============================================================
# Test 13: Fail-open on corrupt state JSON (resets to empty)
# ============================================================
write_config
echo "NOT VALID JSON{{{" > "$TEMP_STATE"
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-cs"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    # Verify state was reset
    if jq . "$TEMP_STATE" >/dev/null 2>&1; then
        pass "Fail-open on corrupt state (resets to empty)"
    else
        fail "Fail-open on corrupt state (state still corrupt)"
    fi
else
    fail "Fail-open on corrupt state (rc=$RC)"
fi

# ============================================================
# Test 14: Non-subagent tool calls pass through
# ============================================================
write_config
reset_state
OUTPUT=$(run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess-bash"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Non-subagent tool calls pass through"
else
    fail "Non-subagent tool calls pass through (rc=$RC)"
fi

echo "# Done"
