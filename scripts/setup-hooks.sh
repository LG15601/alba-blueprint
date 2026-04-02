#!/usr/bin/env bash
# setup-hooks.sh — Register Alba memory hooks in ~/.claude/settings.json
# Usage: bash scripts/setup-hooks.sh [--dry-run]
#
# Idempotently adds hook entries for the operational learning pipeline:
#   PostToolUse  → capture-observation.sh
#   SessionStart → inject-context.sh
#   Stop         → capture-session-summary.sh, extract-learnings.sh,
#                  promote-patterns-hook.sh, extract-skills-hook.sh
#
# Uses jq to merge — never overwrites existing entries.

set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# ── Preflight ────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not found. Install with: brew install jq" >&2
    exit 1
fi

if [[ ! -f "$SETTINGS_FILE" ]]; then
    echo "ERROR: Settings file not found: $SETTINGS_FILE" >&2
    exit 1
fi

# Read current settings
settings=$(cat "$SETTINGS_FILE")
changes=()

# ── Helper: check if a hook command already exists in settings ─
hook_exists() {
    local event_type="$1"
    local command_str="$2"
    echo "$settings" | jq -e \
        --arg et "$event_type" \
        --arg cmd "$command_str" \
        '.hooks[$et] // [] | map(.hooks[]? | select(.command == $cmd)) | length > 0' \
        >/dev/null 2>&1
}

# ── PostToolUse: capture-observation.sh ──────────────────────
OBS_CMD="bash ~/.alba/hooks/capture-observation.sh"
if hook_exists "PostToolUse" "$OBS_CMD"; then
    echo "✓ PostToolUse: capture-observation.sh already registered"
else
    changes+=("PostToolUse: capture-observation.sh")
    if ! $DRY_RUN; then
        settings=$(echo "$settings" | jq \
            --arg cmd "$OBS_CMD" \
            '.hooks.PostToolUse += [{"matcher": "Bash|Edit|Write|Read|Agent", "hooks": [{"type": "command", "command": $cmd, "timeout": 10}]}]')
    fi
fi

# ── SessionStart: inject-context.sh ──────────────────────────
INJECT_CMD="bash ~/.alba/hooks/inject-context.sh"
if hook_exists "SessionStart" "$INJECT_CMD"; then
    echo "✓ SessionStart: inject-context.sh already registered"
else
    changes+=("SessionStart: inject-context.sh")
    if ! $DRY_RUN; then
        # Add to existing SessionStart entry's hooks array if there's one entry,
        # otherwise add a new matcher entry
        has_session_start=$(echo "$settings" | jq '.hooks.SessionStart | length')
        if [[ "$has_session_start" -gt 0 ]]; then
            # Append to the first entry's hooks array
            settings=$(echo "$settings" | jq \
                --arg cmd "$INJECT_CMD" \
                '.hooks.SessionStart[0].hooks += [{"type": "command", "command": $cmd}]')
        else
            settings=$(echo "$settings" | jq \
                --arg cmd "$INJECT_CMD" \
                '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": $cmd}]}]')
        fi
    fi
fi

# ── Stop: capture-session-summary.sh (must come before extract-learnings.sh) ─
SUMMARY_CMD="bash ~/.alba/hooks/capture-session-summary.sh"
if hook_exists "Stop" "$SUMMARY_CMD"; then
    echo "✓ Stop: capture-session-summary.sh already registered"
else
    changes+=("Stop: capture-session-summary.sh")
    if ! $DRY_RUN; then
        has_stop=$(echo "$settings" | jq '.hooks.Stop | length')
        if [[ "$has_stop" -gt 0 ]]; then
            settings=$(echo "$settings" | jq \
                --arg cmd "$SUMMARY_CMD" \
                '.hooks.Stop[0].hooks += [{"type": "command", "command": $cmd}]')
        else
            settings=$(echo "$settings" | jq \
                --arg cmd "$SUMMARY_CMD" \
                '.hooks.Stop = [{"hooks": [{"type": "command", "command": $cmd}]}]')
        fi
    fi
fi

# ── Stop: extract-learnings.sh (after summary) ──────────────
EXTRACT_CMD="bash ~/.alba/hooks/extract-learnings.sh"
if hook_exists "Stop" "$EXTRACT_CMD"; then
    echo "✓ Stop: extract-learnings.sh already registered"
else
    changes+=("Stop: extract-learnings.sh")
    if ! $DRY_RUN; then
        # This always appends after summary was already added above
        settings=$(echo "$settings" | jq \
            --arg cmd "$EXTRACT_CMD" \
            '.hooks.Stop[0].hooks += [{"type": "command", "command": $cmd}]')
    fi
fi

# ── Stop: promote-patterns-hook.sh (after extract-learnings) ─
PROMOTE_CMD="bash ~/.alba/hooks/promote-patterns-hook.sh"
if hook_exists "Stop" "$PROMOTE_CMD"; then
    echo "✓ Stop: promote-patterns-hook.sh already registered"
else
    changes+=("Stop: promote-patterns-hook.sh")
    if ! $DRY_RUN; then
        settings=$(echo "$settings" | jq \
            --arg cmd "$PROMOTE_CMD" \
            '.hooks.Stop[0].hooks += [{"type": "command", "command": $cmd, "timeout": 30}]')
    fi
fi

# ── Stop: extract-skills-hook.sh (after promote-patterns) ────
SKILLS_CMD="bash ~/.alba/hooks/extract-skills-hook.sh"
if hook_exists "Stop" "$SKILLS_CMD"; then
    echo "✓ Stop: extract-skills-hook.sh already registered"
else
    changes+=("Stop: extract-skills-hook.sh")
    if ! $DRY_RUN; then
        settings=$(echo "$settings" | jq \
            --arg cmd "$SKILLS_CMD" \
            '.hooks.Stop[0].hooks += [{"type": "command", "command": $cmd, "timeout": 30}]')
    fi
fi

# ── Report / Apply ───────────────────────────────────────────
if [[ ${#changes[@]} -eq 0 ]]; then
    echo "All hooks already registered. No changes needed."
    exit 0
fi

echo ""
if $DRY_RUN; then
    echo "Planned changes (dry-run, no files modified):"
    for change in "${changes[@]}"; do
        echo "  + $change"
    done
else
    echo "Applied changes:"
    for change in "${changes[@]}"; do
        echo "  + $change"
    done
    echo "$settings" | jq '.' > "$SETTINGS_FILE"
    echo ""
    echo "Updated: $SETTINGS_FILE"
fi
