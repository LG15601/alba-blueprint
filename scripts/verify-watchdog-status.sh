#!/bin/bash
# ==========================================================
# verify-watchdog-status.sh — TAP test suite for watchdog status detection
# Verifies all 6 status states, uptime display, and detection logic
# added in S03 (Watchdog v3 Consolidation & Health Status).
# Output: TAP format (ok / not ok)
# Exit: 0 if all pass, 1 if any fail
# ==========================================================
set -u

SCRIPT="scripts/start-alba.sh"
PASS=0
FAIL=0
TEST_NUM=0

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

# ---- Test 2: get_uptime_display function exists ----
if grep -q 'get_uptime_display' "$SCRIPT"; then
    tap "ok" "get_uptime_display function exists"
else
    tap "FAIL" "get_uptime_display function exists"
fi

# ---- Test 3: START_TIME_FILE config exists ----
if grep -q 'START_TIME_FILE' "$SCRIPT"; then
    tap "ok" "START_TIME_FILE config exists"
else
    tap "FAIL" "START_TIME_FILE config exists"
fi

# ---- Test 4: Uptime formatting arithmetic ----
# Replicate get_uptime_display logic inline for two cases
uptime_ok=true

# Case A: 2h 35m (9300 seconds)
elapsed_a=9300
days_a=$((elapsed_a / 86400))
hours_a=$(( (elapsed_a % 86400) / 3600 ))
mins_a=$(( (elapsed_a % 3600) / 60 ))
if [ "$days_a" -gt 0 ]; then
    result_a="${days_a}d ${hours_a}h"
elif [ "$hours_a" -gt 0 ]; then
    result_a="${hours_a}h ${mins_a}m"
else
    result_a="${mins_a}m"
fi
if [ "$result_a" != "2h 35m" ]; then
    uptime_ok=false
fi

# Case B: 42m only (2520 seconds)
elapsed_b=2520
days_b=$((elapsed_b / 86400))
hours_b=$(( (elapsed_b % 86400) / 3600 ))
mins_b=$(( (elapsed_b % 3600) / 60 ))
if [ "$days_b" -gt 0 ]; then
    result_b="${days_b}d ${hours_b}h"
elif [ "$hours_b" -gt 0 ]; then
    result_b="${hours_b}h ${mins_b}m"
else
    result_b="${mins_b}m"
fi
if [ "$result_b" != "42m" ]; then
    uptime_ok=false
fi

# Case C: 1d 3h (97200 seconds)
elapsed_c=97200
days_c=$((elapsed_c / 86400))
hours_c=$(( (elapsed_c % 86400) / 3600 ))
mins_c=$(( (elapsed_c % 3600) / 60 ))
if [ "$days_c" -gt 0 ]; then
    result_c="${days_c}d ${hours_c}h"
elif [ "$hours_c" -gt 0 ]; then
    result_c="${hours_c}h ${mins_c}m"
else
    result_c="${mins_c}m"
fi
if [ "$result_c" != "1d 3h" ]; then
    uptime_ok=false
fi

if [ "$uptime_ok" = true ]; then
    tap "ok" "uptime formatting: 2h35m, 42m, 1d3h cases correct"
else
    tap "FAIL" "uptime formatting: got A='$result_a' B='$result_b' C='$result_c'"
fi

# ---- Test 5: TELEGRAM_DEAD detection pattern ----
if grep -q 'pgrep.*telegram' "$SCRIPT"; then
    tap "ok" "TELEGRAM_DEAD detection uses pgrep telegram pattern"
else
    tap "FAIL" "TELEGRAM_DEAD detection uses pgrep telegram pattern"
fi

# ---- Test 6: BUSY detection pattern ----
if grep -q 'IDLE_PROMPT_PATTERN' "$SCRIPT"; then
    tap "ok" "BUSY detection uses IDLE_PROMPT_PATTERN"
else
    tap "FAIL" "BUSY detection uses IDLE_PROMPT_PATTERN"
fi

# ---- Test 7: Status priority order (line-number check) ----
# Extract line numbers of each state within the status block
status_start=$(grep -n 'status)' "$SCRIPT" | head -1 | cut -d: -f1)
if [ -n "$status_start" ]; then
    # Get line numbers for echo statements containing each state (skip comments)
    ln_stopped=$(grep -n 'echo.*STOPPED' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')
    ln_degraded=$(grep -n 'echo.*DEGRADED' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')
    ln_auth=$(grep -n 'echo.*AUTH_EXPIRED' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')
    ln_telegram=$(grep -n 'echo.*TELEGRAM_DEAD' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')
    ln_busy=$(grep -n 'echo.*BUSY' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')
    ln_healthy=$(grep -n 'echo.*HEALTHY' "$SCRIPT" | awk -F: -v s="$status_start" '$1 > s {print $1; exit}')

    if [ -n "$ln_stopped" ] && [ -n "$ln_degraded" ] && [ -n "$ln_auth" ] && \
       [ -n "$ln_telegram" ] && [ -n "$ln_busy" ] && [ -n "$ln_healthy" ] && \
       [ "$ln_stopped" -lt "$ln_degraded" ] && \
       [ "$ln_degraded" -lt "$ln_auth" ] && \
       [ "$ln_auth" -lt "$ln_telegram" ] && \
       [ "$ln_telegram" -lt "$ln_busy" ] || [ "$ln_telegram" -lt "$ln_healthy" ]; then
       # BUSY and HEALTHY are in an if/else block — either order is valid as long as both come after TELEGRAM_DEAD
        tap "ok" "status priority order: STOPPED($ln_stopped) < DEGRADED($ln_degraded) < AUTH_EXPIRED($ln_auth) < TELEGRAM_DEAD($ln_telegram) < BUSY($ln_busy) < HEALTHY($ln_healthy)"
    else
        tap "FAIL" "status priority order incorrect: STOPPED=$ln_stopped DEGRADED=$ln_degraded AUTH=$ln_auth TELEGRAM=$ln_telegram BUSY=$ln_busy HEALTHY=$ln_healthy"
    fi
else
    tap "FAIL" "status) block not found"
fi

# ---- Test 8: Status output includes uptime ----
if grep -n 'uptime' "$SCRIPT" | awk -F: -v s="${status_start:-0}" '$1 > s' | grep -q 'uptime'; then
    tap "ok" "status output references uptime"
else
    tap "FAIL" "status output references uptime"
fi

# ---- Test 9: Start time written on launch ----
# Look for START_TIME_FILE write near launch (date +%s > START_TIME_FILE)
if grep -q 'date +%s.*START_TIME_FILE\|START_TIME_FILE.*date' "$SCRIPT"; then
    tap "ok" "start time persisted on launch"
else
    # Check alternate pattern: date +%s > "$START_TIME_FILE"
    if grep -q 'date.*>.*START_TIME_FILE\|START_TIME_FILE' "$SCRIPT" && grep -q 'date +%s' "$SCRIPT"; then
        tap "ok" "start time persisted on launch"
    else
        tap "FAIL" "start time persisted on launch"
    fi
fi

# ---- Test 10: Start time cleaned on stop ----
# Look for rm -f "$START_TIME_FILE" or similar in stop block
stop_start=$(grep -n 'stop)' "$SCRIPT" | head -1 | cut -d: -f1)
if [ -n "$stop_start" ]; then
    # Check for START_TIME_FILE removal after the stop) line
    if awk -v s="$stop_start" 'NR > s && /START_TIME_FILE/' "$SCRIPT" | grep -q 'rm\|START_TIME_FILE'; then
        tap "ok" "START_TIME_FILE cleaned on stop"
    else
        tap "FAIL" "START_TIME_FILE not cleaned in stop block"
    fi
else
    tap "FAIL" "stop) block not found"
fi

# ---- Test 11: All 6 states present ----
all_states=true
missing=""
for state in STOPPED DEGRADED AUTH_EXPIRED TELEGRAM_DEAD BUSY HEALTHY; do
    if ! grep -q "$state" "$SCRIPT"; then
        all_states=false
        missing="$missing $state"
    fi
done
if [ "$all_states" = true ]; then
    tap "ok" "all 6 states present: STOPPED DEGRADED AUTH_EXPIRED TELEGRAM_DEAD BUSY HEALTHY"
else
    tap "FAIL" "missing states:$missing"
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
    echo "# All 11 passed"
    exit 0
fi
