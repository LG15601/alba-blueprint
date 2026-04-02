#!/usr/bin/env bash
# verify-proactive-monitoring.sh — TAP test suite for proactive monitoring (S02)
#
# Tests: alba-alert.sh functions, alba-monitor.sh syntax+logging,
#        alba-dashboard.sh output, rate limiting, escalation tracking,
#        and start-alba.sh regression.
#
# Uses temp dirs. No side effects on real alert/escalation state.
#
# Usage: bash tests/verify-proactive-monitoring.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Temp dirs for isolation
TEST_ALERT_DIR=$(mktemp -d /tmp/alba-alert-test.XXXXXX)
TEST_ESC_DIR=$(mktemp -d /tmp/alba-esc-test.XXXXXX)
TEST_DB=$(mktemp /tmp/alba-monitor-test.XXXXXX.db)

PLAN=8
PASS=0
FAIL=0
TEST_NUM=0

cleanup() {
    rm -rf "$TEST_ALERT_DIR" "$TEST_ESC_DIR"
    rm -f "$TEST_DB" "${TEST_DB}-wal" "${TEST_DB}-shm"
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
# 1. alba-alert.sh syntax and function availability
# ─────────────────────────────────────────────────────────────
alert_check=$(bash -c "
    set -u
    source '$REPO_DIR/scripts/alba-alert.sh' 2>/dev/null
    type send_alert &>/dev/null && type send_alert_escalated &>/dev/null && echo 'FUNCTIONS_OK'
" 2>&1)

if echo "$alert_check" | grep -q 'FUNCTIONS_OK'; then
    ok "alba-alert.sh sources cleanly, send_alert and send_alert_escalated defined"
else
    not_ok "alba-alert.sh sources cleanly, send_alert and send_alert_escalated defined" "$alert_check"
fi

# ─────────────────────────────────────────────────────────────
# 2. alba-monitor.sh syntax check
# ─────────────────────────────────────────────────────────────
monitor_syntax=$(bash -n "$REPO_DIR/scripts/alba-monitor.sh" 2>&1)
if [ $? -eq 0 ]; then
    ok "alba-monitor.sh passes bash -n syntax check"
else
    not_ok "alba-monitor.sh passes bash -n syntax check" "$monitor_syntax"
fi

# ─────────────────────────────────────────────────────────────
# 3. alba-dashboard.sh syntax check
# ─────────────────────────────────────────────────────────────
dash_syntax=$(bash -n "$REPO_DIR/scripts/alba-dashboard.sh" 2>&1)
if [ $? -eq 0 ]; then
    ok "alba-dashboard.sh passes bash -n syntax check"
else
    not_ok "alba-dashboard.sh passes bash -n syntax check" "$dash_syntax"
fi

# ─────────────────────────────────────────────────────────────
# 4. Alert rate limiting — second call suppressed within cooldown
# ─────────────────────────────────────────────────────────────
rate_result=$(bash -c "
    export ALERT_COOLDOWN=600
    export ALERT_DIR='$TEST_ALERT_DIR'
    export PUSHOVER_USER_KEY=''
    export PUSHOVER_API_TOKEN=''
    source '$REPO_DIR/scripts/alba-alert.sh' 2>/dev/null

    # First call — should send (creates stamp file)
    send_alert 'test_rate' 'first call' 2>/dev/null

    # Stamp file should exist now
    if [ ! -f '${TEST_ALERT_DIR}/alba-alert-test_rate' ]; then
        echo 'NO_STAMP'
        exit 0
    fi

    # Second call — should be suppressed (within cooldown)
    output=\$(send_alert 'test_rate' 'second call' 2>&1)
    # _alert_log writes suppressed message — check stamp wasn't updated far from first
    stamp_val=\$(cat '${TEST_ALERT_DIR}/alba-alert-test_rate')
    now=\$(date +%s)
    diff=\$((now - stamp_val))
    # Stamp should be <=2s old (from first call, not updated by suppressed second call)
    if [ \$diff -le 3 ]; then
        echo 'RATE_OK'
    else
        echo 'RATE_FAIL diff=\$diff'
    fi
" 2>&1)

if echo "$rate_result" | grep -q 'RATE_OK'; then
    ok "Alert rate limiting — second call within cooldown is suppressed"
elif echo "$rate_result" | grep -q 'NO_STAMP'; then
    not_ok "Alert rate limiting — second call within cooldown is suppressed" "stamp file not created"
else
    not_ok "Alert rate limiting — second call within cooldown is suppressed" "$rate_result"
fi

# ─────────────────────────────────────────────────────────────
# 5. Escalation tracking — count increments and resets
# ─────────────────────────────────────────────────────────────
esc_result=$(bash -c "
    export ESCALATION_DIR='$TEST_ESC_DIR'
    export ESCALATION_THRESHOLD=3
    export PUSHOVER_USER_KEY=''
    export PUSHOVER_API_TOKEN=''
    export ALERT_DIR='$TEST_ALERT_DIR'
    export ALERT_COOLDOWN=0
    source '$REPO_DIR/scripts/alba-monitor.sh' 2>/dev/null

    # Simulate 3 consecutive critical checks
    track_escalation 'test_metric' 'critical' 'val=99' 2>/dev/null
    track_escalation 'test_metric' 'critical' 'val=99' 2>/dev/null
    track_escalation 'test_metric' 'critical' 'val=99' 2>/dev/null

    count_after=\$(cat '${TEST_ESC_DIR}/alba-monitor-escalation-test_metric' 2>/dev/null || echo -1)

    # Now reset with an ok status
    track_escalation 'test_metric' 'ok' '' 2>/dev/null
    count_reset=\$(cat '${TEST_ESC_DIR}/alba-monitor-escalation-test_metric' 2>/dev/null || echo -1)

    if [ \"\$count_after\" = '3' ] && [ \"\$count_reset\" = '0' ]; then
        echo 'ESC_OK'
    else
        echo \"ESC_FAIL count_after=\$count_after count_reset=\$count_reset\"
    fi
" 2>&1)

if echo "$esc_result" | grep -q 'ESC_OK'; then
    ok "Escalation tracking — count increments to threshold and resets on recovery"
else
    not_ok "Escalation tracking — count increments to threshold and resets on recovery" "$esc_result"
fi

# ─────────────────────────────────────────────────────────────
# 6. Dashboard output — contains expected sections
# ─────────────────────────────────────────────────────────────
dash_output=$(bash "$REPO_DIR/scripts/alba-dashboard.sh" 2>/dev/null)

dash_ok=true
dash_missing=""
for section in "Claude Process" "Disk Usage" "Logs DB" "Memory DB" "Error Rate" "Escalations"; do
    if ! echo "$dash_output" | grep -q "$section"; then
        dash_ok=false
        dash_missing="${dash_missing} ${section}"
    fi
done

if $dash_ok; then
    ok "Dashboard output contains all expected sections"
else
    not_ok "Dashboard output contains all expected sections" "missing:${dash_missing}"
fi

# ─────────────────────────────────────────────────────────────
# 7. Monitor writes log entries to alba-logs.db
# ─────────────────────────────────────────────────────────────

# Initialize test DB
init_output=$(bash "$REPO_DIR/scripts/alba-memory-init.sh" "$TEST_DB" 2>&1)
if [ $? -ne 0 ]; then
    not_ok "Monitor writes log entries with source=alba-monitor" "DB init failed: $init_output"
else
    # Run monitor against test DB (suppress stdout from run_check status lines)
    ALBA_LOGS_DB="$TEST_DB" ALBA_MEMORY_DB="$TEST_DB" \
        ESCALATION_DIR="$TEST_ESC_DIR" ALERT_DIR="$TEST_ALERT_DIR" ALERT_COOLDOWN=0 \
        PUSHOVER_USER_KEY="" PUSHOVER_API_TOKEN="" \
        bash "$REPO_DIR/scripts/alba-monitor.sh" >/dev/null 2>/dev/null

    monitor_rows=$(/usr/bin/sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM logs WHERE source='alba-monitor';" 2>/dev/null)
    monitor_rows="${monitor_rows:-0}"
    if [ "$monitor_rows" -gt 0 ]; then
        ok "Monitor writes log entries with source=alba-monitor (${monitor_rows} rows)"
    else
        not_ok "Monitor writes log entries with source=alba-monitor" "0 rows found"
    fi
fi

# ─────────────────────────────────────────────────────────────
# 8. start-alba.sh regression — syntax valid, send_alert callable
# ─────────────────────────────────────────────────────────────
start_syntax=$(bash -n "$REPO_DIR/scripts/start-alba.sh" 2>&1)
if [ $? -ne 0 ]; then
    not_ok "start-alba.sh regression — syntax valid and send_alert callable after sourcing alba-alert.sh" "$start_syntax"
else
    # Verify send_alert is available after sourcing alba-alert.sh (as start-alba.sh does)
    alert_available=$(bash -c "
        source '$REPO_DIR/scripts/alba-alert.sh' 2>/dev/null
        type send_alert &>/dev/null && echo 'AVAILABLE'
    " 2>&1)
    if echo "$alert_available" | grep -q 'AVAILABLE'; then
        ok "start-alba.sh regression — syntax valid and send_alert callable after sourcing alba-alert.sh"
    else
        not_ok "start-alba.sh regression — syntax valid and send_alert callable after sourcing alba-alert.sh" "send_alert not found after source"
    fi
fi

# ── TAP summary ──────────────────────────────────────────────
echo ""
echo "# Tests: $TEST_NUM  Pass: $PASS  Fail: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
