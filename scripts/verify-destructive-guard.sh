#!/usr/bin/env bash
# verify-destructive-guard.sh — TAP test suite for destructive-command-guard.sh
#
# Tests: config validity, block tier (rm, fork bomb), allow tier (safe paths),
#        warn tier (force push, SQL), edge cases (variables, quoted paths).
#
# Usage: bash scripts/verify-destructive-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_DIR/hooks/destructive-command-guard.sh"
CONFIG="$REPO_DIR/config/destructive-commands.json"

PLAN=12
PASS=0
FAIL=0
TEST_NUM=0

cd "$REPO_DIR"

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
    [[ -n "${2:-}" ]] && echo "  # $2"
}

# Helper: run guard with a command string, capture exit code and stdout
run_guard() {
    local cmd="$1"
    local input='{"tool_input":{"command":"'"$cmd"'"}}'
    GUARD_OUTPUT=$(echo "$input" | bash "$GUARD" 2>/dev/null) || true
    # Re-run to capture exit code properly
    echo "$input" | bash "$GUARD" >/dev/null 2>/dev/null
    GUARD_EXIT=$?
}

echo "TAP version 14"
echo "1..$PLAN"

# ═════════════════════════════════════════════════════════════
# Test 1: Config file valid JSON
# ═════════════════════════════════════════════════════════════
if jq . "$CONFIG" >/dev/null 2>&1; then
    ok "Config file is valid JSON"
else
    not_ok "Config file is valid JSON" "jq parse failed"
fi

# ═════════════════════════════════════════════════════════════
# Test 2: rm -rf / is blocked
# ═════════════════════════════════════════════════════════════
run_guard 'rm -rf /'
if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "rm -rf / is blocked (exit 2)"
else
    not_ok "rm -rf / is blocked (exit 2)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 3: rm -rf ~ is blocked
# ═════════════════════════════════════════════════════════════
run_guard 'rm -rf ~'
if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "rm -rf ~ is blocked (exit 2)"
else
    not_ok "rm -rf ~ is blocked (exit 2)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 4: sudo rm -rf /var is blocked
# ═════════════════════════════════════════════════════════════
run_guard 'sudo rm -rf /var'
if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "sudo rm -rf /var is blocked (exit 2)"
else
    not_ok "sudo rm -rf /var is blocked (exit 2)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 5: Fork bomb is blocked
# ═════════════════════════════════════════════════════════════
run_guard ':(){ :|:& };:'
if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "Fork bomb is blocked (exit 2)"
else
    not_ok "Fork bomb is blocked (exit 2)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 6: rm -rf ./build is allowed
# ═════════════════════════════════════════════════════════════
run_guard 'rm -rf ./build'
if [[ "$GUARD_EXIT" -eq 0 ]]; then
    ok "rm -rf ./build is allowed (exit 0)"
else
    not_ok "rm -rf ./build is allowed (exit 0)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 7: rm tempfile.txt is allowed
# ═════════════════════════════════════════════════════════════
run_guard 'rm tempfile.txt'
if [[ "$GUARD_EXIT" -eq 0 ]]; then
    ok "rm tempfile.txt is allowed (exit 0)"
else
    not_ok "rm tempfile.txt is allowed (exit 0)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 8: git push --force warns but allows
# ═════════════════════════════════════════════════════════════
run_guard 'git push --force origin main'
if [[ "$GUARD_EXIT" -eq 0 ]] && echo "$GUARD_OUTPUT" | grep -q "additionalContext"; then
    ok "git push --force warns but allows (exit 0 + additionalContext)"
else
    not_ok "git push --force warns but allows" "exit=$GUARD_EXIT output=$GUARD_OUTPUT"
fi

# ═════════════════════════════════════════════════════════════
# Test 9: DROP TABLE warns but allows
# ═════════════════════════════════════════════════════════════
run_guard 'DROP TABLE users'
if [[ "$GUARD_EXIT" -eq 0 ]] && echo "$GUARD_OUTPUT" | grep -q "additionalContext"; then
    ok "DROP TABLE warns but allows (exit 0 + additionalContext)"
else
    not_ok "DROP TABLE warns but allows" "exit=$GUARD_EXIT output=$GUARD_OUTPUT"
fi

# ═════════════════════════════════════════════════════════════
# Test 10: rm -rf with variable target warns
# ═════════════════════════════════════════════════════════════
GUARD_OUTPUT=$(echo '{"tool_input":{"command":"rm -rf $SOMEDIR"}}' | bash "$GUARD" 2>/dev/null) || true
echo '{"tool_input":{"command":"rm -rf $SOMEDIR"}}' | bash "$GUARD" >/dev/null 2>/dev/null
GUARD_EXIT=$?
if [[ "$GUARD_EXIT" -eq 0 ]] && echo "$GUARD_OUTPUT" | grep -q "additionalContext"; then
    ok "rm -rf with variable target warns (exit 0 + warning)"
else
    not_ok "rm -rf with variable target warns" "exit=$GUARD_EXIT output=$GUARD_OUTPUT"
fi

# ═════════════════════════════════════════════════════════════
# Test 11: Quoted path rm -rf "/" is blocked
# ═════════════════════════════════════════════════════════════
T11_INPUT=$(jq -n --arg cmd 'rm -rf "/"' '{"tool_input":{"command":$cmd}}')
GUARD_OUTPUT=$(echo "$T11_INPUT" | bash "$GUARD" 2>/dev/null) || true
echo "$T11_INPUT" | bash "$GUARD" >/dev/null 2>/dev/null
GUARD_EXIT=$?
if [[ "$GUARD_EXIT" -eq 2 ]]; then
    ok "rm -rf with quoted root path is blocked (exit 2)"
else
    not_ok "rm -rf with quoted root path is blocked (exit 2)" "got exit $GUARD_EXIT"
fi

# ═════════════════════════════════════════════════════════════
# Test 12: Safe command passes through silently
# ═════════════════════════════════════════════════════════════
run_guard 'ls -la'
if [[ "$GUARD_EXIT" -eq 0 ]] && [[ -z "$GUARD_OUTPUT" ]]; then
    ok "Safe command passes through silently (exit 0, no output)"
else
    not_ok "Safe command passes through silently" "exit=$GUARD_EXIT output=$GUARD_OUTPUT"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "# destructive-guard: $PASS/$PLAN passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
