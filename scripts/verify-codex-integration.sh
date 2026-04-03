#!/bin/bash
# ==========================================================
# verify-codex-integration.sh — TAP tests for Codex skill integration
# Verifies binary, auth, skill files, slash commands, and install.sh wiring.
# Output: TAP format (ok / not ok)
# Exit: 0 if all pass, 1 if any fail
# ==========================================================
set -u

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

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ---- Test 1: codex binary exists ----
if command -v codex >/dev/null 2>&1; then
    tap "ok" "codex binary exists on PATH"
else
    tap "FAIL" "codex binary exists on PATH"
fi

# ---- Test 2: codex auth configured ----
if [ -f ~/.codex/auth.json ]; then
    tap "ok" "codex auth.json exists"
else
    tap "FAIL" "codex auth.json exists"
fi

# ---- Test 3: codex review --help exits 0 ----
if codex review --help >/dev/null 2>&1; then
    tap "ok" "codex review --help exits 0"
else
    tap "FAIL" "codex review --help exits 0"
fi

# ---- Test 4: codex-review.sh passes bash -n syntax check ----
if bash -n "$SCRIPT_DIR/skills/codex/scripts/codex-review.sh" 2>/dev/null; then
    tap "ok" "codex-review.sh passes bash -n"
else
    tap "FAIL" "codex-review.sh passes bash -n"
fi

# ---- Test 5: codex-rescue.sh passes bash -n syntax check ----
if bash -n "$SCRIPT_DIR/skills/codex/scripts/codex-rescue.sh" 2>/dev/null; then
    tap "ok" "codex-rescue.sh passes bash -n"
else
    tap "FAIL" "codex-rescue.sh passes bash -n"
fi

# ---- Test 6: SKILL.md exists and contains 'codex' ----
if [ -f "$SCRIPT_DIR/skills/codex/SKILL.md" ] && grep -qi 'codex' "$SCRIPT_DIR/skills/codex/SKILL.md"; then
    tap "ok" "SKILL.md exists and mentions codex"
else
    tap "FAIL" "SKILL.md exists and mentions codex"
fi

# ---- Test 7: commands/codex/review.md exists ----
if [ -f "$SCRIPT_DIR/commands/codex/review.md" ]; then
    tap "ok" "commands/codex/review.md exists"
else
    tap "FAIL" "commands/codex/review.md exists"
fi

# ---- Test 8: commands/codex/rescue.md exists ----
if [ -f "$SCRIPT_DIR/commands/codex/rescue.md" ]; then
    tap "ok" "commands/codex/rescue.md exists"
else
    tap "FAIL" "commands/codex/rescue.md exists"
fi

# ---- Test 9: codex-rescue.sh prints usage when called with no args ----
rescue_output=$("$SCRIPT_DIR/skills/codex/scripts/codex-rescue.sh" 2>&1) && rescue_exit=0 || rescue_exit=$?
# Script should exit non-zero and print usage
if [ $rescue_exit -ne 0 ] && echo "$rescue_output" | grep -qi 'usage'; then
    tap "ok" "codex-rescue.sh prints usage on no args (exit $rescue_exit)"
else
    tap "FAIL" "codex-rescue.sh prints usage on no args (exit $rescue_exit)"
fi

# ---- Test 10: install.sh contains commands copy block ----
if grep -q 'commands/' "$SCRIPT_DIR/install.sh"; then
    tap "ok" "install.sh contains commands copy block"
else
    tap "FAIL" "install.sh contains commands copy block"
fi

# ---- Summary ----
echo ""
echo "1..$TEST_NUM"
echo "# pass $PASS / $TEST_NUM"
if [ "$FAIL" -gt 0 ]; then
    echo "# FAIL $FAIL test(s)"
    exit 1
fi
echo "# All tests passed"
exit 0
