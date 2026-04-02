#!/usr/bin/env bash
# verify-pattern-promotion.sh — TAP test suite for the pattern promotion pipeline
# Tests: migration 003, pattern detection, rule content, dedup, below-threshold,
#        singleton, idempotency, empty DB.
#
# Uses temp DB + temp rules dir. No side effects on real data.
#
# Usage: bash tests/verify-pattern-promotion.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DB=$(mktemp /tmp/alba-pp-test.XXXXXX.db)
TEST_RULES_DIR=$(mktemp -d /tmp/alba-pp-rules.XXXXXX)
TEST_LOG_DIR=$(mktemp -d /tmp/alba-pp-logs.XXXXXX)

PLAN=8
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
    rm -rf "$TEST_RULES_DIR" "$TEST_LOG_DIR"
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

# ── Initialize DB with all migrations (001 + 002 + 003) ─────
echo "# Initializing test database at $TEST_DB"
init_output=$(bash "$REPO_DIR/scripts/alba-memory-init.sh" "$TEST_DB" 2>&1)
if [ $? -ne 0 ]; then
    echo "Bail out! alba-memory-init.sh failed: $init_output"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# 1. Migration 003 — promoted_rules table exists with expected columns
# ─────────────────────────────────────────────────────────────
tables=$(sqlite3 "$TEST_DB" ".tables" 2>/dev/null)
if echo "$tables" | grep -q 'promoted_rules'; then
    cols=$(sqlite3 "$TEST_DB" "PRAGMA table_info(promoted_rules);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ' ')
    expected_cols="id rule_name source_learning_ids content_hash created_at"
    all_found=true
    for col in $expected_cols; do
        if ! echo "$cols" | grep -qw "$col"; then
            all_found=false
            break
        fi
    done
    if $all_found; then
        ok "Migration 003: promoted_rules table exists with expected columns"
    else
        not_ok "Migration 003: promoted_rules table exists with expected columns" "missing columns; got: $cols"
    fi
else
    not_ok "Migration 003: promoted_rules table exists with expected columns" "promoted_rules table not found; tables: $tables"
fi

# ── Seed test data ───────────────────────────────────────────
echo "# Seeding test session and learnings"
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;

-- Fake session (learnings reference sessions via FK)
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('pp-test-sess', '/tmp/pp-test', '2026-03-30T10:00:00Z', '2026-03-30T11:00:00Z', 5);

-- Category 'pattern': 3 learnings about macOS locking — should cluster & promote
INSERT INTO learnings (session_id, source, content, content_hash, category, created_at)
VALUES
    ('pp-test-sess', 'observation', 'macOS has no flock use mkdir locking instead', 'hash-lock-1', 'pattern', '2026-03-30T10:10:00Z'),
    ('pp-test-sess', 'observation', 'Use mkdir-based locks on macOS instead of flock', 'hash-lock-2', 'pattern', '2026-03-30T10:20:00Z'),
    ('pp-test-sess', 'observation', 'mkdir atomic locking replaces flock on macOS', 'hash-lock-3', 'pattern', '2026-03-30T10:30:00Z');

-- Category 'pattern': 2 learnings about a different topic (below threshold, no term overlap with locking cluster)
INSERT INTO learnings (session_id, source, content, content_hash, category, created_at)
VALUES
    ('pp-test-sess', 'observation', 'Python virtualenv activation requires source command', 'hash-venv-1', 'pattern', '2026-03-30T10:40:00Z'),
    ('pp-test-sess', 'observation', 'Virtualenv pip install works only after source activate', 'hash-venv-2', 'pattern', '2026-03-30T10:50:00Z');

-- Category 'gotcha': 1 singleton learning (should NOT promote)
INSERT INTO learnings (session_id, source, content, content_hash, category, created_at)
VALUES
    ('pp-test-sess', 'observation', 'Bash set -e exits on falsy arithmetic with ((var++))', 'hash-gotcha-1', 'gotcha', '2026-03-30T11:00:00Z');
SQL

# ─────────────────────────────────────────────────────────────
# 2. Pattern detection — exactly 1 rule file created
# ─────────────────────────────────────────────────────────────
echo "# Running promote-patterns.sh against test DB"
promote_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/promote-patterns.sh" \
    --db "$TEST_DB" --rules-dir "$TEST_RULES_DIR" 2>&1)
promote_exit=$?

rule_files=$(find "$TEST_RULES_DIR" -name 'auto-*.md' -type f 2>/dev/null)
rule_count=$(echo "$rule_files" | grep -c '.' 2>/dev/null || echo "0")

if [ "$promote_exit" -eq 0 ] && [ "$rule_count" -eq 1 ]; then
    ok "Pattern detection: promote-patterns.sh created exactly 1 rule file"
else
    not_ok "Pattern detection: promote-patterns.sh created exactly 1 rule file" \
        "exit=$promote_exit count=$rule_count output=$promote_output"
fi

# ─────────────────────────────────────────────────────────────
# 3. Rule file content — correct markers and source learnings
# ─────────────────────────────────────────────────────────────
if [ "$rule_count" -eq 1 ]; then
    rule_file=$(echo "$rule_files" | head -1)
    rule_body=$(cat "$rule_file")

    has_marker=false
    has_heading=false
    has_source_section=false
    source_count=0

    echo "$rule_body" | grep -q '<!-- auto-promoted -->' && has_marker=true
    echo "$rule_body" | grep -q '# Auto-Promoted Pattern:' && has_heading=true
    echo "$rule_body" | grep -q '## Source Learnings' && has_source_section=true
    source_count=$(echo "$rule_body" | grep -c '\[Learning #' || true)

    if $has_marker && $has_heading && $has_source_section && [ "$source_count" -ge 3 ]; then
        ok "Rule file content: has auto-promoted marker, heading, and $source_count source learnings"
    else
        not_ok "Rule file content: has auto-promoted marker, heading, and source learnings" \
            "marker=$has_marker heading=$has_heading sources=$has_source_section count=$source_count"
    fi
else
    not_ok "Rule file content: has auto-promoted marker, heading, and source learnings" \
        "skipped — no single rule file to inspect"
fi

# ─────────────────────────────────────────────────────────────
# 4. promoted_rules table — 1 row with correct data
# ─────────────────────────────────────────────────────────────
pr_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM promoted_rules;" 2>/dev/null || echo "0")
if [ "$pr_count" -eq 1 ]; then
    pr_ids=$(sqlite3 "$TEST_DB" "SELECT source_learning_ids FROM promoted_rules LIMIT 1;" 2>/dev/null)
    pr_name=$(sqlite3 "$TEST_DB" "SELECT rule_name FROM promoted_rules LIMIT 1;" 2>/dev/null)
    # All 3 learning IDs should be referenced
    id_count=$(echo "$pr_ids" | tr ',' '\n' | wc -l | tr -d ' ')
    if [ "$id_count" -ge 3 ] && [ -n "$pr_name" ]; then
        ok "promoted_rules table: 1 row, rule_name='$pr_name', $id_count source learning IDs"
    else
        not_ok "promoted_rules table: 1 row with correct data" \
            "name=$pr_name ids=$pr_ids id_count=$id_count"
    fi
else
    not_ok "promoted_rules table: 1 row with correct data" "row count=$pr_count (expected 1)"
fi

# ─────────────────────────────────────────────────────────────
# 5. Below threshold — 2-learning WAL cluster did NOT produce a rule
# ─────────────────────────────────────────────────────────────
wal_rule=$(find "$TEST_RULES_DIR" -name 'auto-*virtualenv*' -o -name 'auto-*venv*' -type f 2>/dev/null | head -1)
wal_rule_via_content=$(grep -rl 'virtualenv' "$TEST_RULES_DIR" 2>/dev/null | head -1)

if [ -z "$wal_rule" ] && [ -z "$wal_rule_via_content" ]; then
    ok "Below threshold: 2-learning virtualenv cluster did NOT produce a rule file"
else
    not_ok "Below threshold: 2-learning virtualenv cluster did NOT produce a rule file" \
        "found: ${wal_rule:-$wal_rule_via_content}"
fi

# ─────────────────────────────────────────────────────────────
# 6. Singleton — single 'gotcha' learning did NOT produce a rule
# ─────────────────────────────────────────────────────────────
gotcha_rule=$(find "$TEST_RULES_DIR" -name 'auto-*gotcha*' -o -name 'auto-*arithmetic*' -type f 2>/dev/null | head -1)
gotcha_rule_via_content=$(grep -rl 'set -e' "$TEST_RULES_DIR" 2>/dev/null | head -1)

if [ -z "$gotcha_rule" ] && [ -z "$gotcha_rule_via_content" ]; then
    ok "Singleton: gotcha learning did NOT produce a rule file"
else
    not_ok "Singleton: gotcha learning did NOT produce a rule file" \
        "found: ${gotcha_rule:-$gotcha_rule_via_content}"
fi

# ─────────────────────────────────────────────────────────────
# 7. Idempotency — re-run creates no new rules
# ─────────────────────────────────────────────────────────────
files_before=$(find "$TEST_RULES_DIR" -name 'auto-*.md' -type f | wc -l | tr -d ' ')
rows_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM promoted_rules;" 2>/dev/null || echo "0")

ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/promote-patterns.sh" \
    --db "$TEST_DB" --rules-dir "$TEST_RULES_DIR" 2>/dev/null

files_after=$(find "$TEST_RULES_DIR" -name 'auto-*.md' -type f | wc -l | tr -d ' ')
rows_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM promoted_rules;" 2>/dev/null || echo "0")

if [ "$files_after" -eq "$files_before" ] && [ "$rows_after" -eq "$rows_before" ]; then
    ok "Idempotency: re-run produces no new rules ($files_before files, $rows_before rows)"
else
    not_ok "Idempotency: re-run produces no new rules" \
        "files: $files_before→$files_after rows: $rows_before→$rows_after"
fi

# ─────────────────────────────────────────────────────────────
# 8. Empty DB — fresh DB with no learnings, exits 0 with no files
# ─────────────────────────────────────────────────────────────
EMPTY_DB=$(mktemp /tmp/alba-pp-empty.XXXXXX.db)
EMPTY_RULES=$(mktemp -d /tmp/alba-pp-empty-rules.XXXXXX)

bash "$REPO_DIR/scripts/alba-memory-init.sh" "$EMPTY_DB" > /dev/null 2>&1

empty_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/promote-patterns.sh" \
    --db "$EMPTY_DB" --rules-dir "$EMPTY_RULES" 2>&1)
empty_exit=$?

empty_files=$(find "$EMPTY_RULES" -name 'auto-*.md' -type f | wc -l | tr -d ' ')

if [ "$empty_exit" -eq 0 ] && [ "$empty_files" -eq 0 ]; then
    ok "Empty DB: exits 0 with no rule files created"
else
    not_ok "Empty DB: exits 0 with no rule files created" \
        "exit=$empty_exit files=$empty_files"
fi

rm -f "$EMPTY_DB" "${EMPTY_DB}-wal" "${EMPTY_DB}-shm"
rm -rf "$EMPTY_RULES"

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
