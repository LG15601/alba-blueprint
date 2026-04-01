#!/usr/bin/env bash
# verify-gstack.sh — Integration verification for gstack bin tools and review output.
# Exits 0 if all checks pass, 1 otherwise.

set -euo pipefail

GSTACK_BIN="$HOME/.claude/skills/gstack/bin"
PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label"
    FAIL=$((FAIL + 1))
  fi
}

check_output() {
  local label="$1"
  local pattern="$2"
  shift 2
  local out
  out=$("$@" 2>&1) || true
  if echo "$out" | grep -qE "$pattern"; then
    echo "PASS  $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $label (expected pattern: $pattern)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== gstack Integration Verification ==="
echo ""

# 1. Bin tools exist and are executable
check "gstack-slug is executable"          test -x "$GSTACK_BIN/gstack-slug"
check "gstack-repo-mode is executable"     test -x "$GSTACK_BIN/gstack-repo-mode"
check "gstack-review-read is executable"   test -x "$GSTACK_BIN/gstack-review-read"
check "gstack-config is executable"        test -x "$GSTACK_BIN/gstack-config"
check "gstack-platform-detect is executable" test -x "$GSTACK_BIN/gstack-platform-detect"

# 2. Bin tools produce expected output patterns
check_output "gstack-slug outputs SLUG="           "^SLUG="           "$GSTACK_BIN/gstack-slug"
check_output "gstack-repo-mode outputs REPO_MODE="  "^REPO_MODE="     "$GSTACK_BIN/gstack-repo-mode"
check_output "gstack-review-read runs"               "(NO_REVIEWS|REVIEW)" "$GSTACK_BIN/gstack-review-read"
check_output "gstack-config list outputs config"     "(gstack|configuration)" "$GSTACK_BIN/gstack-config" list
check_output "gstack-platform-detect detects agent"  "(claude|Agent)" "$GSTACK_BIN/gstack-platform-detect"

# 3. Skill files exist
check "review checklist exists"  test -r "$HOME/.claude/skills/gstack/review/checklist.md"
check "qa SKILL.md exists"       test -r "$HOME/.claude/skills/gstack/qa/SKILL.md"

# 4. Review output from T01
REVIEW_OUTPUT=".gsd/milestones/M003/slices/S04/gstack-review-output.md"
check "review output file exists"              test -f "$REVIEW_OUTPUT"
check_output "review output has expected header" "Pre-Landing Review" cat "$REVIEW_OUTPUT"

# 5. Test branch cleaned up
BRANCH_COUNT=$(git branch --list test/gstack-review | wc -l | tr -d ' ')
if [ "$BRANCH_COUNT" -eq 0 ]; then
  echo "PASS  test branch cleaned up"
  PASS=$((PASS + 1))
else
  echo "FAIL  test branch cleaned up (found $BRANCH_COUNT branches)"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

[ "$FAIL" -eq 0 ]
