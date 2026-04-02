#!/usr/bin/env bash
# Alba — Pattern Promotion Hook (Stop)
# Runs promote-patterns.sh in a background subshell after session ends.
# Detects recurring learnings (3+ similar) and promotes them to Claude Code rules.
#
# Fail-open: never blocks session shutdown.

# ── Config ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/alba-log.sh"

# ── Fork background worker (parent returns immediately) ───────
(
    alba_log INFO promote-patterns-hook "starting"
    bash "$SCRIPT_DIR/../scripts/promote-patterns.sh" > /dev/null 2>&1 || true
    alba_log INFO promote-patterns-hook "finished"
) > /dev/null 2>&1 &

exit 0
