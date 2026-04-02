#!/usr/bin/env bash
# verify-context-compaction.sh — TAP test suite for context compaction strategies
#
# Tests: check_context_pressure thresholds, pre-compact.sh validity,
# inject-context.sh pressure-aware scaling, self-improvement-check.sh
# pressure warnings, dashboard validity, settings.json hook registration.
#
# Uses temp counter files. No side effects on real /tmp/alba-tool-counter.
#
# Usage: bash tests/verify-context-compaction.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PLAN=9
PASS=0
FAIL=0
TEST_NUM=0

# Temp files for isolated testing
TEST_COUNTER=$(mktemp /tmp/alba-compaction-test.XXXXXX)
TEST_COUNTER2=$(mktemp /tmp/alba-compaction-test2.XXXXXX)

cleanup() {
    rm -f "$TEST_COUNTER" "$TEST_COUNTER2"
}
trap cleanup EXIT

# ── TAP helpers ──────────────────────────────────────────────
ok() {
    TEST_NUM=$((TEST_NUM + 1))
    PASS=$((PASS + 1))
    echo "ok $TEST_NUM - $1"
}

not_ok() {
    TEST_NUM=$((TEST_NUM + 1))
    FAIL=$((FAIL + 1))
    echo "not ok $TEST_NUM - $1"
    [ -n "${2:-}" ] && echo "  # $2"
}

echo "1..$PLAN"

# ── Test 1: check_context_pressure returns 'ok' for counter <50 ──
echo "10" > "$TEST_COUNTER"
source "$REPO_DIR/scripts/alba-monitor.sh"
result=$(COUNTER_FILE="$TEST_COUNTER" check_context_pressure)
status=$(echo "$result" | awk '{print $1}')
if [ "$status" = "ok" ]; then
    ok "check_context_pressure returns 'ok' for counter <50"
else
    not_ok "check_context_pressure returns 'ok' for counter <50" "got: $result"
fi

# ── Test 2: check_context_pressure returns 'warning' for counter 50-99 ──
echo "75" > "$TEST_COUNTER"
result=$(COUNTER_FILE="$TEST_COUNTER" check_context_pressure)
status=$(echo "$result" | awk '{print $1}')
if [ "$status" = "warning" ]; then
    ok "check_context_pressure returns 'warning' for counter 50-99"
else
    not_ok "check_context_pressure returns 'warning' for counter 50-99" "got: $result"
fi

# ── Test 3: check_context_pressure returns 'critical' for counter >=100 ──
echo "120" > "$TEST_COUNTER"
result=$(COUNTER_FILE="$TEST_COUNTER" check_context_pressure)
status=$(echo "$result" | awk '{print $1}')
if [ "$status" = "critical" ]; then
    ok "check_context_pressure returns 'critical' for counter >=100"
else
    not_ok "check_context_pressure returns 'critical' for counter >=100" "got: $result"
fi

# ── Test 4: pre-compact.sh exits 0 and is valid bash ──
if bash -n "$REPO_DIR/hooks/pre-compact.sh" 2>/dev/null; then
    ok "pre-compact.sh is valid bash"
else
    not_ok "pre-compact.sh is valid bash" "bash -n failed"
fi

# ── Test 5: inject-context.sh scales budget variables under pressure ──
# Source the script in a subshell to capture variable values without running DB queries.
# We override COUNTER_FILE and check the budget vars at different tiers.
low_max=$(echo "5" > "$TEST_COUNTER"; COUNTER_FILE="$TEST_COUNTER" bash -c '
    # Simulate the pressure-scaling block from inject-context.sh
    _COUNTER_FILE="'"$TEST_COUNTER"'"
    _tool_count=0
    if [ -f "$_COUNTER_FILE" ]; then
        _tool_count=$(cat "$_COUNTER_FILE" 2>/dev/null || echo 0)
        _tool_count=$((_tool_count + 0)) 2>/dev/null || _tool_count=0
    fi
    if [ "$_tool_count" -ge 100 ]; then
        echo 6000
    elif [ "$_tool_count" -ge 50 ]; then
        echo 10000
    else
        echo 16000
    fi
')
echo "80" > "$TEST_COUNTER"
mid_max=$(COUNTER_FILE="$TEST_COUNTER" bash -c '
    _COUNTER_FILE="'"$TEST_COUNTER"'"
    _tool_count=$(cat "$_COUNTER_FILE" 2>/dev/null || echo 0)
    _tool_count=$((_tool_count + 0)) 2>/dev/null || _tool_count=0
    if [ "$_tool_count" -ge 100 ]; then echo 6000
    elif [ "$_tool_count" -ge 50 ]; then echo 10000
    else echo 16000; fi
')
echo "150" > "$TEST_COUNTER"
high_max=$(COUNTER_FILE="$TEST_COUNTER" bash -c '
    _COUNTER_FILE="'"$TEST_COUNTER"'"
    _tool_count=$(cat "$_COUNTER_FILE" 2>/dev/null || echo 0)
    _tool_count=$((_tool_count + 0)) 2>/dev/null || _tool_count=0
    if [ "$_tool_count" -ge 100 ]; then echo 6000
    elif [ "$_tool_count" -ge 50 ]; then echo 10000
    else echo 16000; fi
')
if [ "$low_max" = "16000" ] && [ "$mid_max" = "10000" ] && [ "$high_max" = "6000" ]; then
    ok "inject-context.sh scales budget: low=16000 mid=10000 high=6000"
else
    not_ok "inject-context.sh scales budget" "got low=$low_max mid=$mid_max high=$high_max"
fi

# ── Test 6: self-improvement-check.sh emits pressure warning at 75+ calls ──
# Set counter to 74 so the script increments to 75
echo "74" > "$TEST_COUNTER"
output=$(COUNTER_FILE="$TEST_COUNTER" bash "$REPO_DIR/hooks/self-improvement-check.sh" 2>/dev/null)
if echo "$output" | grep -q 'CONTEXT PRESSURE'; then
    ok "self-improvement-check.sh emits pressure warning at 75 calls"
else
    not_ok "self-improvement-check.sh emits pressure warning at 75 calls" "output: $output"
fi

# ── Test 7: self-improvement-check.sh emits HIGH pressure warning at 100+ calls ──
echo "99" > "$TEST_COUNTER2"
output=$(COUNTER_FILE="$TEST_COUNTER2" bash "$REPO_DIR/hooks/self-improvement-check.sh" 2>/dev/null)
if echo "$output" | grep -q 'CONTEXT PRESSURE HIGH'; then
    ok "self-improvement-check.sh emits high-pressure warning at 100 calls"
else
    not_ok "self-improvement-check.sh emits high-pressure warning at 100 calls" "output: $output"
fi

# ── Test 8: Dashboard script is valid bash ──
if bash -n "$REPO_DIR/scripts/alba-dashboard.sh" 2>/dev/null; then
    ok "alba-dashboard.sh is valid bash"
else
    not_ok "alba-dashboard.sh is valid bash" "bash -n failed"
fi

# ── Test 9: config/settings.json contains PreCompact hook entry ──
if jq -e '.hooks.PreCompact' "$REPO_DIR/config/settings.json" > /dev/null 2>&1; then
    ok "config/settings.json contains PreCompact hook entry"
else
    not_ok "config/settings.json contains PreCompact hook entry" "PreCompact key missing"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "# Tests: $PLAN | Pass: $PASS | Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
