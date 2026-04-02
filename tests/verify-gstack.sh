#!/usr/bin/env bash
# verify-gstack.sh — TAP integration verification for gstack bin tools and review output.
# Produces standard TAP output. Exits 0 if all pass, 1 otherwise.

set -euo pipefail

GSTACK_BIN="$HOME/.claude/skills/gstack/bin"

# Skip all if gstack binaries not installed
if [ ! -d "$GSTACK_BIN" ]; then
  echo "1..0 # SKIP gstack bin tools not installed"
  exit 0
fi

TOTAL=15
echo "1..$TOTAL"

TEST_NUM=0
FAIL=0

tap_check() {
  local label="$1"
  shift
  TEST_NUM=$((TEST_NUM + 1))
  if "$@" > /dev/null 2>&1; then
    echo "ok $TEST_NUM - $label"
  else
    echo "not ok $TEST_NUM - $label"
    FAIL=$((FAIL + 1))
  fi
}

tap_check_output() {
  local label="$1"
  local pattern="$2"
  shift 2
  TEST_NUM=$((TEST_NUM + 1))
  local out
  out=$("$@" 2>&1) || true
  if echo "$out" | grep -qE "$pattern"; then
    echo "ok $TEST_NUM - $label"
  else
    echo "not ok $TEST_NUM - $label # expected pattern: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

# 1. Bin tools exist and are executable
tap_check "gstack-slug is executable"              test -x "$GSTACK_BIN/gstack-slug"
tap_check "gstack-repo-mode is executable"         test -x "$GSTACK_BIN/gstack-repo-mode"
tap_check "gstack-review-read is executable"       test -x "$GSTACK_BIN/gstack-review-read"
tap_check "gstack-config is executable"            test -x "$GSTACK_BIN/gstack-config"
tap_check "gstack-platform-detect is executable"   test -x "$GSTACK_BIN/gstack-platform-detect"

# 2. Bin tools produce expected output patterns
tap_check_output "gstack-slug outputs SLUG="            "^SLUG="           "$GSTACK_BIN/gstack-slug"
tap_check_output "gstack-repo-mode outputs REPO_MODE="  "^REPO_MODE="      "$GSTACK_BIN/gstack-repo-mode"
tap_check_output "gstack-review-read runs"               "(NO_REVIEWS|REVIEW)" "$GSTACK_BIN/gstack-review-read"
tap_check_output "gstack-config list outputs config"     "(gstack|configuration)" "$GSTACK_BIN/gstack-config" list
tap_check_output "gstack-platform-detect detects agent"  "(claude|Agent)" "$GSTACK_BIN/gstack-platform-detect"

# 3. Skill files exist
tap_check "review checklist exists"  test -r "$HOME/.claude/skills/gstack/review/checklist.md"
tap_check "qa SKILL.md exists"       test -r "$HOME/.claude/skills/gstack/qa/SKILL.md"

# 4. Review output from T01
REVIEW_OUTPUT=".gsd/milestones/M003/slices/S04/gstack-review-output.md"
tap_check "review output file exists"              test -f "$REVIEW_OUTPUT"
tap_check_output "review output has expected header" "Pre-Landing Review" cat "$REVIEW_OUTPUT"

# 5. Test branch cleaned up
BRANCH_COUNT=$(git branch --list test/gstack-review | wc -l | tr -d ' ')
TEST_NUM=$((TEST_NUM + 1))
if [ "$BRANCH_COUNT" -eq 0 ]; then
  echo "ok $TEST_NUM - test branch cleaned up"
else
  echo "not ok $TEST_NUM - test branch cleaned up # found $BRANCH_COUNT branches"
  FAIL=$((FAIL + 1))
fi

[ "$FAIL" -eq 0 ]
