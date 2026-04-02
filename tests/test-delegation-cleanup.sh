#!/bin/bash
# TAP test suite for delegation-cleanup.sh
# Tests child removal, stale purge, and negative/boundary cases.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/delegation-cleanup.sh"

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

write_config() {
    cat > "$TEMP_CONFIG" <<'CONF'
{
  "maxConcurrentChildren": 3,
  "maxDepth": 2,
  "staleTTL": 3600,
  "blockedTools": {}
}
CONF
}

reset_state() {
    echo '{"children":[]}' > "$TEMP_STATE"
}

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
echo "1..12"

TEST_NUM=0
pass() { TEST_NUM=$((TEST_NUM + 1)); echo "ok $TEST_NUM - $1"; }
fail() { TEST_NUM=$((TEST_NUM + 1)); echo "not ok $TEST_NUM - $1"; }

# ============================================================
# Test 1: Successful child removal via session_id
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-A","depth":0,"timestamp":$NOW},
  {"id":"c2","session_id":"sess-B","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"session_id":"sess-A"}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
REMAINING_SID=$(jq -r '.children[0].session_id' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ] && [ "$REMAINING_SID" = "sess-B" ]; then
    pass "Successful child removal via session_id"
else
    fail "Successful child removal (rc=$RC, remaining=$REMAINING, sid=$REMAINING_SID)"
fi

# ============================================================
# Test 2: Removal via tool_output.session_id (PostToolUse format)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-PTU","depth":1,"timestamp":$NOW}
]}
EOF
run_hook '{"tool_name":"Agent","tool_output":{"session_id":"sess-PTU","result":"done"}}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 0 ]; then
    pass "Removal via tool_output.session_id"
else
    fail "Removal via tool_output.session_id (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 3: Removal via subagent.session_id (SubagentStop format)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-SAS","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"subagent":{"session_id":"sess-SAS","status":"stopped"}}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 0 ]; then
    pass "Removal via subagent.session_id"
else
    fail "Removal via subagent.session_id (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 4: Removal of non-existent child (no error)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-keep","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"session_id":"sess-nonexistent"}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ]; then
    pass "Removal of non-existent child (no error, state unchanged)"
else
    fail "Removal of non-existent child (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 5: Stale entry purge during cleanup
# ============================================================
write_config
NOW=$(date +%s)
OLD_TS=$(( NOW - 7200 ))
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"stale1","session_id":"s-old","depth":0,"timestamp":$OLD_TS},
  {"id":"fresh1","session_id":"s-fresh","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"session_id":"s-old"}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ]; then
    pass "Stale entry purged during cleanup"
else
    fail "Stale entry purge (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 6: Remove last child → empty children array
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-last","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"session_id":"sess-last"}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
VALID_JSON=$(jq . "$TEMP_STATE" >/dev/null 2>&1 && echo "yes" || echo "no")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 0 ] && [ "$VALID_JSON" = "yes" ]; then
    pass "Remove last child → empty children array, valid JSON"
else
    fail "Remove last child (rc=$RC, remaining=$REMAINING, valid=$VALID_JSON)"
fi

# ============================================================
# Test 7: Empty stdin → exit 0, no state change
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW}
]}
EOF
echo "" | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LOGS_DB="$TEMP_LOGS_DB" \
    bash "$HOOK" >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ]; then
    pass "Empty stdin → exit 0, no state change"
else
    fail "Empty stdin (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 8: Missing session_id in input → exit 0, no state change
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW}
]}
EOF
run_hook '{"tool_name":"Agent","tool_output":{"result":"done"}}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ]; then
    pass "Missing session_id → exit 0, no state change"
else
    fail "Missing session_id (rc=$RC, remaining=$REMAINING)"
fi

# ============================================================
# Test 9: Missing state file → create empty, exit 0
# ============================================================
write_config
rm -f "$TEMP_STATE"
run_hook '{"session_id":"sess-nofile"}' >/dev/null 2>&1 && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && [ -f "$TEMP_STATE" ]; then
    if jq . "$TEMP_STATE" >/dev/null 2>&1; then
        pass "Missing state file → created empty, exit 0"
    else
        fail "Missing state file → created but invalid JSON"
    fi
else
    fail "Missing state file (rc=$RC, exists=$([ -f "$TEMP_STATE" ] && echo yes || echo no))"
fi

# ============================================================
# Test 10: Corrupt state JSON → reset to empty, exit 0
# ============================================================
write_config
echo "NOT VALID JSON{{{" > "$TEMP_STATE"
run_hook '{"session_id":"sess-corrupt"}' >/dev/null 2>&1 && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && jq . "$TEMP_STATE" >/dev/null 2>&1; then
    pass "Corrupt state JSON → reset to empty, exit 0"
else
    fail "Corrupt state JSON (rc=$RC)"
fi

# ============================================================
# Test 11: Cleanup logs removal to delegation.log
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"sess-logged","depth":0,"timestamp":$NOW}
]}
EOF
rm -f "$TEMP_LOG" "$TEMP_LOGS_DB"
sqlite3 "$TEMP_LOGS_DB" "CREATE TABLE IF NOT EXISTS logs (id INTEGER PRIMARY KEY, timestamp TEXT, level TEXT, source TEXT, message TEXT, metadata TEXT);" 2>/dev/null
run_hook '{"session_id":"sess-logged"}' >/dev/null 2>&1 && RC=$? || RC=$?
if [ "$RC" -eq 0 ] && sqlite3 "$TEMP_LOGS_DB" "SELECT COUNT(*) FROM logs WHERE source='delegation-cleanup' AND message LIKE '%Removed%';" 2>/dev/null | grep -qE '^[1-9]'; then
    pass "Cleanup removal logged to alba-logs.db"
else
    fail "Cleanup logging (rc=$RC, log_exists=$([ -f "$TEMP_LOGS_DB" ] && echo yes || echo no))"
fi

# ============================================================
# Test 12: Malformed JSON input → exit 0
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"c1","session_id":"s1","depth":0,"timestamp":$NOW}
]}
EOF
run_hook 'not json at all {{{}}}' >/dev/null 2>&1 && RC=$? || RC=$?
REMAINING=$(jq '.children | length' "$TEMP_STATE")
if [ "$RC" -eq 0 ] && [ "$REMAINING" -eq 1 ]; then
    pass "Malformed JSON input → exit 0, no state change"
else
    fail "Malformed JSON input (rc=$RC, remaining=$REMAINING)"
fi

echo "# Done"
