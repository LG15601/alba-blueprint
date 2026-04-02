#!/bin/bash
# TAP test suite for lane detection and per-lane limit enforcement.
# Validates all lane-specific behavior added in S02/T01.
# Follows patterns from test-delegation-gate.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/delegation-gate.sh"

# --- Setup temp environment ---
TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE" /tmp/alba-delegation.lock' EXIT

TEMP_CONFIG="$TMPDIR_BASE/config/delegation-limits.json"
TEMP_STATE="$TMPDIR_BASE/state/delegation-state.json"
TEMP_LOG="$TMPDIR_BASE/logs/delegation.log"

mkdir -p "$(dirname "$TEMP_CONFIG")" "$(dirname "$TEMP_STATE")" "$(dirname "$TEMP_LOG")"

# Config with lanes enabled
write_config() {
    cat > "$TEMP_CONFIG" <<'CONF'
{
  "maxConcurrentChildren": 5,
  "maxDepth": 4,
  "staleTTL": 3600,
  "blockedTools": {},
  "allowedAgentTypes": ["scout", "worker", "planner", "reviewer"],
  "lanes": {
    "main":     { "maxConcurrent": 3 },
    "cron":     { "maxConcurrent": 2 },
    "subagent": { "maxConcurrent": 2 },
    "nested":   { "maxConcurrent": 1 }
  }
}
CONF
}

# Config without lanes key (backward compat)
write_config_no_lanes() {
    cat > "$TEMP_CONFIG" <<'CONF'
{
  "maxConcurrentChildren": 5,
  "maxDepth": 4,
  "staleTTL": 3600,
  "blockedTools": {},
  "allowedAgentTypes": ["scout", "worker", "planner", "reviewer"]
}
CONF
}

reset_state() {
    echo '{"children":[]}' > "$TEMP_STATE"
}

run_hook() {
    local input="$1"
    shift
    local exit_code=0
    local output
    output=$(echo "$input" | \
        DELEGATION_CONFIG="$TEMP_CONFIG" \
        DELEGATION_STATE="$TEMP_STATE" \
        DELEGATION_LOG="$TEMP_LOG" \
        "$@" \
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
# LANE DETECTION TESTS
# ============================================================

# Test 1: No env vars, no parent context → main lane
write_config
reset_state
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t1"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "main" ]; then
        pass "No env vars, no parent → lane=main"
    else
        fail "No env vars, no parent → lane=main (got lane=$LANE)"
    fi
else
    fail "No env vars, no parent → lane=main (rc=$RC)"
fi

# Test 2: ALBA_LANE=cron → cron lane
write_config
reset_state
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t2"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=cron \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "cron" ]; then
        pass "ALBA_LANE=cron → lane=cron"
    else
        fail "ALBA_LANE=cron → lane=cron (got lane=$LANE)"
    fi
else
    fail "ALBA_LANE=cron → lane=cron (rc=$RC)"
fi

# Test 3: ALBA_CRON=1 → cron lane
write_config
reset_state
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t3"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_CRON=1 \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "cron" ]; then
        pass "ALBA_CRON=1 → lane=cron"
    else
        fail "ALBA_CRON=1 → lane=cron (got lane=$LANE)"
    fi
else
    fail "ALBA_CRON=1 → lane=cron (rc=$RC)"
fi

# Test 4: ALBA_LANE=custom → lane=custom (arbitrary override)
write_config
reset_state
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t4"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=custom \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "custom" ]; then
        pass "ALBA_LANE=custom → lane=custom (env override)"
    else
        fail "ALBA_LANE=custom → lane=custom (got lane=$LANE)"
    fi
else
    fail "ALBA_LANE=custom → lane=custom (rc=$RC)"
fi

# Test 5: Spawn from depth-1 parent → subagent lane
# Pre-populate state with a depth-1 entry for the session, so spawner depth=1
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"parent-1","session_id":"sess-t5","depth":1,"timestamp":$NOW,"lane":"main"}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t5"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    # The new child should be the last entry
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "subagent" ]; then
        pass "Depth-1 spawner → lane=subagent"
    else
        fail "Depth-1 spawner → lane=subagent (got lane=$LANE)"
    fi
else
    fail "Depth-1 spawner → lane=subagent (rc=$RC)"
fi

# Test 6: Spawn from depth-2+ parent → nested lane
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"parent-2","session_id":"sess-t6","depth":2,"timestamp":$NOW,"lane":"subagent"}
]}
EOF
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t6"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[-1].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "nested" ]; then
        pass "Depth-2 spawner → lane=nested"
    else
        fail "Depth-2 spawner → lane=nested (got lane=$LANE)"
    fi
else
    fail "Depth-2 spawner → lane=nested (rc=$RC)"
fi

# ============================================================
# PER-LANE LIMIT TESTS
# ============================================================

# Test 7: Fill cron lane to limit (2) → next cron rejected, main allowed
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"cron-1","session_id":"s-c1","depth":1,"timestamp":$NOW,"lane":"cron"},
  {"id":"cron-2","session_id":"s-c2","depth":1,"timestamp":$NOW,"lane":"cron"}
]}
EOF
# Cron spawn should be denied
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t7-cron"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=cron \
    bash "$HOOK" 2>/dev/null) && RC_CRON=$? || RC_CRON=$?
# Main spawn should still be allowed
OUTPUT_MAIN=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t7-main"}') && RC_MAIN=$? || RC_MAIN=$?
if [ "$RC_CRON" -eq 2 ] && [ "$RC_MAIN" -eq 0 ]; then
    pass "Cron lane full → cron rejected, main allowed"
else
    fail "Cron lane full → cron rejected, main allowed (cron_rc=$RC_CRON, main_rc=$RC_MAIN)"
fi

# Test 8: Fill main lane to limit (3) → main rejected, cron allowed
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"main-1","session_id":"s-m1","depth":1,"timestamp":$NOW,"lane":"main"},
  {"id":"main-2","session_id":"s-m2","depth":1,"timestamp":$NOW,"lane":"main"},
  {"id":"main-3","session_id":"s-m3","depth":1,"timestamp":$NOW,"lane":"main"}
]}
EOF
# Main spawn should be denied
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t8-main"}') && RC_MAIN=$? || RC_MAIN=$?
# Cron spawn should be allowed
OUTPUT_CRON=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t8-cron"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=cron \
    bash "$HOOK" 2>/dev/null) && RC_CRON=$? || RC_CRON=$?
if [ "$RC_MAIN" -eq 2 ] && [ "$RC_CRON" -eq 0 ]; then
    pass "Main lane full → main rejected, cron allowed"
else
    fail "Main lane full → main rejected, cron allowed (main_rc=$RC_MAIN, cron_rc=$RC_CRON)"
fi

# Test 9: Global ceiling enforced across lanes
# Each lane individually under limit but total at maxConcurrentChildren (5)
write_config
NOW=$(date +%s)
cat > "$TEMP_STATE" <<EOF
{"children":[
  {"id":"g1","session_id":"s-g1","depth":1,"timestamp":$NOW,"lane":"main"},
  {"id":"g2","session_id":"s-g2","depth":1,"timestamp":$NOW,"lane":"main"},
  {"id":"g3","session_id":"s-g3","depth":1,"timestamp":$NOW,"lane":"cron"},
  {"id":"g4","session_id":"s-g4","depth":1,"timestamp":$NOW,"lane":"subagent"},
  {"id":"g5","session_id":"s-g5","depth":1,"timestamp":$NOW,"lane":"nested"}
]}
EOF
# Any spawn should be rejected — global ceiling hit
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t9"}') && RC=$? || RC=$?
if [ "$RC" -eq 2 ] && echo "$OUTPUT" | grep -q "Concurrent child limit"; then
    pass "Global ceiling blocks all lanes when total at max"
else
    fail "Global ceiling blocks all lanes (rc=$RC, output=$OUTPUT)"
fi

# ============================================================
# BACKWARD COMPATIBILITY
# ============================================================

# Test 10: Config without lanes key → spawn allowed (global limit only)
write_config_no_lanes
reset_state
OUTPUT=$(run_hook '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t10"}') && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "No lanes config → spawn allowed (global limit only)"
else
    fail "No lanes config → spawn allowed (rc=$RC)"
fi

# Test 11: Config with lanes but lane not listed → spawn allowed (no per-lane check)
write_config
reset_state
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t11"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=unlisted \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    pass "Unknown lane (not in config) → spawn allowed"
else
    fail "Unknown lane (not in config) → spawn allowed (rc=$RC)"
fi

# ============================================================
# STATE VERIFICATION
# ============================================================

# Test 12: After allowed spawn, state entry has correct lane field
write_config
reset_state
OUTPUT=$(echo '{"tool_name":"subagent","tool_input":{"agent":"worker","task":"stuff"},"session_id":"sess-t12"}' | \
    DELEGATION_CONFIG="$TEMP_CONFIG" \
    DELEGATION_STATE="$TEMP_STATE" \
    DELEGATION_LOG="$TEMP_LOG" \
    ALBA_LANE=cron \
    bash "$HOOK" 2>/dev/null) && RC=$? || RC=$?
if [ "$RC" -eq 0 ]; then
    LANE=$(jq -r '.children[0].lane' "$TEMP_STATE" 2>/dev/null)
    if [ "$LANE" = "cron" ]; then
        pass "Allowed spawn records correct lane in state"
    else
        fail "Allowed spawn records correct lane (expected cron, got $LANE)"
    fi
else
    fail "Allowed spawn records correct lane (rc=$RC)"
fi

echo "# Done"
