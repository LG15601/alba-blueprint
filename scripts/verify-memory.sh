#!/usr/bin/env bash
# verify-memory.sh — TAP test suite for the Alba memory system
# Tests: schema creation, FTS5 search, session summaries, migration tracking,
#        WAL mode, trigger sync (insert + delete), temp DB isolation.
#
# Usage: bash scripts/verify-memory.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DB=$(mktemp /tmp/alba-memory-test.XXXXXX.db)
PLAN=11
PASS=0
FAIL=0
TEST_NUM=0

cleanup() { rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"; }
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

# ── Initialize test database ────────────────────────────────
echo "1..$PLAN"
echo "# Initializing test database at $TEST_DB"

init_output=$(bash "$SCRIPT_DIR/alba-memory-init.sh" "$TEST_DB" 2>&1)
if [ $? -ne 0 ]; then
    echo "Bail out! alba-memory-init.sh failed: $init_output"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# 1. Core tables exist
# ─────────────────────────────────────────────────────────────
tables=$(sqlite3 "$TEST_DB" ".tables")
missing=""
for t in sessions observations session_summaries observations_fts meta; do
    echo "$tables" | grep -qw "$t" || missing="$missing $t"
done

if [ -z "$missing" ]; then
    ok "Core tables exist (sessions, observations, session_summaries, observations_fts, meta)"
else
    not_ok "Core tables exist" "missing:$missing"
fi

# ─────────────────────────────────────────────────────────────
# 2. FTS5 virtual table is queryable
# ─────────────────────────────────────────────────────────────
fts_check=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM observations_fts WHERE observations_fts MATCH 'test';" 2>&1)
if [ $? -eq 0 ]; then
    ok "FTS5 table is queryable"
else
    not_ok "FTS5 table is queryable" "$fts_check"
fi

# ─────────────────────────────────────────────────────────────
# 3. WAL mode is enabled
# ─────────────────────────────────────────────────────────────
journal_mode=$(sqlite3 "$TEST_DB" "PRAGMA journal_mode;")
if [ "$journal_mode" = "wal" ]; then
    ok "WAL mode enabled"
else
    not_ok "WAL mode enabled" "got: $journal_mode"
fi

# ─────────────────────────────────────────────────────────────
# 4. Migration version tracking works
# ─────────────────────────────────────────────────────────────
schema_version=$(sqlite3 "$TEST_DB" "SELECT value FROM meta WHERE key = 'schema_version';")
if [ "$schema_version" = "7" ]; then
    ok "Migration version is 7 after all migrations"
else
    not_ok "Migration version is 7 after all migrations" "got: $schema_version"
fi

# ─────────────────────────────────────────────────────────────
# 5. Re-running init is idempotent (no errors, no re-apply)
# ─────────────────────────────────────────────────────────────
reinit_output=$(bash "$SCRIPT_DIR/alba-memory-init.sh" "$TEST_DB" 2>&1)
if echo "$reinit_output" | grep -q "up to date"; then
    ok "Re-init is idempotent (skips applied migrations)"
else
    not_ok "Re-init is idempotent" "$reinit_output"
fi

# ─────────────────────────────────────────────────────────────
# 6. Observation insert succeeds with FK constraint
# ─────────────────────────────────────────────────────────────
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;
INSERT OR IGNORE INTO sessions (id, project, started_at) VALUES ('test-session-1', '/tmp/test-project', '2025-01-01T00:00:00Z');
INSERT INTO observations (session_id, type, title, subtitle, narrative, facts, concepts, created_at)
VALUES ('test-session-1', 'discovery', 'Found SQLite FTS5 quirk', 'content-sync triggers', 'The FTS5 content-sync triggers need before-delete pattern', '["fts5","triggers"]', '["search","indexing"]', '2025-01-01T00:01:00Z');
SQL
if [ $? -eq 0 ]; then
    ok "Observation insert succeeds with FK constraint"
else
    not_ok "Observation insert succeeds with FK constraint"
fi

# ─────────────────────────────────────────────────────────────
# 7. FTS5 trigger sync — inserted observation appears in FTS
# ─────────────────────────────────────────────────────────────
fts_hits=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM observations_fts WHERE observations_fts MATCH 'FTS5 quirk';")
if [ "$fts_hits" -ge 1 ]; then
    ok "Trigger sync: inserted observation found via FTS5 search"
else
    not_ok "Trigger sync: inserted observation found via FTS5 search" "hits: $fts_hits"
fi

# ─────────────────────────────────────────────────────────────
# 8. FTS5 ranked search returns matching row
# ─────────────────────────────────────────────────────────────
search_title=$(sqlite3 "$TEST_DB" "SELECT title FROM observations WHERE id IN (SELECT rowid FROM observations_fts WHERE observations_fts MATCH 'triggers') LIMIT 1;")
if [ "$search_title" = "Found SQLite FTS5 quirk" ]; then
    ok "FTS5 search returns correct observation by content match"
else
    not_ok "FTS5 search returns correct observation by content match" "got: $search_title"
fi

# ─────────────────────────────────────────────────────────────
# 9. Session summary insert + query
# ─────────────────────────────────────────────────────────────
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;
INSERT INTO session_summaries (session_id, request, investigated, learned, completed, next_steps)
VALUES ('test-session-1', 'Build memory system', 'SQLite FTS5 capabilities', 'Triggers keep FTS in sync', 'Schema and init script', 'Add MCP search tool');
SQL
summary_learned=$(sqlite3 "$TEST_DB" "SELECT learned FROM session_summaries WHERE session_id = 'test-session-1';")
if [ "$summary_learned" = "Triggers keep FTS in sync" ]; then
    ok "Session summary insert + query returns correct data"
else
    not_ok "Session summary insert + query returns correct data" "got: $summary_learned"
fi

# ─────────────────────────────────────────────────────────────
# 10. Delete observation → removed from FTS5
# ─────────────────────────────────────────────────────────────
obs_id=$(sqlite3 "$TEST_DB" "SELECT id FROM observations WHERE title = 'Found SQLite FTS5 quirk';")
sqlite3 "$TEST_DB" "PRAGMA foreign_keys = ON; DELETE FROM observations WHERE id = $obs_id;"
fts_after_delete=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM observations_fts WHERE observations_fts MATCH 'FTS5 quirk';")
if [ "$fts_after_delete" -eq 0 ]; then
    ok "Delete trigger: observation removed from FTS5 index"
else
    not_ok "Delete trigger: observation removed from FTS5 index" "still found $fts_after_delete hit(s)"
fi

# ─────────────────────────────────────────────────────────────
# 11. Update observation → FTS5 reflects new content
# ─────────────────────────────────────────────────────────────
sqlite3 "$TEST_DB" <<'SQL'
PRAGMA foreign_keys = ON;
INSERT INTO observations (session_id, type, title, narrative, created_at)
VALUES ('test-session-1', 'bugfix', 'Original title', 'Original narrative', '2025-01-01T00:02:00Z');
SQL
upd_id=$(sqlite3 "$TEST_DB" "SELECT id FROM observations WHERE title = 'Original title';")
sqlite3 "$TEST_DB" "UPDATE observations SET title = 'Updated flamingo title', narrative = 'Updated narrative about flamingos' WHERE id = $upd_id;"

old_hits=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM observations_fts WHERE observations_fts MATCH 'Original title';")
new_hits=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM observations_fts WHERE observations_fts MATCH 'flamingo';")

if [ "$old_hits" -eq 0 ] && [ "$new_hits" -ge 1 ]; then
    ok "Update trigger: FTS5 reflects updated content (old removed, new indexed)"
else
    not_ok "Update trigger: FTS5 reflects updated content" "old_hits=$old_hits new_hits=$new_hits"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
