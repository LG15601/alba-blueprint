#!/usr/bin/env bash
# verify-centralized-logging.sh — TAP test suite for centralized logging infrastructure
#
# Tests migration 005, alba_log(), alba_log_bg(), alba-logs-query.sh, fallback, and concurrency.
# Uses temp DB. No side effects on real DB.
#
# Usage: bash tests/verify-centralized-logging.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DB=$(mktemp /tmp/alba-log-test.XXXXXX.db)
TEST_HOME=$(mktemp -d /tmp/alba-log-home.XXXXXX)

PLAN=7
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
    rm -rf "$TEST_HOME"
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
# 1. Migration applies, logs table exists with correct columns
# ─────────────────────────────────────────────────────────────
tables=$(sqlite3 "$TEST_DB" ".tables" 2>/dev/null)
if echo "$tables" | grep -qw 'logs'; then
    cols=$(sqlite3 "$TEST_DB" "PRAGMA table_info(logs);" 2>/dev/null | cut -d'|' -f2 | tr '\n' ' ')
    expected_cols="id timestamp level source component message metadata"
    all_found=true
    for col in $expected_cols; do
        if ! echo "$cols" | grep -qw "$col"; then
            all_found=false
            break
        fi
    done
    if $all_found; then
        # Verify indexes exist
        indexes=$(sqlite3 "$TEST_DB" ".indices logs" 2>/dev/null | tr '\n' ' ')
        idx_ok=true
        for idx in idx_logs_timestamp idx_logs_level idx_logs_source; do
            echo "$indexes" | grep -qw "$idx" || idx_ok=false
        done
        if $idx_ok; then
            ok "Migration 005: logs table with correct columns and indexes"
        else
            not_ok "Migration 005: logs table with correct columns and indexes" "missing indexes; got: $indexes"
        fi
    else
        not_ok "Migration 005: logs table with correct columns and indexes" "missing columns; got: $cols"
    fi
else
    not_ok "Migration 005: logs table with correct columns and indexes" "logs table not found; tables: $tables"
fi

# ─────────────────────────────────────────────────────────────
# 2. alba_log writes a row to DB with correct fields
# ─────────────────────────────────────────────────────────────
source "$REPO_DIR/scripts/alba-log.sh"
ALBA_LOGS_DB="$TEST_DB"

alba_log INFO watchdog "Health check passed" '{"uptime":3600}'

row=$(sqlite3 "$TEST_DB" "SELECT level, source, message, metadata FROM logs ORDER BY id DESC LIMIT 1;" 2>/dev/null)
if [ "$row" = 'INFO|watchdog|Health check passed|{"uptime":3600}' ]; then
    ok "alba_log writes structured row with correct fields"
else
    not_ok "alba_log writes structured row with correct fields" "got: $row"
fi

# ─────────────────────────────────────────────────────────────
# 3. Multiple log levels work
# ─────────────────────────────────────────────────────────────
for lvl in DEBUG INFO WARN ERROR CRITICAL; do
    alba_log "$lvl" test "Level test $lvl"
done

level_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(DISTINCT level) FROM logs WHERE source='test';" 2>/dev/null)
if [ "$level_count" -eq 5 ]; then
    ok "All 5 log levels (DEBUG, INFO, WARN, ERROR, CRITICAL) write successfully"
else
    not_ok "All 5 log levels write successfully" "distinct levels=$level_count"
fi

# ─────────────────────────────────────────────────────────────
# 4. Fallback works when DB path is invalid
# ─────────────────────────────────────────────────────────────
ALBA_LOGS_DB="/nonexistent/path/nope.db"
ALBA_LOGS_FALLBACK="$TEST_HOME/.alba/logs/alba-fallback.log"

alba_log ERROR fallback-test "Should go to fallback"

# Restore DB path
ALBA_LOGS_DB="$TEST_DB"

if [ -f "$ALBA_LOGS_FALLBACK" ] && grep -q "fallback-test" "$ALBA_LOGS_FALLBACK"; then
    ok "Fallback: writes to text log when DB is unavailable"
else
    not_ok "Fallback: writes to text log when DB is unavailable" "fallback file missing or empty"
fi

# ─────────────────────────────────────────────────────────────
# 5. alba_log never writes to stdout (capture test)
# ─────────────────────────────────────────────────────────────
ALBA_LOGS_DB="$TEST_DB"
captured_stdout=$(alba_log INFO stdout-test "This should produce no stdout" 2>/dev/null)

if [ -z "$captured_stdout" ]; then
    ok "alba_log produces no stdout output (safe for subshell capture)"
else
    not_ok "alba_log produces no stdout output" "captured: $captured_stdout"
fi

# ─────────────────────────────────────────────────────────────
# 6. alba-logs-query.sh last/errors/source subcommands work
# ─────────────────────────────────────────────────────────────
query_ok=true
query_issues=""

# last
last_output=$(ALBA_LOGS_DB="$TEST_DB" bash "$REPO_DIR/scripts/alba-logs-query.sh" last 5 2>/dev/null)
if [ -z "$last_output" ]; then
    query_ok=false
    query_issues="${query_issues} last-empty"
fi

# errors — we logged an ERROR in test 2
errors_output=$(ALBA_LOGS_DB="$TEST_DB" bash "$REPO_DIR/scripts/alba-logs-query.sh" errors 5 2>/dev/null)
if ! echo "$errors_output" | grep -q "ERROR"; then
    query_ok=false
    query_issues="${query_issues} errors-missing"
fi

# source
source_output=$(ALBA_LOGS_DB="$TEST_DB" bash "$REPO_DIR/scripts/alba-logs-query.sh" source watchdog 5 2>/dev/null)
if ! echo "$source_output" | grep -q "watchdog"; then
    query_ok=false
    query_issues="${query_issues} source-missing"
fi

if $query_ok; then
    ok "alba-logs-query.sh last/errors/source subcommands return correct data"
else
    not_ok "alba-logs-query.sh last/errors/source subcommands" "issues:$query_issues"
fi

# ─────────────────────────────────────────────────────────────
# 7. Concurrent writes don't fail (3 parallel alba_log calls)
# ─────────────────────────────────────────────────────────────
count_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM logs;" 2>/dev/null)

alba_log INFO concurrent "Write 1" &
pid1=$!
alba_log INFO concurrent "Write 2" &
pid2=$!
alba_log INFO concurrent "Write 3" &
pid3=$!

wait $pid1 $pid2 $pid3

count_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM logs;" 2>/dev/null)
concurrent_added=$((count_after - count_before))

if [ "$concurrent_added" -eq 3 ]; then
    ok "Concurrent writes: 3 parallel alba_log calls all succeed"
else
    not_ok "Concurrent writes: 3 parallel alba_log calls" "expected 3 new rows, got $concurrent_added"
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
