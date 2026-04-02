#!/usr/bin/env bash
# Alba — Skill Extraction Hook (Stop)
# Runs extract-skills.sh in a background subshell after session ends.
# Detects successful multi-step workflows and extracts them as SKILL.md files.
#
# Fail-open: never blocks session shutdown.

# ── Config ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.alba/logs/extract-skills.log"

# ── Fork background worker (parent returns immediately) ───────
(
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] extract-skills-hook: starting" >> "$LOG_FILE"
    bash "$SCRIPT_DIR/../scripts/extract-skills.sh" >> "$LOG_FILE" 2>&1 || true
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] extract-skills-hook: finished" >> "$LOG_FILE"
) > /dev/null 2>&1 &

exit 0
