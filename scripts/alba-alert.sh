#!/usr/bin/env bash
# alba-alert.sh — Shared alert library for all Alba components
#
# Usage:
#   source scripts/alba-alert.sh
#   send_alert "high_ram" "RSS exceeded 6GB"
#   send_alert_escalated "watchdog_dead" "Agent unreachable for 15min"
#
# Environment (overridable by sourcing script):
#   ALERT_COOLDOWN  — seconds between repeated alerts of same type (default: 600)
#   ALERT_DIR       — directory for rate-limit stamp files (default: /tmp)
#
# Dependencies:
#   alba-log.sh — structured logging (fail-open if not found)

set -u

# ---- Defaults (overridden if caller already set these) ----
ALERT_COOLDOWN="${ALERT_COOLDOWN:-600}"
ALERT_DIR="${ALERT_DIR:-/tmp}"

# ---- Source alba-log.sh for structured logging (fail-open) ----
_ALBA_ALERT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_ALBA_ALERT_DIR/alba-log.sh" ]; then
    # Only source if alba_log isn't already defined (caller may have sourced it)
    if ! type alba_log &>/dev/null; then
        source "$_ALBA_ALERT_DIR/alba-log.sh"
    fi
fi

# Fallback logger if alba_log is unavailable
_alert_log() {
    if type alba_log &>/dev/null; then
        alba_log "$1" alert "$2"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1 alert: $2" >&2
    fi
}

# ---- Rate limiter (shared by both send functions) ----
# Returns 0 if alert should be sent, 1 if suppressed by cooldown
_alert_rate_check() {
    local alert_type="$1"
    local stamp_file="${ALERT_DIR}/alba-alert-${alert_type}"

    if [ -f "$stamp_file" ]; then
        local last_sent now elapsed
        last_sent=$(cat "$stamp_file" 2>/dev/null || echo "0")
        now=$(date +%s)
        elapsed=$((now - last_sent))
        if [ "$elapsed" -lt "$ALERT_COOLDOWN" ]; then
            _alert_log INFO "suppressed (${alert_type}) — cooldown active (${elapsed}s < ${ALERT_COOLDOWN}s)"
            return 1
        fi
    fi
    return 0
}

# Update the rate-limit stamp after a successful send
_alert_stamp_update() {
    local alert_type="$1"
    local stamp_file="${ALERT_DIR}/alba-alert-${alert_type}"
    date +%s > "$stamp_file"
}

# ---- send_alert: Pushover (priority=1) + macOS notification ----
send_alert() {
    local alert_type="$1"
    local message="$2"

    _alert_rate_check "$alert_type" || return 0

    # Pushover (priority=1 — high priority, bypass quiet hours)
    if [ -n "${PUSHOVER_USER_KEY:-}" ] && [ -n "${PUSHOVER_API_TOKEN:-}" ]; then
        curl -s --max-time 10 -X POST https://api.pushover.net/1/messages.json \
            -d "token=${PUSHOVER_API_TOKEN}" \
            -d "user=${PUSHOVER_USER_KEY}" \
            -d "title=Alba Alert" \
            -d "message=${message}" \
            -d "priority=1" 2>/dev/null || true
        _alert_log INFO "sent via pushover (${alert_type})"
    fi

    # macOS notification (always attempted as fallback)
    osascript -e "display notification \"${message}\" with title \"Alba Alert\"" 2>/dev/null || true
    _alert_log INFO "sent via macos-notification (${alert_type})"

    _alert_stamp_update "$alert_type"
}

# ---- send_alert_escalated: Pushover emergency (priority=2) ----
# Emergency alerts require user acknowledgment. Pushover retries every
# retry= seconds until acknowledged or expire= seconds elapse.
send_alert_escalated() {
    local alert_type="$1"
    local message="$2"

    _alert_rate_check "$alert_type" || return 0

    # Pushover (priority=2 — emergency, requires acknowledgment)
    if [ -n "${PUSHOVER_USER_KEY:-}" ] && [ -n "${PUSHOVER_API_TOKEN:-}" ]; then
        curl -s --max-time 10 -X POST https://api.pushover.net/1/messages.json \
            -d "token=${PUSHOVER_API_TOKEN}" \
            -d "user=${PUSHOVER_USER_KEY}" \
            -d "title=Alba CRITICAL" \
            -d "message=${message}" \
            -d "priority=2" \
            -d "retry=60" \
            -d "expire=3600" 2>/dev/null || true
        _alert_log CRITICAL "escalated via pushover (${alert_type})"
    fi

    # macOS notification (always attempted as fallback)
    osascript -e "display notification \"${message}\" with title \"Alba CRITICAL\"" 2>/dev/null || true
    _alert_log CRITICAL "escalated via macos-notification (${alert_type})"

    _alert_stamp_update "$alert_type"
}
