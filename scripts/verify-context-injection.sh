#!/usr/bin/env bash
# verify-context-injection.sh — TAP test suite for context injection hook
# Tests: syntax, output structure, token budget, table format,
#        full observations section, snapshot timestamp, re-injection guard,
#        empty DB fallback.
#
# Uses a temp DB with seeded test data. No side effects on real DB.
#
# Usage: bash scripts/verify-context-injection.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DB=$(mktemp /tmp/alba-ctx-inject-test.XXXXXX.db)
TEST_OUTPUT=$(mktemp /tmp/alba-ctx-output.XXXXXX.md)
TEST_LOG_DIR=$(mktemp -d /tmp/alba-ctx-logs.XXXXXX)
PLAN=8
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
    rm -f "$TEST_OUTPUT"
    rm -rf "$TEST_LOG_DIR"
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

# ─────────────────────────────────────────────────────────────
# 1. Syntax check inject-context.sh
# ─────────────────────────────────────────────────────────────
syntax_err=$(bash -n "$REPO_DIR/hooks/inject-context.sh" 2>&1)
if [ $? -eq 0 ]; then
    ok "Syntax check passes (bash -n)"
else
    not_ok "Syntax check passes (bash -n)" "$syntax_err"
fi

# ── Seed test database ───────────────────────────────────────
echo "# Initializing test database at $TEST_DB"
init_output=$(bash "$SCRIPT_DIR/alba-memory-init.sh" "$TEST_DB" 2>&1)
if [ $? -ne 0 ]; then
    echo "Bail out! alba-memory-init.sh failed: $init_output"
    exit 1
fi

# Insert a session with summary
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;

INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('sess-001', '/tmp/project-a', '2026-03-30T10:00:00Z', '2026-03-30T11:00:00Z', 42);
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('sess-002', '/tmp/project-b', '2026-03-31T14:00:00Z', '2026-03-31T15:30:00Z', 17);
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('sess-003', '/tmp/project-a', '2026-04-01T09:00:00Z', '2026-04-01T10:00:00Z', 55);

INSERT INTO session_summaries (session_id, request, investigated, learned, completed, next_steps)
VALUES ('sess-001', 'Build login flow', 'OAuth patterns', 'Token refresh needed', 'Login endpoint', 'Add refresh logic');
INSERT INTO session_summaries (session_id, request, investigated, learned, completed, next_steps)
VALUES ('sess-002', 'Fix memory leak', 'Event listeners', 'Unbind on unmount', 'Leak fixed', 'Add tests');
INSERT INTO session_summaries (session_id, request, investigated, learned, completed, next_steps)
VALUES ('sess-003', 'Deploy pipeline', 'CI configs', 'Cache docker layers', 'Pipeline live', 'Monitor performance');
SQL

# Insert 32 observations — 5 recent (full detail) + 25 older (table rows)
for i in $(seq 1 32); do
    ts=$(printf "2026-03-%02dT%02d:00:00Z" $(( (i % 28) + 1 )) $(( i % 24 )))
    sqlite3 "$TEST_DB" "
        PRAGMA foreign_keys = ON;
        INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
        VALUES (
            'sess-001',
            'discovery',
            'Test observation number $i',
            'subtitle for obs $i',
            'This is the narrative for observation $i. It contains details about what was found during testing session.',
            '[\"fact-$i-a\", \"fact-$i-b\"]',
            '[\"concept-$i\"]',
            '$ts'
        );
    "
done

echo "# Seeded $TEST_DB with 3 sessions + 32 observations"

# ── Run injection against seeded DB ──────────────────────────
# Remove any existing output to ensure fresh generation
rm -f "$TEST_OUTPUT"

ALBA_MEMORY_DB="$TEST_DB" \
ALBA_SESSION_CONTEXT="$TEST_OUTPUT" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/inject-context.sh" 2>&1

if [ ! -f "$TEST_OUTPUT" ]; then
    echo "Bail out! inject-context.sh produced no output file"
    exit 1
fi

output_content=$(cat "$TEST_OUTPUT")

# ─────────────────────────────────────────────────────────────
# 2. Context output contains '## Recent Memory' header
# ─────────────────────────────────────────────────────────────
if echo "$output_content" | grep -q '## Recent Memory'; then
    ok "Output contains '## Recent Memory' header"
else
    not_ok "Output contains '## Recent Memory' header" "header not found in output"
fi

# ─────────────────────────────────────────────────────────────
# 3. Token budget: output ≤16000 chars
# ─────────────────────────────────────────────────────────────
char_count=${#output_content}
if [ "$char_count" -le 16000 ]; then
    ok "Token budget: output is ${char_count} chars (≤16000)"
else
    not_ok "Token budget: output is ${char_count} chars (≤16000)" "exceeded by $(( char_count - 16000 ))"
fi

# ─────────────────────────────────────────────────────────────
# 4. Table format present (| ID | Time |)
# ─────────────────────────────────────────────────────────────
if echo "$output_content" | grep -q '| ID | Time |'; then
    ok "Table format present (| ID | Time |)"
else
    not_ok "Table format present (| ID | Time |)" "table header not found"
fi

# ─────────────────────────────────────────────────────────────
# 5. Full observations section present for recent entries
# ─────────────────────────────────────────────────────────────
if echo "$output_content" | grep -q '### Recent Observations'; then
    # Check that at least one full observation block is present
    if echo "$output_content" | grep -q '\[discovery\]'; then
        ok "Full observations section present with typed entries"
    else
        not_ok "Full observations section present with typed entries" "section header found but no typed entries"
    fi
else
    not_ok "Full observations section present with typed entries" "### Recent Observations header not found"
fi

# ─────────────────────────────────────────────────────────────
# 6. Snapshot timestamp present
# ─────────────────────────────────────────────────────────────
if echo "$output_content" | grep -q 'SNAPSHOT_GENERATED_AT:'; then
    ok "Snapshot timestamp present (SNAPSHOT_GENERATED_AT)"
else
    not_ok "Snapshot timestamp present (SNAPSHOT_GENERATED_AT)" "timestamp comment not found"
fi

# ─────────────────────────────────────────────────────────────
# 7. Re-injection guard works (skip if <5min old)
# ─────────────────────────────────────────────────────────────
# Check: output file mtime shouldn't have changed (guard skipped regeneration)
mtime_before=$(stat -f %m "$TEST_OUTPUT" 2>/dev/null || stat -c %Y "$TEST_OUTPUT" 2>/dev/null)
sleep 1
guard_output=$(ALBA_MEMORY_DB="$TEST_DB" \
ALBA_SESSION_CONTEXT="$TEST_OUTPUT" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/inject-context.sh" 2>&1)
mtime_after=$(stat -f %m "$TEST_OUTPUT" 2>/dev/null || stat -c %Y "$TEST_OUTPUT" 2>/dev/null)

if [ "$mtime_before" = "$mtime_after" ]; then
    ok "Re-injection guard: skips when output <5min old"
else
    not_ok "Re-injection guard: skips when output <5min old" "output file was regenerated (mtime changed)"
fi

# ─────────────────────────────────────────────────────────────
# 8. Empty DB produces minimal valid output (not crash)
# ─────────────────────────────────────────────────────────────
EMPTY_DB=$(mktemp /tmp/alba-ctx-empty.XXXXXX.db)
EMPTY_OUTPUT=$(mktemp /tmp/alba-ctx-empty-out.XXXXXX.md)
bash "$SCRIPT_DIR/alba-memory-init.sh" "$EMPTY_DB" > /dev/null 2>&1

# Force fresh generation by ensuring output doesn't exist
rm -f "$EMPTY_OUTPUT"

empty_exit=0
ALBA_MEMORY_DB="$EMPTY_DB" \
ALBA_SESSION_CONTEXT="$EMPTY_OUTPUT" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/inject-context.sh" 2>&1 || empty_exit=$?

if [ "$empty_exit" -eq 0 ] && [ -f "$EMPTY_OUTPUT" ]; then
    empty_content=$(cat "$EMPTY_OUTPUT")
    if echo "$empty_content" | grep -q 'SNAPSHOT_GENERATED_AT'; then
        ok "Empty DB produces valid output without crash"
    else
        not_ok "Empty DB produces valid output without crash" "output missing SNAPSHOT_GENERATED_AT"
    fi
else
    not_ok "Empty DB produces valid output without crash" "exit=$empty_exit or no output file"
fi

rm -f "$EMPTY_DB" "${EMPTY_DB}-wal" "${EMPTY_DB}-shm" "$EMPTY_OUTPUT"

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
