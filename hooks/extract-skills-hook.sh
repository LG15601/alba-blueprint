#!/usr/bin/env bash
# Alba — Skill Extraction Hook (Stop)
# Runs extract-skills.sh in a background subshell after session ends.
# Detects successful multi-step workflows and extracts them as SKILL.md files.
#
# Fail-open: never blocks session shutdown.

# ── Config ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/alba-log.sh"

# ── Fork background worker (parent returns immediately) ───────
(
    alba_log INFO extract-skills-hook "starting"
    bash "$SCRIPT_DIR/../scripts/extract-skills.sh" > /dev/null 2>&1 || true
    alba_log INFO extract-skills-hook "finished"
) > /dev/null 2>&1 &

exit 0
