#!/usr/bin/env bash
# Alba — Session Summary Capture Hook (Stop / SessionEnd)
# Queries observations for the current session, produces a template-based
# structured summary, writes to session_summaries, and updates the sessions row.
#
# v1 uses heuristic extraction (counts, file lists, observation titles)
# rather than LLM-based summarization.
#
# Non-blocking: forks a background writer and returns immediately.

# ── Config ────────────────────────────────────────────────────
DB_PATH="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
LOG_FILE="${HOME}/.alba/logs/capture-session-summary.log"
SESSION_ID="${CLAUDE_SESSION_ID:-default-$(date +%Y%m%d)}"

# Skip if DB doesn't exist (memory not initialized)
[ -f "$DB_PATH" ] || exit 0

# ── Fork background writer (parent returns immediately) ───────
(
    mkdir -p "$(dirname "$LOG_FILE")"

    # ── Count observations by type ────────────────────────────
    obs_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM observations WHERE session_id='${SESSION_ID}';" 2>/dev/null)

    # Nothing captured this session — skip summary
    if [ -z "$obs_count" ] || [ "$obs_count" -eq 0 ] 2>/dev/null; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SKIP session=${SESSION_ID} no observations" >> "$LOG_FILE"
        exit 0
    fi

    type_counts=$(sqlite3 "$DB_PATH" \
        "SELECT type, COUNT(*) FROM observations WHERE session_id='${SESSION_ID}' GROUP BY type ORDER BY COUNT(*) DESC;" 2>/dev/null)

    # ── Gather file lists ─────────────────────────────────────
    # Collect all modified files across observations (JSON arrays → unique list)
    files_mod=$(sqlite3 "$DB_PATH" \
        "SELECT files_modified FROM observations WHERE session_id='${SESSION_ID}' AND files_modified != '[]';" 2>/dev/null \
        | jq -r '.[]?' 2>/dev/null | sort -u | head -20)

    files_read_list=$(sqlite3 "$DB_PATH" \
        "SELECT files_read FROM observations WHERE session_id='${SESSION_ID}' AND files_read != '[]';" 2>/dev/null \
        | jq -r '.[]?' 2>/dev/null | sort -u | head -20)

    # ── Extract last observation titles ───────────────────────
    last_titles=$(sqlite3 "$DB_PATH" \
        "SELECT title FROM observations WHERE session_id='${SESSION_ID}' ORDER BY created_at DESC LIMIT 5;" 2>/dev/null)

    # First observation title often indicates the request
    first_title=$(sqlite3 "$DB_PATH" \
        "SELECT title FROM observations WHERE session_id='${SESSION_ID}' ORDER BY created_at ASC LIMIT 1;" 2>/dev/null)

    # ── Count bugfixes and decisions ──────────────────────────
    bugfix_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM observations WHERE session_id='${SESSION_ID}' AND type='bugfix';" 2>/dev/null || echo "0")
    decision_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM observations WHERE session_id='${SESSION_ID}' AND type='decision';" 2>/dev/null || echo "0")
    discovery_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM observations WHERE session_id='${SESSION_ID}' AND type='discovery';" 2>/dev/null || echo "0")
    change_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM observations WHERE session_id='${SESSION_ID}' AND type='change';" 2>/dev/null || echo "0")

    # ── Build structured summary fields ───────────────────────

    # REQUEST: derived from first observation title
    request="Session with ${obs_count} tool calls"
    if [ -n "$first_title" ]; then
        request="Started with: ${first_title}"
    fi

    # INVESTIGATED: files read + discovery count
    investigated=""
    if [ "$discovery_count" -gt 0 ]; then
        investigated="${discovery_count} discoveries"
    fi
    if [ -n "$files_read_list" ]; then
        read_count=$(echo "$files_read_list" | wc -l | tr -d ' ')
        if [ -n "$investigated" ]; then
            investigated="${investigated}, read ${read_count} files"
        else
            investigated="Read ${read_count} files"
        fi
    fi
    [ -z "$investigated" ] && investigated="No specific investigation recorded"

    # LEARNED: decisions + bugfixes
    learned=""
    if [ "$decision_count" -gt 0 ]; then
        learned="${decision_count} decisions made"
    fi
    if [ "$bugfix_count" -gt 0 ]; then
        if [ -n "$learned" ]; then
            learned="${learned}, ${bugfix_count} bugs encountered"
        else
            learned="${bugfix_count} bugs encountered"
        fi
    fi
    [ -z "$learned" ] && learned="No specific learnings recorded"

    # COMPLETED: changes + files modified
    completed=""
    if [ "$change_count" -gt 0 ]; then
        completed="${change_count} changes"
    fi
    if [ -n "$files_mod" ]; then
        mod_count=$(echo "$files_mod" | wc -l | tr -d ' ')
        file_list=$(echo "$files_mod" | head -5 | tr '\n' ', ' | sed 's/,$//')
        if [ -n "$completed" ]; then
            completed="${completed} across ${mod_count} files: ${file_list}"
        else
            completed="Modified ${mod_count} files: ${file_list}"
        fi
    fi
    [ -z "$completed" ] && completed="No file modifications recorded"

    # NEXT_STEPS: derived from last observation titles
    next_steps=""
    if [ -n "$last_titles" ]; then
        last_title_line=$(echo "$last_titles" | head -1)
        next_steps="Last activity: ${last_title_line}"
    fi
    [ -z "$next_steps" ] && next_steps="No follow-up items identified"

    # Brief one-line summary for sessions.summary
    summary_text="${obs_count} observations (${change_count} changes, ${discovery_count} discoveries, ${bugfix_count} bugfixes, ${decision_count} decisions)"

    # ── SQL-safe escaping ─────────────────────────────────────
    esc() { printf '%s' "$1" | sed "s/'/''/g"; }

    request_safe=$(esc "$request")
    investigated_safe=$(esc "$investigated")
    learned_safe=$(esc "$learned")
    completed_safe=$(esc "$completed")
    next_steps_safe=$(esc "$next_steps")
    summary_safe=$(esc "$summary_text")

    # ── Write session summary ─────────────────────────────────
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO session_summaries (
        session_id, request, investigated, learned, completed, next_steps
    ) VALUES (
        '${SESSION_ID}',
        '${request_safe}',
        '${investigated_safe}',
        '${learned_safe}',
        '${completed_safe}',
        '${next_steps_safe}'
    );" 2>>"$LOG_FILE"

    rc_summary=$?

    # ── Update sessions row ───────────────────────────────────
    sqlite3 "$DB_PATH" "UPDATE sessions SET
        ended_at = datetime('now'),
        summary = '${summary_safe}',
        tool_call_count = ${obs_count}
    WHERE id = '${SESSION_ID}';" 2>>"$LOG_FILE"

    rc_session=$?

    if [ $rc_summary -ne 0 ] || [ $rc_session -ne 0 ]; then
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] FAIL session_summary session=${SESSION_ID} rc_summary=${rc_summary} rc_session=${rc_session}" >> "$LOG_FILE"
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] OK session=${SESSION_ID} obs=${obs_count}" >> "$LOG_FILE"
    fi

) > /dev/null 2>&1 &

exit 0
