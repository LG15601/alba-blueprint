#!/usr/bin/env bash
# test-goals.sh — TAP test suite for goal hierarchy and heartbeat integration
#
# Exercises:
#   - Migration 007 schema creation
#   - Goal CRUD: add mission/goal/task with hierarchy enforcement
#   - Tree display, done, block, list with filters
#   - Heartbeat handler_goals pass/triggered states
#
# Fully isolated: uses temp DBs, temp config files. No side effects.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Temp isolation ───────────────────────────────────────────
TEST_DIR=$(mktemp -d /tmp/alba-goals-test.XXXXXX)
TEST_MEMORY_DB="$TEST_DIR/memory.db"
TEST_LOGS_DB="$TEST_DIR/logs.db"
TEST_HEARTBEAT_FILE="$TEST_DIR/HEARTBEAT.md"

PLAN=11
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -rf "$TEST_DIR"
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

# ── Helper: init a fresh test DB with all migrations ─────────
init_test_db() {
    local db="$1"
    rm -f "$db" "${db}-wal" "${db}-shm"
    bash "$REPO_DIR/scripts/alba-memory-init.sh" "$db" >/dev/null 2>&1
}

# ── Helper: init logs DB with minimal schema ─────────────────
init_logs_db() {
    local db="$1"
    rm -f "$db" "${db}-wal" "${db}-shm"
    /usr/bin/sqlite3 "$db" <<'SQL' >/dev/null
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT,
    level TEXT,
    source TEXT,
    message TEXT,
    metadata TEXT
);
SQL
}

# ─────────────────────────────────────────────────────────────
# 1. Migration 007 applies cleanly, goals table has correct columns
# ─────────────────────────────────────────────────────────────
init_test_db "$TEST_MEMORY_DB"

table_exists=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='goals';" 2>/dev/null)
cols=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "PRAGMA table_info(goals);" 2>/dev/null | awk -F'|' '{print $2}' | sort | tr '\n' ',')

if [ "$table_exists" = "1" ] && echo "$cols" | grep -q "parent_id" && echo "$cols" | grep -q "target_date" && echo "$cols" | grep -q "status"; then
    ok "Migration 007 creates goals table with expected columns"
else
    not_ok "Migration 007 creates goals table with expected columns" "table=$table_exists cols=$cols"
fi

# ─────────────────────────────────────────────────────────────
# 2. Add mission (no parent) succeeds
# ─────────────────────────────────────────────────────────────
output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type mission --title "Test Mission" 2>/dev/null)

if echo "$output" | grep -q "Created mission #1"; then
    ok "Add mission (no parent) succeeds"
else
    not_ok "Add mission (no parent) succeeds" "output: $output"
fi

# ─────────────────────────────────────────────────────────────
# 3. Add goal with parent=mission succeeds
# ─────────────────────────────────────────────────────────────
output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type goal --parent 1 --title "Test Goal" --target 2026-06-30 2>/dev/null)

if echo "$output" | grep -q "Created goal #2"; then
    ok "Add goal with parent=mission succeeds"
else
    not_ok "Add goal with parent=mission succeeds" "output: $output"
fi

# ─────────────────────────────────────────────────────────────
# 4. Add task with parent=goal succeeds
# ─────────────────────────────────────────────────────────────
output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type task --parent 2 --title "Test Task" 2>/dev/null)

if echo "$output" | grep -q "Created task #3"; then
    ok "Add task with parent=goal succeeds"
else
    not_ok "Add task with parent=goal succeeds" "output: $output"
fi

# ─────────────────────────────────────────────────────────────
# 5. Add goal with no parent fails (type hierarchy validation)
# ─────────────────────────────────────────────────────────────
error_output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type goal --title "Orphan Goal" 2>&1) && result=0 || result=$?

if [ "$result" -ne 0 ] && echo "$error_output" | grep -q "must have a parent"; then
    ok "Add goal with no parent fails with hierarchy validation error"
else
    not_ok "Add goal with no parent fails with hierarchy validation error" "exit=$result output: $error_output"
fi

# ─────────────────────────────────────────────────────────────
# 6. Tree display shows correct indentation and all entries
# ─────────────────────────────────────────────────────────────
tree_output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" tree 2>/dev/null)
line_count=$(echo "$tree_output" | grep -c '\[' || true)
has_mission=$(echo "$tree_output" | grep -c '\[mission\]' || true)
has_goal=$(echo "$tree_output" | grep -c '\[goal\]' || true)
has_task=$(echo "$tree_output" | grep -c '\[task\]' || true)
# Goal and task should be indented (leading spaces)
goal_indented=$(echo "$tree_output" | grep '\[goal\]' | grep -c '^ ' || true)
task_indented=$(echo "$tree_output" | grep '\[task\]' | grep -c '^ ' || true)

if [ "$line_count" -ge 3 ] && [ "$has_mission" -ge 1 ] && [ "$has_goal" -ge 1 ] && [ "$has_task" -ge 1 ] && \
   [ "$goal_indented" -ge 1 ] && [ "$task_indented" -ge 1 ]; then
    ok "Tree display shows correct indentation and all entries (lines=$line_count)"
else
    not_ok "Tree display shows correct indentation and all entries" "lines=$line_count mission=$has_mission goal=$has_goal task=$has_task goal_indent=$goal_indented task_indent=$task_indented"
    echo "  # tree output: $tree_output"
fi

# ─────────────────────────────────────────────────────────────
# 7. Done command updates status and sets completed_at
# ─────────────────────────────────────────────────────────────
ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" done 3 >/dev/null 2>&1

status=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" "SELECT status FROM goals WHERE id = 3;" 2>/dev/null)
completed=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" "SELECT completed_at FROM goals WHERE id = 3;" 2>/dev/null)

if [ "$status" = "done" ] && [ -n "$completed" ]; then
    ok "Done command updates status to 'done' and sets completed_at"
else
    not_ok "Done command updates status to 'done' and sets completed_at" "status=$status completed=$completed"
fi

# ─────────────────────────────────────────────────────────────
# 8. Block command updates status to blocked
# ─────────────────────────────────────────────────────────────
ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" block 2 >/dev/null 2>&1

status=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" "SELECT status FROM goals WHERE id = 2;" 2>/dev/null)

if [ "$status" = "blocked" ]; then
    ok "Block command updates status to 'blocked'"
else
    not_ok "Block command updates status to 'blocked'" "status=$status"
fi

# ─────────────────────────────────────────────────────────────
# 9. List with --status filter returns correct subset
# ─────────────────────────────────────────────────────────────
list_output=$(ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    list --status blocked 2>/dev/null)

# Should show goal #2 (blocked) and NOT #1 (active) or #3 (done)
has_blocked=$(echo "$list_output" | grep -c "blocked" || true)
has_active=$(echo "$list_output" | grep -c "active" || true)

if [ "$has_blocked" -ge 1 ] && [ "$has_active" -eq 0 ]; then
    ok "List with --status filter returns correct subset (blocked only)"
else
    not_ok "List with --status filter returns correct subset" "blocked=$has_blocked active=$has_active"
    echo "  # list output: $list_output"
fi

# ─────────────────────────────────────────────────────────────
# 10. Heartbeat handler_goals returns 0 when no blocked/overdue goals
# ─────────────────────────────────────────────────────────────
# Fresh DB with only an active mission (no blocked, no overdue)
init_test_db "$TEST_MEMORY_DB"
init_logs_db "$TEST_LOGS_DB"

ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type mission --title "Clean Mission" >/dev/null 2>&1

cat > "$TEST_HEARTBEAT_FILE" <<'EOF'
# Test Heartbeat
- [ ] [goals] Check for blocked/overdue goals
EOF

hb_output=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    HEARTBEAT_FILE="$TEST_HEARTBEAT_FILE" \
    bash "$REPO_DIR/scripts/alba-heartbeat-proactive.sh" 2>/dev/null)
hb_exit=$?

if [ "$hb_exit" -eq 0 ] && echo "$hb_output" | grep -q "1/1 passed, 0 triggered"; then
    ok "Heartbeat handler_goals returns 0 when no blocked/overdue goals"
else
    not_ok "Heartbeat handler_goals returns 0 when no blocked/overdue goals" "exit=$hb_exit output=$hb_output"
fi

# ─────────────────────────────────────────────────────────────
# 11. Heartbeat handler_goals returns 1 when blocked goal exists
# ─────────────────────────────────────────────────────────────
# Add a goal under the mission, then block it
ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    add --type goal --parent 1 --title "Blocked Goal" >/dev/null 2>&1
ALBA_MEMORY_DB="$TEST_MEMORY_DB" bash "$REPO_DIR/scripts/alba-goals.sh" \
    block 2 >/dev/null 2>&1

hb_output2=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    HEARTBEAT_FILE="$TEST_HEARTBEAT_FILE" \
    bash "$REPO_DIR/scripts/alba-heartbeat-proactive.sh" 2>/dev/null)
hb_exit2=$?

if [ "$hb_exit2" -eq 0 ] && echo "$hb_output2" | grep -q "0/1 passed, 1 triggered"; then
    ok "Heartbeat handler_goals returns 1 when blocked goal exists"
else
    not_ok "Heartbeat handler_goals returns 1 when blocked goal exists" "exit=$hb_exit2 output=$hb_output2"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
