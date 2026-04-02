#!/usr/bin/env bash
# verify-skills-guard.sh — TAP test suite for skills_guard.py
#
# Tests: syntax, malicious detection, category reporting, clean file pass,
#        trust matrix exemptions, single-file mode, and memory_guard regression.
#
# Usage: bash scripts/verify-skills-guard.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$REPO_DIR/scripts/security/skills_guard.py"
TRUST="$REPO_DIR/config/trust-matrix.json"
MALICIOUS="$REPO_DIR/tests/fixtures/malicious-skill"
CLEAN="$REPO_DIR/tests/fixtures/clean-skill"
# Use relative path for skills/ — trust matrix globs are relative
SKILLS="skills"
PLAN=8
PASS=0
FAIL=0
TEST_NUM=0

# Run from repo root so relative skills/ path resolves correctly
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

echo "TAP version 14"
echo "1..$PLAN"

# ═════════════════════════════════════════════════════════════
# Test 1: Syntax check
# ═════════════════════════════════════════════════════════════
if python3 -c "import py_compile; py_compile.compile('$GUARD', doraise=True)" 2>/dev/null; then
    ok "skills_guard.py passes syntax check"
else
    not_ok "skills_guard.py passes syntax check" "py_compile failed"
fi

# ═════════════════════════════════════════════════════════════
# Test 2: Malicious skill blocked with CRITICAL exit code
# ═════════════════════════════════════════════════════════════
python3 "$GUARD" --dir "$MALICIOUS" --json >/dev/null 2>/dev/null
exit_code=$?
if [[ "$exit_code" -eq 2 ]]; then
    ok "Malicious skill blocked with CRITICAL exit code (exit 2)"
else
    not_ok "Malicious skill blocked with CRITICAL exit code (exit 2)" "got exit $exit_code"
fi

# ═════════════════════════════════════════════════════════════
# Test 3: Malicious skill JSON contains expected categories
# ═════════════════════════════════════════════════════════════
output=$(python3 "$GUARD" --dir "$MALICIOUS" --json 2>/dev/null) || true
missing=""
for cat in supply_chain network credential_exposure prompt_injection; do
    if ! echo "$output" | grep -q "\"$cat\""; then
        missing="$missing $cat"
    fi
done
if [[ -z "$missing" ]]; then
    ok "Malicious skill reports expected categories (supply_chain, network, credential_exposure, prompt_injection)"
else
    not_ok "Malicious skill reports expected categories" "missing:$missing"
fi

# ═════════════════════════════════════════════════════════════
# Test 4: Clean skill passes with exit 0
# ═════════════════════════════════════════════════════════════
clean_output=$(python3 "$GUARD" --dir "$CLEAN" --json 2>/dev/null)
clean_exit=$?
clean_findings=$(echo "$clean_output" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_findings',0))" 2>/dev/null) || true
if [[ "$clean_exit" -eq 0 ]] && [[ "$clean_findings" == "0" ]]; then
    ok "Clean skill passes with exit 0 and no findings"
else
    not_ok "Clean skill passes with exit 0 and no findings" "exit=$clean_exit findings=$clean_findings"
fi

# ═════════════════════════════════════════════════════════════
# Test 5: Trust matrix exempts known patterns in real skills
# ═════════════════════════════════════════════════════════════
if [[ -d "$SKILLS" ]] && [[ -f "$TRUST" ]]; then
    python3 "$GUARD" --dir "$SKILLS" --trust-matrix "$TRUST" --json >/dev/null 2>/dev/null
    tm_exit=$?
    if [[ "$tm_exit" -eq 0 ]]; then
        ok "Trust matrix exempts known patterns in real skills (exit 0)"
    else
        not_ok "Trust matrix exempts known patterns in real skills (exit 0)" "got exit $tm_exit"
    fi
else
    not_ok "Trust matrix exempts known patterns in real skills (exit 0)" "skills/ or trust-matrix.json missing"
fi

# ═════════════════════════════════════════════════════════════
# Test 6: Scanner without trust matrix flags real skills
# ═════════════════════════════════════════════════════════════
if [[ -d "$SKILLS" ]]; then
    python3 "$GUARD" --dir "$SKILLS" --json >/dev/null 2>/dev/null
    no_tm_exit=$?
    if [[ "$no_tm_exit" -ne 0 ]]; then
        ok "Scanner without trust matrix flags real skills (exit $no_tm_exit)"
    else
        not_ok "Scanner without trust matrix flags real skills" "expected non-zero exit, got 0"
    fi
else
    not_ok "Scanner without trust matrix flags real skills" "skills/ directory missing"
fi

# ═════════════════════════════════════════════════════════════
# Test 7: Single file mode works (--file flag)
# ═════════════════════════════════════════════════════════════
file_output=$(python3 "$GUARD" --file "$MALICIOUS/SKILL.md" --json 2>/dev/null)
file_exit=$?
file_findings=$(echo "$file_output" | python3 -c "import sys,json; print(json.load(sys.stdin).get('total_findings',0))" 2>/dev/null) || true
if [[ "$file_exit" -eq 2 ]] && [[ "$file_findings" -gt 0 ]]; then
    ok "Single file mode works (--file flag, exit 2, $file_findings findings)"
else
    not_ok "Single file mode works (--file flag)" "exit=$file_exit findings=$file_findings"
fi

# ═════════════════════════════════════════════════════════════
# Test 8: Regression — memory_guard tests still pass
# ═════════════════════════════════════════════════════════════
if [[ -f "$REPO_DIR/scripts/verify-guard.sh" ]]; then
    guard_output=$(bash "$REPO_DIR/scripts/verify-guard.sh" 2>/dev/null)
    guard_exit=$?
    if [[ "$guard_exit" -eq 0 ]]; then
        ok "memory_guard regression check passes (verify-guard.sh)"
    else
        not_ok "memory_guard regression check passes" "verify-guard.sh exit=$guard_exit"
    fi
else
    not_ok "memory_guard regression check passes" "verify-guard.sh not found"
fi

# ── Summary ──────────────────────────────────────────────────
echo ""
echo "# skills-guard: $PASS/$PLAN passed, $FAIL failed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
