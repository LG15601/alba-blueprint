#!/usr/bin/env bash
# Alba — Pattern Promotion Hook (Stop)
# Runs promote-patterns.sh in a background subshell after session ends.
# Detects recurring learnings (3+ similar) and promotes them to Claude Code rules.
#
# Fail-open: never blocks session shutdown.

# ── Config ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.alba/logs/promote-patterns.log"

# ── Fork background worker (parent returns immediately) ───────
(
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] promote-patterns-hook: starting" >> "$LOG_FILE"
    bash "$SCRIPT_DIR/../scripts/promote-patterns.sh" >> "$LOG_FILE" 2>&1 || true
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] promote-patterns-hook: finished" >> "$LOG_FILE"
) > /dev/null 2>&1 &

exit 0
