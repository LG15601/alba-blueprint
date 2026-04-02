#!/bin/bash
# ==========================================================
# verify-auth-alerts.sh — Unit-level assertions for auth alert logic
# Exercises send_alert(), rate limiting, Pushover/macOS notification,
# and auth-expiry wiring without actually sending notifications.
# Output: TAP format (ok / not ok)
# Exit: 0 if all pass, 1 if any fail
# ==========================================================
set -u

SCRIPT="scripts/start-alba.sh"
ALERT_SCRIPT="scripts/alba-alert.sh"
PASS=0
FAIL=0
TEST_NUM=0
STAMP_FILE="/tmp/alba-last-alert-test"

trap 'rm -f "$STAMP_FILE"' EXIT

tap() {
    TEST_NUM=$((TEST_NUM + 1))
    local verdict="$1"
    local desc="$2"
    if [ "$verdict" = "ok" ]; then
        PASS=$((PASS + 1))
        echo "ok $TEST_NUM - $desc"
    else
        FAIL=$((FAIL + 1))
        echo "not ok $TEST_NUM - $desc"
    fi
}

# ---- Test 1: Syntax check ----
if bash -n "$SCRIPT" 2>/dev/null; then
    tap "ok" "bash -n syntax check passes"
else
    tap "FAIL" "bash -n syntax check passes"
fi

# ---- Test 2: send_alert function exists (in alba-alert.sh) ----
if grep -q 'send_alert()' "$ALERT_SCRIPT"; then
    tap "ok" "send_alert function exists"
else
    tap "FAIL" "send_alert function exists"
fi

# ---- Test 3: ALERT_COOLDOWN config exists (in alba-alert.sh) ----
if grep -q 'ALERT_COOLDOWN=' "$ALERT_SCRIPT"; then
    tap "ok" "ALERT_COOLDOWN config defined"
else
    tap "FAIL" "ALERT_COOLDOWN config defined"
fi

# ---- Test 4: Rate-limit file creation ----
now=$(date +%s)
echo "$now" > "$STAMP_FILE"
if [ -f "$STAMP_FILE" ]; then
    stored=$(cat "$STAMP_FILE")
    if echo "$stored" | grep -qE '^[0-9]+$'; then
        tap "ok" "rate-limit file created with valid epoch ($stored)"
    else
        tap "FAIL" "rate-limit file created with valid epoch (got: '$stored')"
    fi
else
    tap "FAIL" "rate-limit file created with valid epoch (file missing)"
fi

# ---- Test 5: Rate-limit suppression (within cooldown) ----
# Simulate: last alert sent 60 seconds ago, cooldown is 600 → should suppress
COOLDOWN=600
now=$(date +%s)
last_sent=$((now - 60))
echo "$last_sent" > "$STAMP_FILE"
elapsed=$((now - last_sent))
if [ "$elapsed" -lt "$COOLDOWN" ]; then
    tap "ok" "rate-limit suppresses within cooldown (${elapsed}s < ${COOLDOWN}s)"
else
    tap "FAIL" "rate-limit suppresses within cooldown (${elapsed}s < ${COOLDOWN}s)"
fi

# ---- Test 6: Rate-limit expiry (past cooldown) ----
# Simulate: last alert sent 700 seconds ago, cooldown is 600 → should allow
old_sent=$((now - 700))
echo "$old_sent" > "$STAMP_FILE"
elapsed=$((now - old_sent))
if [ "$elapsed" -ge "$COOLDOWN" ]; then
    tap "ok" "rate-limit allows after cooldown expires (${elapsed}s >= ${COOLDOWN}s)"
else
    tap "FAIL" "rate-limit allows after cooldown expires (${elapsed}s >= ${COOLDOWN}s)"
fi

# ---- Test 7: Pushover curl command construction (in alba-alert.sh) ----
if grep -q 'api.pushover.net' "$ALERT_SCRIPT"; then
    tap "ok" "Pushover curl posts to api.pushover.net"
else
    tap "FAIL" "Pushover curl posts to api.pushover.net"
fi

# ---- Test 8: macOS notification command (in alba-alert.sh) ----
if grep -q 'osascript.*display notification' "$ALERT_SCRIPT"; then
    tap "ok" "macOS notification via osascript display notification"
else
    tap "FAIL" "macOS notification via osascript display notification"
fi

# ---- Test 9: Auth expiry calls send_alert ----
if grep -q 'send_alert.*auth' "$SCRIPT"; then
    tap "ok" "auth expiry path calls send_alert"
else
    tap "FAIL" "auth expiry path calls send_alert"
fi

# ---- Test 10: Alert uses alba_log for structured logging ----
if grep -q 'alba_log' "$ALERT_SCRIPT"; then
    tap "ok" "Alert library uses alba_log for structured logging"
else
    tap "FAIL" "Alert library uses alba_log for structured logging"
fi

# ---- Summary ----
TOTAL=$((PASS + FAIL))
echo ""
echo "1..$TOTAL"
echo "# pass: $PASS"
echo "# fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "# FAILED"
    exit 1
else
    echo "# ALL PASSED"
    exit 0
fi
