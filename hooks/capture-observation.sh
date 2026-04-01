#!/usr/bin/env bash
# Alba — Observation Capture Hook (PostToolUse)
# Captures tool call observations into alba-memory.db for long-term memory.
#
# Fires asynchronously: reads stdin, forks background writer, returns <200ms.
# 'Never discard' policy — always saves even if extraction is partial.
#
# Hook protocol: receives JSON on stdin with tool_name/tool_input/tool_output.
#
# Frozen snapshot contract: this hook writes to the DB only.
# It does NOT regenerate ~/.alba/session-context.md mid-session.
# Snapshot refreshes on next session only — preserves prompt cache.

# ── Config ────────────────────────────────────────────────────
DB_PATH="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
LOG_FILE="${HOME}/.alba/logs/capture-observation.log"
SESSION_ID="${CLAUDE_SESSION_ID:-default-$(date +%Y%m%d)}"
PROJECT="${CLAUDE_PROJECT:-$(basename "$(pwd)")}"

# Skip if DB doesn't exist (memory not initialized)
[ -f "$DB_PATH" ] || exit 0

# ── Read stdin (tool context) ─────────────────────────────────
if [ -t 0 ]; then
    exit 0
fi
INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

# ── Extract tool info from JSON ───────────────────────────────
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null)
TOOL_INPUT_RAW=$(echo "$INPUT" | jq -c '.tool_input // {}' 2>/dev/null || echo '{}')
TOOL_OUTPUT_RAW=$(echo "$INPUT" | jq -r '.tool_output // ""' 2>/dev/null || echo '')

# Skip if no usable tool name
case "$TOOL_NAME" in
    unknown|""|null) exit 0 ;;
esac

# ── Fork background writer (parent returns immediately) ───────
# Variables are inherited by the subshell — no temp file needed.
(
    mkdir -p "$(dirname "$LOG_FILE")"

    # ── Ensure session row exists ─────────────────────────────
    project_safe=$(printf '%s' "$PROJECT" | sed "s/'/''/g")
    sqlite3 "$DB_PATH" \
        "INSERT OR IGNORE INTO sessions (id, project, started_at) VALUES ('${SESSION_ID}', '${project_safe}', datetime('now'));" \
        2>>"$LOG_FILE" || true

    # ── Classify observation type ─────────────────────────────
    obs_type="change"
    title=""
    subtitle=""
    files_read="[]"
    files_modified="[]"

    case "$TOOL_NAME" in
        Bash|bash)
            title=$(echo "$TOOL_INPUT_RAW" | jq -r '.command // empty' 2>/dev/null | head -c 200)
            [ -z "$title" ] && title="bash command"
            ;;
        Edit|edit|Write|write)
            filepath=$(echo "$TOOL_INPUT_RAW" | jq -r '.path // .file // empty' 2>/dev/null)
            title="Modified: ${filepath:-unknown file}"
            files_modified=$(echo "$TOOL_INPUT_RAW" | jq -c '[.path // .file // empty] | map(select(. != ""))' 2>/dev/null || echo "[]")
            ;;
        Read|read)
            obs_type="discovery"
            filepath=$(echo "$TOOL_INPUT_RAW" | jq -r '.path // .file // empty' 2>/dev/null)
            title="Read: ${filepath:-unknown file}"
            files_read=$(echo "$TOOL_INPUT_RAW" | jq -c '[.path // .file // empty] | map(select(. != ""))' 2>/dev/null || echo "[]")
            ;;
        Agent|agent|subagent)
            obs_type="decision"
            title=$(echo "$TOOL_INPUT_RAW" | jq -r '.task // .prompt // empty' 2>/dev/null | head -c 200)
            [ -z "$title" ] && title="Agent delegation"
            ;;
        *)
            title="Tool call: $TOOL_NAME"
            ;;
    esac

    # ── Scan output for patterns ──────────────────────────────
    output_text=$(printf '%s' "$TOOL_OUTPUT_RAW" | head -c 4000)

    # Detect errors → upgrade to bugfix type
    # Pattern targets actual error output, not code containing error-handling constructs
    if printf '%s' "$output_text" | grep -qE '(^(Error|ERROR|FATAL|FAIL|panic):| error[: ]|Exception:|Traceback |FAILED |fatal error|npm ERR!|exit code [1-9])' 2>/dev/null; then
        obs_type="bugfix"
        error_line=$(printf '%s' "$output_text" | grep -E '(^(Error|ERROR|FATAL|FAIL|panic):| error[: ]|Exception:|Traceback |FAILED |fatal error|npm ERR!|exit code [1-9])' | head -1 | head -c 200)
        subtitle="Error: ${error_line}"
    fi

    # Detect decisions
    if printf '%s' "$output_text" | grep -qiE '(decided|choosing|decision|will use|switched to|migrated)' 2>/dev/null; then
        obs_type="decision"
    fi

    # Extract file paths from output
    mentioned_files=$(printf '%s' "$output_text" | grep -oE '[a-zA-Z0-9_./-]+\.(ts|js|py|sh|sql|md|json|yaml|yml|css|html|tsx|jsx|rs|go|rb)' 2>/dev/null | sort -u | head -10 | jq -R . 2>/dev/null | jq -sc '.' 2>/dev/null || echo "[]")
    if [ "$mentioned_files" != "[]" ] && [ "$files_read" = "[]" ] && [ "$files_modified" = "[]" ]; then
        files_read="$mentioned_files"
    fi

    # Extract key facts (versions, URLs)
    facts=$(printf '%s' "$output_text" | grep -oE '(v[0-9]+\.[0-9]+\.[0-9]+|https?://[^ ]+)' 2>/dev/null | head -5 | jq -R . 2>/dev/null | jq -sc '.' 2>/dev/null || echo "[]")

    # Narrative: truncated output
    narrative=$(printf '%s' "$output_text" | head -c 1000)

    # ── SQL-safe escaping ─────────────────────────────────────
    title_safe=$(printf '%s' "$title" | sed "s/'/''/g" | head -c 200)
    subtitle_safe=$(printf '%s' "$subtitle" | sed "s/'/''/g" | head -c 500)
    narrative_safe=$(printf '%s' "$narrative" | sed "s/'/''/g")
    facts_safe=$(printf '%s' "$facts" | sed "s/'/''/g")
    files_read_safe=$(printf '%s' "$files_read" | sed "s/'/''/g")
    files_modified_safe=$(printf '%s' "$files_modified" | sed "s/'/''/g")

    # ── Insert observation ────────────────────────────────────
    sqlite3 "$DB_PATH" "INSERT INTO observations (
        session_id, type, title, subtitle, narrative,
        facts, concepts, files_read, files_modified, created_at
    ) VALUES (
        '${SESSION_ID}',
        '${obs_type}',
        '${title_safe}',
        '${subtitle_safe}',
        '${narrative_safe}',
        '${facts_safe}',
        '[]',
        '${files_read_safe}',
        '${files_modified_safe}',
        datetime('now')
    );" 2>>"$LOG_FILE"

    rc=$?
    if [ $rc -ne 0 ]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAIL insert tool=$TOOL_NAME rc=$rc" >> "$LOG_FILE"
    fi

) > /dev/null 2>&1 &

exit 0
