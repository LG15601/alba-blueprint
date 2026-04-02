#!/usr/bin/env bash
# test-heartbeat-proactive.sh — TAP test suite for standing orders + heartbeat
#
# Exercises:
#   - Migration 006 schema creation
#   - Standing orders parser, time-window matching, dedup, --check mode
#   - Execution recording to SQLite
#   - HEARTBEAT.md check-ID parsing
#   - Heartbeat runner end-to-end
#   - Lock contention (mkdir-based)
#
# Fully isolated: uses temp DBs, temp config files, and temp dirs.
# No side effects on real state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Temp isolation ───────────────────────────────────────────
TEST_DIR=$(mktemp -d /tmp/alba-hb-test.XXXXXX)
TEST_MEMORY_DB="$TEST_DIR/memory.db"
TEST_LOGS_DB="$TEST_DIR/logs.db"
TEST_ORDERS_FILE="$TEST_DIR/standing-orders.md"
TEST_HEARTBEAT_FILE="$TEST_DIR/HEARTBEAT.md"
TEST_LOCK_DIR="/tmp/alba-standing-orders.lock"

PLAN=9
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -rf "$TEST_DIR"
    rmdir "$TEST_LOCK_DIR" 2>/dev/null || rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
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
# 1. Migration 006 applies cleanly and creates expected schema
# ─────────────────────────────────────────────────────────────
init_test_db "$TEST_MEMORY_DB"

table_exists=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='standing_order_executions';" 2>/dev/null)
cols=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "PRAGMA table_info(standing_order_executions);" 2>/dev/null | awk -F'|' '{print $2}' | sort | tr '\n' ',')

if [ "$table_exists" = "1" ] && echo "$cols" | grep -q "order_id" && echo "$cols" | grep -q "executed_at"; then
    ok "Migration 006 creates standing_order_executions with expected columns"
else
    not_ok "Migration 006 creates standing_order_executions with expected columns" "table=$table_exists cols=$cols"
fi

# ─────────────────────────────────────────────────────────────
# 2. Standing orders parser extracts HH:MM + description
# ─────────────────────────────────────────────────────────────
cat > "$TEST_ORDERS_FILE" <<'EOF'
# Standing Orders

Daily scheduled tasks.

- 07:00 — Morning briefing (check overnight alerts)
- 12:30 — Midday review (sync context)
- 18:00 — Evening wrap-up
EOF

# Source the parse_orders function by extracting it — but the script isn't designed to be sourced.
# Instead, test via the --check interface with a known-good time.
# For parser-only test, replicate the parse logic inline (TAP pattern from KNOWLEDGE.md).
parse_result=$(grep -E '^\s*-\s+[0-9]{2}:[0-9]{2}' "$TEST_ORDERS_FILE" | \
    perl -CSD -pe 's/^\s*-\s+(\d{2}:\d{2})\s*[\x{2014}\x{2013}\-]+\s*/$1|||/' 2>/dev/null)

line_count=$(echo "$parse_result" | grep -c '|||' || true)
has_0700=$(echo "$parse_result" | grep -c '07:00|||Morning briefing' || true)
has_1230=$(echo "$parse_result" | grep -c '12:30|||Midday review' || true)

if [ "$line_count" -eq 3 ] && [ "$has_0700" -ge 1 ] && [ "$has_1230" -ge 1 ]; then
    ok "Standing orders parser extracts HH:MM + description (3 orders found)"
else
    not_ok "Standing orders parser extracts HH:MM + description" "lines=$line_count 0700=$has_0700 1230=$has_1230"
fi

# ─────────────────────────────────────────────────────────────
# 3. Time-window matching: order at current time is detected as due
# ─────────────────────────────────────────────────────────────
# Write an orders file with the current HH:MM so it's guaranteed due.
current_hhmm=$(date +%H:%M)
cat > "$TEST_ORDERS_FILE" <<EOF
# Standing Orders
- $current_hhmm — Test order at current time
EOF

init_logs_db "$TEST_LOGS_DB"
init_test_db "$TEST_MEMORY_DB"

check_output=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" --check 2>/dev/null)

if echo "$check_output" | grep -q "^DUE:"; then
    ok "Time-window matching: order at current time is detected as due"
else
    not_ok "Time-window matching: order at current time is detected as due" "output: $check_output"
fi

# ─────────────────────────────────────────────────────────────
# 4. Time-window matching: already-executed order is skipped
# ─────────────────────────────────────────────────────────────
# First, execute the order so it gets recorded
rmdir "$TEST_LOCK_DIR" 2>/dev/null || rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true

exec_output=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" 2>/dev/null)

# Now --check should show SKIP
check_output2=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" --check 2>/dev/null)

if echo "$check_output2" | grep -q "^SKIP:"; then
    ok "Time-window matching: already-executed order is skipped"
else
    not_ok "Time-window matching: already-executed order is skipped" "output: $check_output2"
fi

# ─────────────────────────────────────────────────────────────
# 5. --check dry-run mode outputs due orders without recording
# ─────────────────────────────────────────────────────────────
# Use a fresh DB and a time that's current
init_test_db "$TEST_MEMORY_DB"

check_output3=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" --check 2>/dev/null)

# Verify DUE is shown and no execution was recorded
row_count=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "SELECT COUNT(*) FROM standing_order_executions;" 2>/dev/null)

if echo "$check_output3" | grep -q "^DUE:" && [ "${row_count:-0}" -eq 0 ]; then
    ok "--check dry-run outputs due orders without recording to DB"
else
    not_ok "--check dry-run outputs due orders without recording to DB" "DUE in output=$(echo "$check_output3" | grep -c '^DUE:' || true) rows=$row_count"
fi

# ─────────────────────────────────────────────────────────────
# 6. Execution recording writes correct fields to SQLite
# ─────────────────────────────────────────────────────────────
init_test_db "$TEST_MEMORY_DB"
rmdir "$TEST_LOCK_DIR" 2>/dev/null || rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true

ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" >/dev/null 2>/dev/null

row=$(/usr/bin/sqlite3 "$TEST_MEMORY_DB" \
    "SELECT order_id, scheduled_time, exit_code FROM standing_order_executions LIMIT 1;" 2>/dev/null)

# Expect: slug|HH:MM|0
order_id_val=$(echo "$row" | cut -d'|' -f1)
sched_val=$(echo "$row" | cut -d'|' -f2)
exit_val=$(echo "$row" | cut -d'|' -f3)

if [ -n "$order_id_val" ] && [ "$sched_val" = "$current_hhmm" ] && [ "$exit_val" = "0" ]; then
    ok "Execution recording writes correct fields (order_id=$order_id_val, time=$sched_val, exit=0)"
else
    not_ok "Execution recording writes correct fields" "row=$row"
fi

# ─────────────────────────────────────────────────────────────
# 7. HEARTBEAT.md parser extracts check IDs
# ─────────────────────────────────────────────────────────────
cat > "$TEST_HEARTBEAT_FILE" <<'EOF'
# Heartbeat Checklist
## System
- [ ] [disk] Disk usage below 90%
- [ ] [ram] RAM check
## Data
- [ ] [memory-db] Memory database OK
EOF

# Replicate the parser logic from alba-heartbeat-proactive.sh
parsed_ids=$(grep -oE '\[([a-z][a-z0-9-]*)\]' "$TEST_HEARTBEAT_FILE" | \
    grep -v '^\[ \]$' | \
    grep -v '^\[x\]$' | \
    sed 's/\[//g; s/\]//g' | \
    sort -u)

id_count=$(echo "$parsed_ids" | grep -c . || true)
has_disk=$(echo "$parsed_ids" | grep -c '^disk$' || true)
has_memory=$(echo "$parsed_ids" | grep -c '^memory-db$' || true)

if [ "$id_count" -eq 3 ] && [ "$has_disk" -ge 1 ] && [ "$has_memory" -ge 1 ]; then
    ok "HEARTBEAT.md parser extracts check IDs (found: $id_count)"
else
    not_ok "HEARTBEAT.md parser extracts check IDs" "count=$id_count ids=$parsed_ids"
fi

# ─────────────────────────────────────────────────────────────
# 8. Heartbeat runner completes with exit 0 against test file
# ─────────────────────────────────────────────────────────────
# Use a minimal heartbeat with only checks that pass in test env
cat > "$TEST_HEARTBEAT_FILE" <<'EOF'
# Test Heartbeat
- [ ] [disk] Disk check
- [ ] [memory-db] Memory DB check
EOF

init_test_db "$TEST_MEMORY_DB"
init_logs_db "$TEST_LOGS_DB"

hb_output=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    HEARTBEAT_FILE="$TEST_HEARTBEAT_FILE" \
    bash "$REPO_DIR/scripts/alba-heartbeat-proactive.sh" 2>/dev/null)
hb_exit=$?

if [ "$hb_exit" -eq 0 ] && echo "$hb_output" | grep -q "Heartbeat:"; then
    ok "Heartbeat runner completes exit 0 against test HEARTBEAT.md ($hb_output)"
else
    not_ok "Heartbeat runner completes exit 0 against test HEARTBEAT.md" "exit=$hb_exit output=$hb_output"
fi

# ─────────────────────────────────────────────────────────────
# 9. Lock contention: concurrent run is blocked by mkdir lock
# ─────────────────────────────────────────────────────────────
# Pre-create the lock dir to simulate a running instance
rmdir "$TEST_LOCK_DIR" 2>/dev/null || rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
mkdir -p "$TEST_LOCK_DIR"
# Touch it to now so it's not stale
touch "$TEST_LOCK_DIR"

init_test_db "$TEST_MEMORY_DB"
cat > "$TEST_ORDERS_FILE" <<EOF
# Standing Orders
- $current_hhmm — Lock test order
EOF

lock_output=$(ALBA_LOGS_DB="$TEST_LOGS_DB" ALBA_MEMORY_DB="$TEST_MEMORY_DB" \
    STANDING_ORDERS_FILE="$TEST_ORDERS_FILE" \
    bash "$REPO_DIR/scripts/alba-standing-orders.sh" 2>&1)
lock_exit=$?

# Should exit 0 (graceful) with LOCKED message on stderr
rmdir "$TEST_LOCK_DIR" 2>/dev/null || rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true

if [ "$lock_exit" -eq 0 ] && echo "$lock_output" | grep -q "LOCKED"; then
    ok "Lock contention: concurrent run is blocked by mkdir lock"
else
    not_ok "Lock contention: concurrent run is blocked by mkdir lock" "exit=$lock_exit output=$lock_output"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
