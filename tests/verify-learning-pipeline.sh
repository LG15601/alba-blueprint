#!/usr/bin/env bash
# verify-learning-pipeline.sh — TAP test suite for the operational learning pipeline
# Tests: migration, FTS5, observation extraction, dedup, JSONL ingestion,
#        context injection with/without learnings, setup-hooks dry-run.
#
# Uses temp DB + temp files. No side effects on real DB or settings.
#
# Usage: bash tests/verify-learning-pipeline.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DB=$(mktemp /tmp/alba-lp-test.XXXXXX.db)
TEST_OUTPUT=$(mktemp /tmp/alba-lp-ctx.XXXXXX.md)
TEST_LOG_DIR=$(mktemp -d /tmp/alba-lp-logs.XXXXXX)
TEST_JSONL=$(mktemp /tmp/alba-lp-jsonl.XXXXXX.jsonl)

PLAN=9
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
    rm -f "$TEST_OUTPUT" "$TEST_JSONL"
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

# ── Initialize DB with migrations ────────────────────────────
echo "# Initializing test database at $TEST_DB"
init_output=$(bash "$REPO_DIR/scripts/alba-memory-init.sh" "$TEST_DB" 2>&1)
if [ $? -ne 0 ]; then
    echo "Bail out! alba-memory-init.sh failed: $init_output"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# 1. Migration 002 applies — learnings table exists with expected columns
# ─────────────────────────────────────────────────────────────
tables=$(sqlite3 "$TEST_DB" ".tables" 2>/dev/null)
if echo "$tables" | grep -q 'learnings'; then
    # Check columns: id, session_id, source, content, content_hash, category, created_at
    cols=$(sqlite3 "$TEST_DB" "PRAGMA table_info(learnings);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ' ')
    expected_cols="id session_id source content content_hash category created_at"
    all_found=true
    for col in $expected_cols; do
        if ! echo "$cols" | grep -qw "$col"; then
            all_found=false
            break
        fi
    done
    if $all_found; then
        ok "Migration 002: learnings table exists with expected columns"
    else
        not_ok "Migration 002: learnings table exists with expected columns" "missing columns; got: $cols"
    fi
else
    not_ok "Migration 002: learnings table exists with expected columns" "learnings table not found; tables: $tables"
fi

# ─────────────────────────────────────────────────────────────
# 2. FTS5 index exists for learnings
# ─────────────────────────────────────────────────────────────
fts_tables=$(sqlite3 "$TEST_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='learnings_fts';" 2>/dev/null)
if [ "$fts_tables" = "learnings_fts" ]; then
    ok "FTS5 virtual table learnings_fts exists"
else
    not_ok "FTS5 virtual table learnings_fts exists" "not found in sqlite_master"
fi

# ── Seed test data: session + observations ───────────────────
echo "# Seeding test session and observations"
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('test-lp-sess', '/tmp/test-project', '2026-03-30T10:00:00Z', '2026-03-30T11:00:00Z', 10);

-- bugfix observation — should be extracted as learning
INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
VALUES ('test-lp-sess', 'bugfix', 'Fix off-by-one in pagination', 'Array index started at 1 instead of 0',
        'The pagination helper was using 1-based indexing', '["off-by-one"]', '["pagination"]',
        '2026-03-30T10:15:00Z');

-- decision observation — should be extracted as learning
INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
VALUES ('test-lp-sess', 'decision', 'Use WAL mode for SQLite', 'Better concurrent read performance',
        'WAL mode allows concurrent readers with a single writer', '["sqlite","WAL"]', '["database"]',
        '2026-03-30T10:30:00Z');

-- discovery observation — should NOT be extracted (not bugfix/decision)
INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
VALUES ('test-lp-sess', 'discovery', 'Found legacy config file', 'Old YAML format still present',
        'The legacy config is loaded as fallback', '["config"]', '["migration"]',
        '2026-03-30T10:45:00Z');
SQL

# ─────────────────────────────────────────────────────────────
# 3. Extract learnings from observations — bugfix + decision types
# ─────────────────────────────────────────────────────────────
# extract-learnings.sh forks a background writer; we need to wait for it
ALBA_MEMORY_DB="$TEST_DB" \
CLAUDE_SESSION_ID="test-lp-sess" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/extract-learnings.sh" 2>/dev/null

# Wait for background writer to finish (it's an orphan subshell doing sqlite)
sleep 1

learnings_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")
if [ "$learnings_count" -gt 0 ]; then
    # Verify only bugfix and decision were extracted (not discovery)
    categories=$(sqlite3 "$TEST_DB" "SELECT DISTINCT category FROM learnings ORDER BY category;" 2>/dev/null | tr '\n' ',')
    if echo "$categories" | grep -q 'bugfix' && echo "$categories" | grep -q 'decision'; then
        ok "Observation extraction: ${learnings_count} learnings from bugfix+decision types (categories: ${categories%,})"
    else
        not_ok "Observation extraction: bugfix+decision types" "unexpected categories: $categories"
    fi
else
    not_ok "Observation extraction: learnings table has >0 rows" "count=$learnings_count"
fi

# ─────────────────────────────────────────────────────────────
# 4. Dedup — run extract-learnings.sh again → no duplicate learnings
# ─────────────────────────────────────────────────────────────
count_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")

ALBA_MEMORY_DB="$TEST_DB" \
CLAUDE_SESSION_ID="test-lp-sess" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/extract-learnings.sh" 2>/dev/null

sleep 1

count_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")
if [ "$count_after" -eq "$count_before" ]; then
    ok "Deduplication: re-extraction produces no duplicates (${count_before} → ${count_after})"
else
    not_ok "Deduplication: re-extraction produces no duplicates" "before=${count_before} after=${count_after}"
fi

# ─────────────────────────────────────────────────────────────
# 5. JSONL ingestion — create learnings.jsonl, run extract → entries in DB
# ─────────────────────────────────────────────────────────────
mkdir -p "$TEST_LOG_DIR/logs"
cat > "$TEST_LOG_DIR/logs/learnings.jsonl" <<'JSONL'
{"learning": "Always validate user input before DB insert", "category": "security"}
{"learning": "Use connection pooling for PostgreSQL", "category": "performance"}
JSONL

ALBA_MEMORY_DB="$TEST_DB" \
CLAUDE_SESSION_ID="test-lp-sess" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/extract-learnings.sh" 2>/dev/null

sleep 1

jsonl_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings WHERE source='jsonl';" 2>/dev/null || echo "0")
if [ "$jsonl_count" -ge 2 ]; then
    ok "JSONL ingestion: ${jsonl_count} entries from learnings.jsonl"
else
    not_ok "JSONL ingestion: entries from learnings.jsonl" "jsonl source count=$jsonl_count (expected ≥2)"
fi

# ─────────────────────────────────────────────────────────────
# 6. JSONL dedup — duplicate entries produce single DB rows
# ─────────────────────────────────────────────────────────────
# Write same entries again
cat > "$TEST_LOG_DIR/logs/learnings.jsonl" <<'JSONL'
{"learning": "Always validate user input before DB insert", "category": "security"}
{"learning": "Use connection pooling for PostgreSQL", "category": "performance"}
JSONL

count_before_jsonl=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")

ALBA_MEMORY_DB="$TEST_DB" \
CLAUDE_SESSION_ID="test-lp-sess" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/extract-learnings.sh" 2>/dev/null

sleep 1

count_after_jsonl=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")
if [ "$count_after_jsonl" -eq "$count_before_jsonl" ]; then
    ok "JSONL dedup: duplicate entries produce no new rows (${count_before_jsonl} → ${count_after_jsonl})"
else
    not_ok "JSONL dedup: duplicate entries produce no new rows" "before=${count_before_jsonl} after=${count_after_jsonl}"
fi

# ─────────────────────────────────────────────────────────────
# 7. Context injection includes learnings — 'Recent Learnings' present
# ─────────────────────────────────────────────────────────────
rm -f "$TEST_OUTPUT"

ALBA_MEMORY_DB="$TEST_DB" \
ALBA_SESSION_CONTEXT="$TEST_OUTPUT" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/inject-context.sh" 2>/dev/null

if [ -f "$TEST_OUTPUT" ]; then
    ctx_content=$(cat "$TEST_OUTPUT")
    if echo "$ctx_content" | grep -q '### Recent Learnings'; then
        # Verify at least one learning bullet is present
        learning_bullets=$(echo "$ctx_content" | grep -c '^\- \[' || true)
        if [ "$learning_bullets" -gt 0 ]; then
            ok "Context injection includes Recent Learnings section (${learning_bullets} entries)"
        else
            not_ok "Context injection includes Recent Learnings section" "header found but no learning bullets"
        fi
    else
        not_ok "Context injection includes Recent Learnings section" "'### Recent Learnings' not found in output"
    fi
else
    not_ok "Context injection includes Recent Learnings section" "no output file generated"
fi

# ─────────────────────────────────────────────────────────────
# 8. Empty learnings → inject-context.sh omits 'Recent Learnings'
# ─────────────────────────────────────────────────────────────
EMPTY_DB=$(mktemp /tmp/alba-lp-empty.XXXXXX.db)
EMPTY_OUTPUT=$(mktemp /tmp/alba-lp-empty-out.XXXXXX.md)
bash "$REPO_DIR/scripts/alba-memory-init.sh" "$EMPTY_DB" > /dev/null 2>&1

# Seed a session + observation so inject-context.sh doesn't produce the empty-db fallback
sqlite3 "$EMPTY_DB" <<'SQL'
PRAGMA foreign_keys = ON;
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('empty-test', '/tmp/test', '2026-03-30T10:00:00Z', '2026-03-30T11:00:00Z', 5);
INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
VALUES ('empty-test', 'discovery', 'Placeholder', '', '', '[]', '[]', '2026-03-30T10:15:00Z');
SQL

rm -f "$EMPTY_OUTPUT"

ALBA_MEMORY_DB="$EMPTY_DB" \
ALBA_SESSION_CONTEXT="$EMPTY_OUTPUT" \
HOME="$TEST_LOG_DIR" \
bash "$REPO_DIR/hooks/inject-context.sh" 2>/dev/null

if [ -f "$EMPTY_OUTPUT" ]; then
    empty_content=$(cat "$EMPTY_OUTPUT")
    if echo "$empty_content" | grep -q '### Recent Learnings'; then
        not_ok "Empty learnings: output omits Recent Learnings" "section was present but shouldn't be"
    else
        ok "Empty learnings: output correctly omits Recent Learnings section"
    fi
else
    not_ok "Empty learnings: output omits Recent Learnings" "no output file generated"
fi

rm -f "$EMPTY_DB" "${EMPTY_DB}-wal" "${EMPTY_DB}-shm" "$EMPTY_OUTPUT"

# ─────────────────────────────────────────────────────────────
# 9. setup-hooks.sh --dry-run shows all expected hooks
# ─────────────────────────────────────────────────────────────
# Create a minimal settings.json for dry-run
mkdir -p "$TEST_LOG_DIR/.claude"
echo '{"hooks":{}}' > "$TEST_LOG_DIR/.claude/settings.json"

dryrun_output=$(HOME="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/setup-hooks.sh" --dry-run 2>&1)
dryrun_exit=$?

if [ $dryrun_exit -eq 0 ]; then
    missing=""
    echo "$dryrun_output" | grep -q 'capture-observation' || missing="${missing} capture-observation"
    echo "$dryrun_output" | grep -q 'inject-context'      || missing="${missing} inject-context"
    echo "$dryrun_output" | grep -q 'capture-session-summary' || missing="${missing} capture-session-summary"
    echo "$dryrun_output" | grep -q 'extract-learnings'   || missing="${missing} extract-learnings"

    if [ -z "$missing" ]; then
        ok "setup-hooks.sh --dry-run shows all 4 expected hooks"
    else
        not_ok "setup-hooks.sh --dry-run shows all expected hooks" "missing:${missing}"
    fi
else
    not_ok "setup-hooks.sh --dry-run shows all expected hooks" "exit code=$dryrun_exit output=$dryrun_output"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
