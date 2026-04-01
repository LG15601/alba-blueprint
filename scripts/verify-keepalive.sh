#!/bin/bash
# ==========================================================
# verify-keepalive.sh — Unit-level assertions for keepalive logic
# Exercises nudge detection, ANSI stripping, config, and status
# without requiring a live Telegram bot or tmux session.
# Output: TAP format (ok / not ok)
# Exit: 0 if all pass, 1 if any fail
# ==========================================================
set -u

SCRIPT="scripts/start-alba.sh"
PASS=0
FAIL=0
TEST_NUM=0

tap() {
    TEST_NUM=$((TEST_NUM + 1))
    local verdict="$1"
    local desc="$2"
    if [ "$verdict" = "ok" ]; then
        PASS=$((PASS + 1))
        echo "ok $TEST_NUM - $desc"
    else
        FAIL=$((FAIL + 1))
        echo "not ok $TEST_NUM - $desc"
    fi
}

# ---- Test 1: Syntax check ----
if bash -n "$SCRIPT" 2>/dev/null; then
    tap "ok" "bash -n syntax check passes"
else
    tap "FAIL" "bash -n syntax check passes"
fi

# ---- Test 2: Function exists ----
if grep -q 'nudge_if_idle' "$SCRIPT"; then
    tap "ok" "nudge_if_idle function exists"
else
    tap "FAIL" "nudge_if_idle function exists"
fi

# ---- Test 3: Config vars present ----
config_ok=true
for var in KEEPALIVE_INTERVAL IDLE_PROMPT_PATTERN NUDGE_COUNT_FILE; do
    if ! grep -q "^${var}=" "$SCRIPT"; then
        config_ok=false
    fi
done
if [ "$config_ok" = true ]; then
    tap "ok" "config vars KEEPALIVE_INTERVAL, IDLE_PROMPT_PATTERN, NUDGE_COUNT_FILE defined"
else
    tap "FAIL" "config vars KEEPALIVE_INTERVAL, IDLE_PROMPT_PATTERN, NUDGE_COUNT_FILE defined"
fi

# ---- Test 4: ANSI stripping ----
# Create temp file with ANSI-wrapped prompt, pipe through the same sed command
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf '\033[32m❯\033[0m\n' > "$tmpdir/ansi_input"
stripped=$(sed 's/\x1b\[[0-9;]*m//g' "$tmpdir/ansi_input")
if [ "$stripped" = "❯" ]; then
    tap "ok" "ANSI stripping produces bare prompt"
else
    tap "FAIL" "ANSI stripping produces bare prompt (got: '$stripped')"
fi

# ---- Test 5-7: Idle detection logic ----
# We simulate what nudge_if_idle does: strip ANSI, get last non-empty line,
# check if it matches ^[[:space:]]*❯[[:space:]]*$

detect_idle() {
    local input="$1"
    local last_line
    last_line=$(echo "$input" \
        | sed 's/\x1b\[[0-9;]*m//g' \
        | grep -v '^[[:space:]]*$' \
        | tail -1)
    if echo "$last_line" | grep -qE '^[[:space:]]*❯[[:space:]]*$'; then
        return 0  # idle
    fi
    return 1  # not idle
}

# Test 5: Idle pane (just the prompt)
idle_pane=$(printf '\n\n❯\n')
if detect_idle "$idle_pane"; then
    tap "ok" "idle detection: bare prompt → detected as idle"
else
    tap "FAIL" "idle detection: bare prompt → detected as idle"
fi

# Test 6: Active pane (multi-line tool output)
active_pane=$(printf 'Reading file: foo.ts\nLine 1: import stuff\nLine 2: export default\n⠋ Processing...\n')
if ! detect_idle "$active_pane"; then
    tap "ok" "idle detection: active tool output → NOT idle"
else
    tap "FAIL" "idle detection: active tool output → NOT idle"
fi

# Test 7: Prompt with typed text (user typing)
typing_pane=$(printf '❯ hello world\n')
if ! detect_idle "$typing_pane"; then
    tap "ok" "idle detection: prompt with typed text → NOT idle"
else
    tap "FAIL" "idle detection: prompt with typed text → NOT idle"
fi

# ---- Test 8: Status command doesn't error ----
status_out=$(bash "$SCRIPT" status 2>&1)
status_exit=$?
if [ "$status_exit" -eq 0 ]; then
    tap "ok" "status command exits 0 (output: $status_out)"
else
    tap "FAIL" "status command exits 0 (exit=$status_exit, output: $status_out)"
fi

# ---- Test 9: Log format prefix ----
if grep -q 'KEEPALIVE:' "$SCRIPT"; then
    tap "ok" "KEEPALIVE: log prefix present in script"
else
    tap "FAIL" "KEEPALIVE: log prefix present in script"
fi

# ---- Summary ----
TOTAL=$((PASS + FAIL))
echo ""
echo "1..$TOTAL"
echo "# pass: $PASS"
echo "# fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "# FAILED"
    exit 1
else
    echo "# ALL PASSED"
    exit 0
fi
