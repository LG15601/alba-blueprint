#!/bin/bash
# TAP test suite for handoff-handler.sh
# Tests handoff generation, retry loop, escalation, and fail-open behavior.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/handoff-handler.sh"

# --- Setup temp environment ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE" /tmp/alba-delegation.lock' EXIT

TEMP_CONFIG="$TMPDIR_BASE/config/delegation-limits.json"
TEMP_STATE="$TMPDIR_BASE/state/delegation-state.json"
TEMP_LOG="$TMPDIR_BASE/logs/delegation.log"
TEMP_HANDOFFS="$TMPDIR_BASE/handoffs"
TEMP_TEMPLATES="$TMPDIR_BASE/templates"

mkdir -p "$(dirname "$TEMP_CONFIG")" "$(dirname "$TEMP_STATE")" "$(dirname "$TEMP_LOG")" "$TEMP_HANDOFFS" "$TEMP_TEMPLATES"

# Copy real templates
cp "$SCRIPT_DIR/../config/handoff-templates/"*.json "$TEMP_TEMPLATES/"

# Default test config
write_config() {
    cat > "$TEMP_CONFIG" <<'CONF'
{
  "maxConcurrentChildren": 3,
  "maxDepth": 2,
  "staleTTL": 3600,
  "blockedTools": {},
  "allowedAgentTypes": ["scout", "worker", "planner", "reviewer"],
  "handoff": {
    "maxRetries": 3,
    "escalationPolicy": "auto",
    "handoffDir": "~/.alba/handoffs"
  }
}
CONF
}

reset_state() {
    echo '{"children":[]}' > "$TEMP_STATE"
}

reset_handoffs() {
    rm -rf "$TEMP_HANDOFFS"/*
}

# Helper: run hook with given JSON input
run_hook() {
    local input="$1"
    local exit_code=0
    local output
    output=$(echo "$input" | \
        DELEGATION_CONFIG="$TEMP_CONFIG" \
        DELEGATION_STATE="$TEMP_STATE" \
        DELEGATION_LOG="$TEMP_LOG" \
        HANDOFF_DIR="$TEMP_HANDOFFS" \
        TEMPLATE_DIR="$TEMP_TEMPLATES" \
        bash "$HOOK" 2>/dev/null) || exit_code=$?
    echo "$output"
    return "$exit_code"
}

# TAP header
echo "1..21"

TEST_NUM=0
pass() { TEST_NUM=$((TEST_NUM + 1)); echo "ok $TEST_NUM - $1"; }
fail() { TEST_NUM=$((TEST_NUM + 1)); echo "not ok $TEST_NUM - $1"; }

# ============================================================
# Test 1: Template files exist and are valid JSON
# ============================================================
TEMPLATES_VALID=true
for t in standard qa-pass qa-fail escalation completion; do
    if ! jq . "$TEMP_TEMPLATES/$t.json" >/dev/null 2>&1; then
        TEMPLATES_VALID=false
    fi
done
if $TEMPLATES_VALID; then
    pass "Template files exist and are valid JSON"
else
    fail "Template files exist and are valid JSON"
fi

# ============================================================
# Test 2: QA pass result generates qa-pass handoff
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-qa","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-qa","tool_output":{"verdict":"pass","task_id":"T01","evidence":["test-log.txt"]}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*qa-pass*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.type == "qa-pass"' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "QA pass generates qa-pass handoff"
else
    fail "QA pass generates qa-pass handoff (file=$HANDOFF_FILE)"
fi

# ============================================================
# Test 3: QA fail result generates qa-fail handoff with retry_count=1
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-qf1","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"Agent","session_id":"sess-qf1","tool_output":{"verdict":"fail","task_id":"T02","issue_list":[{"severity":"major","expected":"green","actual":"red","description":"Color wrong"}]}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*qa-fail*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.type == "qa-fail" and .retry_count == 1' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "QA fail generates qa-fail handoff with retry_count=1"
else
    RC_VAL=$(jq '.retry_count' "$HANDOFF_FILE" 2>/dev/null)
    fail "QA fail generates qa-fail handoff with retry_count=1 (got retry_count=$RC_VAL)"
fi

# ============================================================
# Test 4: Second QA fail increments retry_count to 2
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-qf2","depth":1,"timestamp":$NOW,"handoff_type":"qa-fail","retry_count":1}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-qf2","tool_output":{"verdict":"fail","task_id":"T02"}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*qa-fail*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.retry_count == 2' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Second QA fail increments retry_count to 2"
else
    RC_VAL=$(jq '.retry_count' "$HANDOFF_FILE" 2>/dev/null)
    fail "Second QA fail increments retry_count to 2 (got $RC_VAL)"
fi

# ============================================================
# Test 5: Third QA fail generates escalation (not qa-fail)
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-esc","depth":1,"timestamp":$NOW,"handoff_type":"qa-fail","retry_count":2}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-esc","tool_output":{"verdict":"fail","task_id":"T03","issue_summary":"Still broken"}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*escalation*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.type == "escalation"' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Third QA fail generates escalation handoff"
else
    FILES=$(ls "$TEMP_HANDOFFS"/ 2>/dev/null)
    fail "Third QA fail generates escalation handoff (files: $FILES)"
fi

# ============================================================
# Test 6: Escalation handoff contains failure_history array
# ============================================================
if [ -n "$HANDOFF_FILE" ] && jq -e '.failure_history | type == "array" and length > 0' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Escalation handoff contains failure_history array"
else
    fail "Escalation handoff contains failure_history array"
fi

# ============================================================
# Test 7: Standard handoff for non-QA results
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-std","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-std","tool_output":{"context":"Some work done","task_id":"T04"}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*standard*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.type == "standard"' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Standard handoff for non-QA results"
else
    FILES=$(ls "$TEMP_HANDOFFS"/ 2>/dev/null)
    fail "Standard handoff for non-QA results (files: $FILES)"
fi

# ============================================================
# Test 8: Malformed stdin — fail-open (exit 0, log error)
# ============================================================
write_config
reset_state
rm -f "$TEMP_LOG"
run_hook 'NOT JSON {{{{' >/dev/null
RC=$?
if [ "$RC" -eq 0 ] && grep -q "Malformed stdin" "$TEMP_LOG" 2>/dev/null; then
    pass "Malformed stdin — fail-open with logged error"
else
    fail "Malformed stdin — fail-open (rc=$RC)"
fi

# ============================================================
# Test 9: Missing config — fail-open with default maxRetries
# ============================================================
rm -f "$TEMP_CONFIG"
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-nc","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-nc","tool_output":{"verdict":"pass","task_id":"T05"}}' >/dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Missing config — fail-open"
else
    fail "Missing config — fail-open (rc=$RC)"
fi

# ============================================================
# Test 10: Missing state file — fail-open
# ============================================================
write_config
rm -f "$TEMP_STATE"
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-ns","tool_output":{"verdict":"pass","task_id":"T06"}}' >/dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Missing state file — fail-open"
else
    fail "Missing state file — fail-open (rc=$RC)"
fi

# ============================================================
# Test 11: Handoff file written with correct timestamp format
# ============================================================
write_config
reset_state
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-ts","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-ts","tool_output":{"verdict":"pass","task_id":"T07"}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ]; then
    # Check filename format: YYYYMMDD-HHMMSS-type.json
    BASENAME=$(basename "$HANDOFF_FILE")
    if echo "$BASENAME" | grep -qE '^[0-9]{8}-[0-9]{6}-[a-z-]+\.json$'; then
        pass "Handoff file has correct timestamp format"
    else
        fail "Handoff file has correct timestamp format (got $BASENAME)"
    fi
else
    fail "Handoff file has correct timestamp format (no file)"
fi

# ============================================================
# Test 12: retry_count persisted in delegation-state.json
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-persist","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-persist","tool_output":{"verdict":"fail","task_id":"T08"}}' >/dev/null
PERSISTED_RC=$(jq '[.children[] | select(.session_id == "sess-persist")] | first | .retry_count' "$TEMP_STATE" 2>/dev/null)
if [ "$PERSISTED_RC" = "1" ]; then
    pass "retry_count persisted in delegation-state.json"
else
    fail "retry_count persisted in delegation-state.json (got $PERSISTED_RC)"
fi

# ============================================================
# Test 13: Empty stdin — exit 0 silently
# ============================================================
write_config
reset_state
OUTPUT=$(echo "" | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    HANDOFF_DIR="$TEMP_HANDOFFS" \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Empty stdin — exit 0 silently"
else
    fail "Empty stdin — exit 0 (rc=$RC)"
fi

# ============================================================
# Test 14: Missing session_id — fail-open with log
# ============================================================
write_config
reset_state
rm -f "$TEMP_LOG"
reset_handoffs
run_hook '{"tool_name":"subagent","tool_output":{"verdict":"pass"}}' >/dev/null
RC=$?
if [ "$RC" -eq 0 ] && grep -q "No session_id" "$TEMP_LOG" 2>/dev/null; then
    pass "Missing session_id — fail-open with log"
else
    fail "Missing session_id — fail-open (rc=$RC)"
fi

# ============================================================
# Test 15: Non-subagent tool calls ignored (exit 0, no file)
# ============================================================
write_config
reset_state
reset_handoffs
run_hook '{"tool_name":"Bash","tool_input":{"command":"ls"},"session_id":"sess-bash"}' >/dev/null
RC=$?
FILE_COUNT=$(find "$TEMP_HANDOFFS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$RC" -eq 0 ] && [ "$FILE_COUNT" -eq 0 ]; then
    pass "Non-subagent tool calls ignored"
else
    fail "Non-subagent tool calls ignored (rc=$RC, files=$FILE_COUNT)"
fi

# ============================================================
# Test 16: Corrupt state file — fail-open (resets)
# ============================================================
write_config
echo "INVALID JSON {{{" > "$TEMP_STATE"
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-corrupt","tool_output":{"verdict":"pass","task_id":"T09"}}' >/dev/null
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Corrupt state file — fail-open"
else
    fail "Corrupt state file — fail-open (rc=$RC)"
fi

# ============================================================
# Test 17: Successful completion generates completion handoff
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c1","session_id":"sess-comp","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-comp","tool_output":{"summary":"Built login page","task_id":"T10","artifacts_produced":["src/login.tsx","src/login.test.tsx"],"learnings":["React portals avoid z-index issues"],"next_steps":["Add forgot-password flow"]}}' >/dev/null
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*completion*.json 2>/dev/null | head -1)
if [ -n "$HANDOFF_FILE" ] && jq -e '.type == "completion"' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Successful completion generates completion handoff"
else
    FILES=$(ls "$TEMP_HANDOFFS"/ 2>/dev/null)
    fail "Successful completion generates completion handoff (files: $FILES)"
fi

# ============================================================
# Test 18: Completion handoff contains summary and artifacts_produced
# ============================================================
if [ -n "$HANDOFF_FILE" ] && \
   jq -e '.summary == "Built login page"' "$HANDOFF_FILE" >/dev/null 2>&1 && \
   jq -e '.artifacts_produced | length == 2' "$HANDOFF_FILE" >/dev/null 2>&1; then
    pass "Completion handoff contains summary and artifacts_produced"
else
    fail "Completion handoff contains summary and artifacts_produced"
fi

# ============================================================
# Test 19: Learnings appended to learnings.jsonl
# ============================================================
TEMP_LEARNINGS="$TMPDIR_BASE/logs/learnings.jsonl"
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c2","session_id":"sess-learn","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
rm -f "$TEMP_LEARNINGS"
echo '{"tool_name":"subagent","session_id":"sess-learn","tool_output":{"summary":"Optimized queries","task_id":"T11","artifacts_produced":["db/migrations/001.sql"],"learnings":["Use covering indexes","Batch inserts > 100 rows"]}}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    HANDOFF_DIR="$TEMP_HANDOFFS" \
    TEMPLATE_DIR="$TEMP_TEMPLATES" \
    LEARNINGS_LOG="$TEMP_LEARNINGS" \
    bash "$HOOK" 2>/dev/null
LINE_COUNT=$(wc -l < "$TEMP_LEARNINGS" 2>/dev/null | tr -d ' ')
FIRST_LEARNING=$(head -1 "$TEMP_LEARNINGS" 2>/dev/null | jq -r '.learning' 2>/dev/null)
if [ "$LINE_COUNT" = "2" ] && [ "$FIRST_LEARNING" = "Use covering indexes" ]; then
    pass "Learnings appended to learnings.jsonl (2 lines, correct content)"
else
    fail "Learnings appended to learnings.jsonl (lines=$LINE_COUNT, first=$FIRST_LEARNING)"
fi

# ============================================================
# Test 20: Completion with no learnings — no crash, no learnings written
# ============================================================
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"c3","session_id":"sess-nolrn","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
rm -f "$TEMP_LEARNINGS"
echo '{"tool_name":"subagent","session_id":"sess-nolrn","tool_output":{"summary":"Simple fix","task_id":"T12","artifacts_produced":["fix.sh"]}}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    HANDOFF_DIR="$TEMP_HANDOFFS" \
    TEMPLATE_DIR="$TEMP_TEMPLATES" \
    LEARNINGS_LOG="$TEMP_LEARNINGS" \
    bash "$HOOK" 2>/dev/null
RC=$?
HANDOFF_FILE=$(ls "$TEMP_HANDOFFS"/*completion*.json 2>/dev/null | head -1)
if [ "$RC" -eq 0 ] && [ -n "$HANDOFF_FILE" ] && [ ! -f "$TEMP_LEARNINGS" ]; then
    pass "Completion with no learnings — no crash, no learnings file"
else
    fail "Completion with no learnings (rc=$RC, learnings_exists=$([ -f "$TEMP_LEARNINGS" ] && echo yes || echo no))"
fi

# ============================================================
# Test 21: Integration — full dev-QA cycle: spawn → fail → retry → fail → retry → fail → escalation
# ============================================================
write_config
NOW=$(date +%s)
# Simulate a fresh child entry
cat > "$TEMP_STATE" <<EOF
{"children":[{"id":"dev1","session_id":"sess-cycle","depth":1,"timestamp":$NOW,"handoff_type":null,"retry_count":0}]}
EOF
reset_handoffs
INTEGRATION_OK=true

# First QA fail → qa-fail, retry_count=1
run_hook '{"tool_name":"subagent","session_id":"sess-cycle","tool_output":{"verdict":"fail","task_id":"T-cycle","issue_list":[{"description":"Test 1 failed"}]}}' >/dev/null
F1=$(ls "$TEMP_HANDOFFS"/*qa-fail*.json 2>/dev/null | head -1)
RC1=$(jq '.retry_count' "$F1" 2>/dev/null)
[ "$RC1" = "1" ] || INTEGRATION_OK=false

# Second QA fail → qa-fail, retry_count=2
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-cycle","tool_output":{"verdict":"fail","task_id":"T-cycle","issue_list":[{"description":"Test 1 still failed"}]}}' >/dev/null
F2=$(ls "$TEMP_HANDOFFS"/*qa-fail*.json 2>/dev/null | head -1)
RC2=$(jq '.retry_count' "$F2" 2>/dev/null)
[ "$RC2" = "2" ] || INTEGRATION_OK=false

# Third QA fail → escalation, retry_count=3
reset_handoffs
run_hook '{"tool_name":"subagent","session_id":"sess-cycle","tool_output":{"verdict":"fail","task_id":"T-cycle","issue_summary":"Persistent failure"}}' >/dev/null
F3=$(ls "$TEMP_HANDOFFS"/*escalation*.json 2>/dev/null | head -1)
if [ -z "$F3" ]; then
    INTEGRATION_OK=false
else
    ESC_TYPE=$(jq -r '.type' "$F3" 2>/dev/null)
    ESC_RC=$(jq '.retry_count' "$F3" 2>/dev/null)
    [ "$ESC_TYPE" = "escalation" ] && [ "$ESC_RC" = "3" ] || INTEGRATION_OK=false
fi

if $INTEGRATION_OK; then
    pass "Integration: full dev-QA cycle — fail×3 → escalation with correct retry progression"
else
    fail "Integration: full dev-QA cycle (rc1=$RC1 rc2=$RC2 esc_type=${ESC_TYPE:-?} esc_rc=${ESC_RC:-?})"
fi

echo "# Done"
