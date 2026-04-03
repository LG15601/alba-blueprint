#!/usr/bin/env bash
# verify-fallback.sh — TAP test suite for alba-fallback pipeline
# Tests fallback script, heartbeat integration, and install.sh wiring

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0
TOTAL=10

echo "1..$TOTAL"

tap_ok() {
    PASS=$((PASS + 1))
    echo "ok $1 - $2"
}

tap_fail() {
    FAIL=$((FAIL + 1))
    echo "not ok $1 - $2"
}

tap_skip() {
    PASS=$((PASS + 1))
    echo "ok $1 - $2 # SKIP $3"
}

# --- Static checks on alba-fallback.sh ---

# Test 1: Script exists and is executable
if [ -x "$SCRIPT_DIR/alba-fallback.sh" ]; then
    tap_ok 1 "alba-fallback.sh exists and is executable"
else
    tap_fail 1 "alba-fallback.sh missing or not executable"
fi

# Test 2: Syntax check
if bash -n "$SCRIPT_DIR/alba-fallback.sh" 2>/dev/null; then
    tap_ok 2 "alba-fallback.sh passes bash -n syntax check"
else
    tap_fail 2 "alba-fallback.sh has syntax errors"
fi

# Test 3: Sources alba-log.sh
if grep -q 'source.*alba-log\.sh' "$SCRIPT_DIR/alba-fallback.sh" 2>/dev/null; then
    tap_ok 3 "alba-fallback.sh sources alba-log.sh"
else
    tap_fail 3 "alba-fallback.sh does not source alba-log.sh"
fi

# Test 4: Uses jq -n --arg for safe JSON construction
if grep -q 'jq -n' "$SCRIPT_DIR/alba-fallback.sh" 2>/dev/null && grep -q '\-\-arg' "$SCRIPT_DIR/alba-fallback.sh" 2>/dev/null; then
    tap_ok 4 "alba-fallback.sh uses jq -n --arg for JSON construction"
else
    tap_fail 4 "alba-fallback.sh does not use safe JSON construction"
fi

# Test 5: Uses stream: false to prevent streaming fragments
if grep -q 'stream.*false' "$SCRIPT_DIR/alba-fallback.sh" 2>/dev/null; then
    tap_ok 5 "alba-fallback.sh disables streaming (stream: false)"
else
    tap_fail 5 "alba-fallback.sh does not disable streaming"
fi

# --- Runtime checks (skipped if Ollama not running) ---

OLLAMA_RUNNING=false
if curl -sf --max-time 5 http://localhost:11434/ > /dev/null 2>&1; then
    OLLAMA_RUNNING=true
fi

# Test 6: Ollama is reachable
if [ "$OLLAMA_RUNNING" = true ]; then
    tap_ok 6 "Ollama is reachable at localhost:11434"
else
    tap_skip 6 "Ollama reachable" "Ollama not running"
fi

# Test 7: alba-fallback.sh status exits 0 when Ollama running
if [ "$OLLAMA_RUNNING" = true ]; then
    if bash "$SCRIPT_DIR/alba-fallback.sh" status > /dev/null 2>&1; then
        tap_ok 7 "alba-fallback.sh status exits 0"
    else
        tap_fail 7 "alba-fallback.sh status exits non-zero"
    fi
else
    tap_skip 7 "alba-fallback.sh status" "Ollama not running"
fi

# --- Heartbeat and install integration ---

# Test 8: Heartbeat script passes syntax check
if bash -n "$SCRIPT_DIR/alba-heartbeat.sh" 2>/dev/null; then
    tap_ok 8 "alba-heartbeat.sh passes bash -n syntax check"
else
    tap_fail 8 "alba-heartbeat.sh has syntax errors"
fi

# Test 9: Heartbeat contains Ollama health check
if grep -q '11434' "$SCRIPT_DIR/alba-heartbeat.sh" 2>/dev/null; then
    tap_ok 9 "alba-heartbeat.sh contains Ollama health check (port 11434)"
else
    tap_fail 9 "alba-heartbeat.sh missing Ollama health check"
fi

# Test 10: install.sh contains Ollama check
if grep -q 'ollama' "$REPO_DIR/install.sh" 2>/dev/null; then
    tap_ok 10 "install.sh contains Ollama check"
else
    tap_fail 10 "install.sh missing Ollama check"
fi

# --- Summary ---
echo ""
echo "# $PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
