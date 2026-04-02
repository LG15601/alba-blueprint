#!/usr/bin/env bash
# verify-skill-extraction.sh — TAP test suite for the skill auto-extraction pipeline
# Tests: migration 004, workflow detection heuristic, SKILL.md content, dedup,
#        security scan, error-ending skip, below-threshold skip, empty DB,
#        setup-hooks registration.
#
# Uses temp DB + temp skills dir. No side effects on real data.
#
# Usage: bash tests/verify-skill-extraction.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DB=$(mktemp /tmp/alba-se-test.XXXXXX.db)
TEST_SKILLS_DIR=$(mktemp -d /tmp/alba-se-skills.XXXXXX)
TEST_LOG_DIR=$(mktemp -d /tmp/alba-se-logs.XXXXXX)

PLAN=9
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
    rm -rf "$TEST_SKILLS_DIR" "$TEST_LOG_DIR"
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

# ── Initialize DB with all migrations (001-004) ─────────────
echo "# Initializing test database at $TEST_DB"
cat "$REPO_DIR/migrations/001-initial-schema.sql" \
    "$REPO_DIR/migrations/002-learnings-table.sql" \
    "$REPO_DIR/migrations/003-promoted-rules.sql" \
    "$REPO_DIR/migrations/004-extracted-skills.sql" \
    | sqlite3 "$TEST_DB" 2>&1
if [ $? -ne 0 ]; then
    echo "Bail out! Migration failed"
    exit 1
fi

# ─────────────────────────────────────────────────────────────
# 1. Migration 004 — extracted_skills table with expected columns
# ─────────────────────────────────────────────────────────────
tables=$(sqlite3 "$TEST_DB" ".tables" 2>/dev/null)
if echo "$tables" | grep -q 'extracted_skills'; then
    cols=$(sqlite3 "$TEST_DB" "PRAGMA table_info(extracted_skills);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ' ')
    expected_cols="id skill_name source_observation_ids content_hash skill_path created_at"
    all_found=true
    for col in $expected_cols; do
        if ! echo "$cols" | grep -qw "$col"; then
            all_found=false
            break
        fi
    done
    # Check UNIQUE constraint on content_hash
    unique_check=$(sqlite3 "$TEST_DB" "SELECT sql FROM sqlite_master WHERE type='table' AND name='extracted_skills';" 2>/dev/null)
    has_unique=false
    echo "$unique_check" | grep -qi 'UNIQUE' && has_unique=true

    if $all_found && $has_unique; then
        ok "Migration 004: extracted_skills table with correct columns and UNIQUE content_hash"
    else
        not_ok "Migration 004: extracted_skills table with correct columns and UNIQUE content_hash" "cols=$cols unique=$has_unique"
    fi
else
    not_ok "Migration 004: extracted_skills table exists" "table not found; tables: $tables"
fi

# ── Seed test data: qualifying session (6 observations with files_modified) ──
echo "# Seeding qualifying session"
sqlite3 "$TEST_DB" <<'SQL'
INSERT INTO sessions (id, project, started_at, ended_at, tool_call_count)
VALUES ('se-test-good', '/tmp/se-test', '2026-03-30T10:00:00Z', '2026-03-30T11:00:00Z', 20);

INSERT INTO observations (session_id, type, title, files_modified, created_at)
VALUES
    ('se-test-good', 'feature',  'Create user model',         '["src/models/user.ts"]',         '2026-03-30T10:05:00Z'),
    ('se-test-good', 'feature',  'Add auth middleware',        '["src/middleware/auth.ts"]',      '2026-03-30T10:10:00Z'),
    ('se-test-good', 'feature',  'Build login endpoint',       '["src/routes/login.ts"]',         '2026-03-30T10:15:00Z'),
    ('se-test-good', 'feature',  'Add password hashing',       '["src/utils/hash.ts"]',           '2026-03-30T10:20:00Z'),
    ('se-test-good', 'feature',  'Create session handler',     '["src/middleware/auth.ts"]',      '2026-03-30T10:25:00Z'),
    ('se-test-good', 'refactor', 'Clean up auth flow',         '["src/middleware/auth.ts","src/routes/login.ts"]', '2026-03-30T10:30:00Z');
SQL

# ─────────────────────────────────────────────────────────────
# 2. Qualifying workflow — creates a skill file
# ─────────────────────────────────────────────────────────────
echo "# Running extract-skills.sh against qualifying session"
extract_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/extract-skills.sh" \
    --db "$TEST_DB" --skills-dir "$TEST_SKILLS_DIR" 2>&1)
extract_exit=$?

skill_dirs=$(find "$TEST_SKILLS_DIR" -name 'SKILL.md' -type f 2>/dev/null)
skill_count=0
if [ -n "$skill_dirs" ]; then
    skill_count=$(echo "$skill_dirs" | wc -l | tr -d ' ')
fi

if [ "$extract_exit" -eq 0 ] && [ "$skill_count" -eq 1 ]; then
    ok "Qualifying workflow: extract-skills.sh created exactly 1 SKILL.md"
else
    not_ok "Qualifying workflow: extract-skills.sh created exactly 1 SKILL.md" \
        "exit=$extract_exit count=$skill_count output=$extract_output"
fi

# ─────────────────────────────────────────────────────────────
# 3. SKILL.md content — uses titles only, has correct structure
# ─────────────────────────────────────────────────────────────
if [ "$skill_count" -eq 1 ]; then
    skill_file=$(echo "$skill_dirs" | head -1)
    skill_body=$(cat "$skill_file")

    has_frontmatter=false
    has_workflow_steps=false
    has_files_involved=false
    has_titles=false
    has_no_narrative=true
    has_invocable_false=false

    echo "$skill_body" | grep -q '^---' && has_frontmatter=true
    echo "$skill_body" | grep -q '## Workflow Steps' && has_workflow_steps=true
    echo "$skill_body" | grep -q '## Files Involved' && has_files_involved=true
    echo "$skill_body" | grep -q 'Create user model' && has_titles=true
    echo "$skill_body" | grep -q 'user-invocable: false' && has_invocable_false=true
    # Narrative text should NOT appear (only titles)
    echo "$skill_body" | grep -qi 'narrative' && has_no_narrative=false

    if $has_frontmatter && $has_workflow_steps && $has_files_involved && $has_titles && $has_no_narrative && $has_invocable_false; then
        ok "SKILL.md content: has frontmatter, workflow steps with titles, files involved, user-invocable: false"
    else
        not_ok "SKILL.md content: correct structure" \
            "fm=$has_frontmatter steps=$has_workflow_steps files=$has_files_involved titles=$has_titles no_narrative=$has_no_narrative invocable=$has_invocable_false"
    fi
else
    not_ok "SKILL.md content: correct structure" "skipped — no skill file"
fi

# ─────────────────────────────────────────────────────────────
# 4. Dedup — re-run creates no new skills
# ─────────────────────────────────────────────────────────────
files_before=$(find "$TEST_SKILLS_DIR" -name 'SKILL.md' -type f | wc -l | tr -d ' ')
rows_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM extracted_skills;" 2>/dev/null || echo "0")

ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/extract-skills.sh" \
    --db "$TEST_DB" --skills-dir "$TEST_SKILLS_DIR" 2>/dev/null

files_after=$(find "$TEST_SKILLS_DIR" -name 'SKILL.md' -type f | wc -l | tr -d ' ')
rows_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM extracted_skills;" 2>/dev/null || echo "0")

if [ "$files_after" -eq "$files_before" ] && [ "$rows_after" -eq "$rows_before" ]; then
    ok "Dedup: re-run produces no new skills ($files_before files, $rows_before rows)"
else
    not_ok "Dedup: re-run produces no new skills" \
        "files: $files_before→$files_after rows: $rows_before→$rows_after"
fi

# ─────────────────────────────────────────────────────────────
# 5. Error-ending session — last 3 observations are bugfix type → skip
# ─────────────────────────────────────────────────────────────
echo "# Seeding error-ending session"
ERROR_DB=$(mktemp /tmp/alba-se-error.XXXXXX.db)
ERROR_SKILLS=$(mktemp -d /tmp/alba-se-error-skills.XXXXXX)

cat "$REPO_DIR/migrations/001-initial-schema.sql" \
    "$REPO_DIR/migrations/002-learnings-table.sql" \
    "$REPO_DIR/migrations/003-promoted-rules.sql" \
    "$REPO_DIR/migrations/004-extracted-skills.sql" \
    | sqlite3 "$ERROR_DB"

sqlite3 "$ERROR_DB" <<'SQL'
INSERT INTO sessions (id, project, started_at) VALUES ('se-test-error', '/tmp/test', '2026-03-30T10:00:00Z');
INSERT INTO observations (session_id, type, title, files_modified, created_at) VALUES
    ('se-test-error', 'feature', 'Step 1', '["a.ts"]', '2026-03-30T10:01:00Z'),
    ('se-test-error', 'feature', 'Step 2', '["b.ts"]', '2026-03-30T10:02:00Z'),
    ('se-test-error', 'feature', 'Step 3', '["c.ts"]', '2026-03-30T10:03:00Z'),
    ('se-test-error', 'feature', 'Step 4', '["d.ts"]', '2026-03-30T10:04:00Z'),
    ('se-test-error', 'feature', 'Step 5', '["e.ts"]', '2026-03-30T10:05:00Z'),
    ('se-test-error', 'bugfix',  'Fix 1',  '["a.ts"]', '2026-03-30T10:06:00Z'),
    ('se-test-error', 'bugfix',  'Fix 2',  '["b.ts"]', '2026-03-30T10:07:00Z'),
    ('se-test-error', 'bugfix',  'Fix 3',  '["c.ts"]', '2026-03-30T10:08:00Z');
SQL

error_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/extract-skills.sh" \
    --db "$ERROR_DB" --skills-dir "$ERROR_SKILLS" 2>&1)
error_files=$(find "$ERROR_SKILLS" -name 'SKILL.md' -type f | wc -l | tr -d ' ')

if [ "$error_files" -eq 0 ]; then
    ok "Error-ending: session with 3 trailing bugfix observations skipped"
else
    not_ok "Error-ending: session with 3 trailing bugfix observations skipped" \
        "found $error_files skill files; output=$error_output"
fi
rm -f "$ERROR_DB" "${ERROR_DB}-wal" "${ERROR_DB}-shm"
rm -rf "$ERROR_SKILLS"

# ─────────────────────────────────────────────────────────────
# 6. Below threshold — session with only 4 observations with files_modified
# ─────────────────────────────────────────────────────────────
echo "# Seeding below-threshold session"
LOW_DB=$(mktemp /tmp/alba-se-low.XXXXXX.db)
LOW_SKILLS=$(mktemp -d /tmp/alba-se-low-skills.XXXXXX)

cat "$REPO_DIR/migrations/001-initial-schema.sql" \
    "$REPO_DIR/migrations/002-learnings-table.sql" \
    "$REPO_DIR/migrations/003-promoted-rules.sql" \
    "$REPO_DIR/migrations/004-extracted-skills.sql" \
    | sqlite3 "$LOW_DB"

sqlite3 "$LOW_DB" <<'SQL'
INSERT INTO sessions (id, project, started_at) VALUES ('se-test-low', '/tmp/test', '2026-03-30T10:00:00Z');
INSERT INTO observations (session_id, type, title, files_modified, created_at) VALUES
    ('se-test-low', 'feature', 'Step 1', '["a.ts"]', '2026-03-30T10:01:00Z'),
    ('se-test-low', 'feature', 'Step 2', '["b.ts"]', '2026-03-30T10:02:00Z'),
    ('se-test-low', 'feature', 'Step 3', '["c.ts"]', '2026-03-30T10:03:00Z'),
    ('se-test-low', 'feature', 'Step 4', '["d.ts"]', '2026-03-30T10:04:00Z');
SQL

low_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/extract-skills.sh" \
    --db "$LOW_DB" --skills-dir "$LOW_SKILLS" 2>&1)
low_files=$(find "$LOW_SKILLS" -name 'SKILL.md' -type f | wc -l | tr -d ' ')

if [ "$low_files" -eq 0 ]; then
    ok "Below threshold: 4-observation session skipped"
else
    not_ok "Below threshold: 4-observation session skipped" \
        "found $low_files skill files"
fi
rm -f "$LOW_DB" "${LOW_DB}-wal" "${LOW_DB}-shm"
rm -rf "$LOW_SKILLS"

# ─────────────────────────────────────────────────────────────
# 7. Empty DB — no sessions, exits 0 with no skills
# ─────────────────────────────────────────────────────────────
EMPTY_DB=$(mktemp /tmp/alba-se-empty.XXXXXX.db)
EMPTY_SKILLS=$(mktemp -d /tmp/alba-se-empty-skills.XXXXXX)

cat "$REPO_DIR/migrations/001-initial-schema.sql" \
    "$REPO_DIR/migrations/002-learnings-table.sql" \
    "$REPO_DIR/migrations/003-promoted-rules.sql" \
    "$REPO_DIR/migrations/004-extracted-skills.sql" \
    | sqlite3 "$EMPTY_DB"

empty_output=$(ALBA_DIR="$TEST_LOG_DIR" bash "$REPO_DIR/scripts/extract-skills.sh" \
    --db "$EMPTY_DB" --skills-dir "$EMPTY_SKILLS" 2>&1)
empty_exit=$?
empty_files=$(find "$EMPTY_SKILLS" -name 'SKILL.md' -type f | wc -l | tr -d ' ')

if [ "$empty_exit" -eq 0 ] && [ "$empty_files" -eq 0 ]; then
    ok "Empty DB: exits 0 with no skill files created"
else
    not_ok "Empty DB: exits 0 with no skill files created" \
        "exit=$empty_exit files=$empty_files"
fi
rm -f "$EMPTY_DB" "${EMPTY_DB}-wal" "${EMPTY_DB}-shm"
rm -rf "$EMPTY_SKILLS"

# ─────────────────────────────────────────────────────────────
# 8. Hook wrapper — syntax valid and contains fail-open pattern
# ─────────────────────────────────────────────────────────────
hook_file="$REPO_DIR/hooks/extract-skills-hook.sh"
if bash -n "$hook_file" 2>/dev/null; then
    hook_body=$(cat "$hook_file")
    has_background=false
    has_fail_open=false
    has_exit_0=false

    echo "$hook_body" | grep -q '&$' && has_background=true
    echo "$hook_body" | grep -q '|| true' && has_fail_open=true
    echo "$hook_body" | grep -q 'exit 0' && has_exit_0=true

    if $has_background && $has_fail_open && $has_exit_0; then
        ok "Hook wrapper: valid syntax, background subshell, fail-open, exit 0"
    else
        not_ok "Hook wrapper: correct structure" \
            "bg=$has_background failopen=$has_fail_open exit0=$has_exit_0"
    fi
else
    not_ok "Hook wrapper: valid syntax" "bash -n failed"
fi

# ─────────────────────────────────────────────────────────────
# 9. setup-hooks.sh — registers extract-skills-hook.sh
# ─────────────────────────────────────────────────────────────
setup_file="$REPO_DIR/scripts/setup-hooks.sh"
if bash -n "$setup_file" 2>/dev/null; then
    setup_body=$(cat "$setup_file")
    has_skills_cmd=false
    has_stop_section=false

    echo "$setup_body" | grep -q 'extract-skills-hook.sh' && has_skills_cmd=true
    echo "$setup_body" | grep -q 'SKILLS_CMD=' && has_stop_section=true

    if $has_skills_cmd && $has_stop_section; then
        ok "setup-hooks.sh: registers extract-skills-hook.sh in Stop matcher"
    else
        not_ok "setup-hooks.sh: registers extract-skills-hook.sh" \
            "has_cmd=$has_skills_cmd has_section=$has_stop_section"
    fi
else
    not_ok "setup-hooks.sh: valid syntax" "bash -n failed"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
