#!/usr/bin/env bash
# Alba — Context Injection Hook (SessionStart)
# Queries alba-memory.db for recent sessions and observations, builds a
# progressive-disclosure context block, and writes it to ~/.alba/session-context.md.
#
# Progressive disclosure strategy:
#   - Last 3 session summaries as compact bullets
#   - Table of older observations (title-only, compact)
#   - Full narrative + facts for the most recent observations
#
# Snapshot refreshes on next session only — preserves prompt cache.
# Mid-session writes (capture-observation.sh) do NOT regenerate this file.
#
# Token budget: ≤4000 tokens (~16000 chars) max output.

set -euo pipefail

# ── Config ────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/alba-log.sh"

DB_PATH="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
OUTPUT_FILE="${ALBA_SESSION_CONTEXT:-$HOME/.alba/session-context.md}"

# ── Pressure-aware budget scaling ─────────────────────────────
# Read tool call counter to determine context pressure tier.
# Higher pressure → smaller context injection to reduce compaction risk.
# This only affects *next* session start (frozen snapshot semantics).
_COUNTER_FILE="${COUNTER_FILE:-/tmp/alba-tool-counter}"
_tool_count=0
if [ -f "$_COUNTER_FILE" ]; then
    _tool_count=$(cat "$_COUNTER_FILE" 2>/dev/null || echo 0)
    _tool_count=$((_tool_count + 0)) 2>/dev/null || _tool_count=0
fi

if [ "$_tool_count" -ge 100 ]; then
    # Minimal budget — context is critically large
    MAX_CHARS=6000
    SESSION_COUNT=1
    FULL_OBSERVATION_COUNT=2
    TOTAL_OBSERVATION_COUNT=8
elif [ "$_tool_count" -ge 50 ]; then
    # Reduced budget — context pressure building
    MAX_CHARS=10000
    SESSION_COUNT=2
    FULL_OBSERVATION_COUNT=3
    TOTAL_OBSERVATION_COUNT=15
else
    # Full budget — context is healthy
    MAX_CHARS=16000
    SESSION_COUNT=3
    FULL_OBSERVATION_COUNT=5
    TOTAL_OBSERVATION_COUNT=30
fi

START_TS=$(date +%s)

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── Guard: skip if DB doesn't exist ──────────────────────────
if [ ! -f "$DB_PATH" ]; then
    alba_log INFO inject-context "SKIP no database at ${DB_PATH}"
    exit 0
fi

# ── Guard: skip if snapshot was generated <5min ago ──────────
# Prevents double-injection on fast restarts.
if [ -f "$OUTPUT_FILE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        file_mod=$(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0)
    else
        file_mod=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    age=$(( now - file_mod ))
    if [ "$age" -lt 300 ]; then
        alba_log INFO inject-context "SKIP snapshot age=${age}s (<300s)"
        exit 0
    fi
fi

# ── Query: recent sessions ───────────────────────────────────
# Get last N sessions with summaries (pipe-delimited for safe parsing)
session_rows=$(sqlite3 -separator '|||' "$DB_PATH" "
    SELECT s.id, s.project, s.started_at, s.ended_at,
           COALESCE(s.summary, 'no summary'),
           COALESCE(ss.completed, ''),
           s.tool_call_count
    FROM sessions s
    LEFT JOIN session_summaries ss ON ss.session_id = s.id
    WHERE s.ended_at IS NOT NULL
    ORDER BY s.started_at DESC
    LIMIT ${SESSION_COUNT};
" 2>/dev/null || echo "")

# ── Query: recent observations (full detail) ─────────────────
full_obs=$(sqlite3 -separator '|||' "$DB_PATH" "
    SELECT id, type, title,
           COALESCE(subtitle, ''),
           COALESCE(narrative, ''),
           COALESCE(facts, '[]'),
           created_at
    FROM observations
    ORDER BY created_at DESC
    LIMIT ${FULL_OBSERVATION_COUNT};
" 2>/dev/null || echo "")

# ── Query: older observations (title-only table) ─────────────
# Offset by FULL_OBSERVATION_COUNT to avoid overlap
older_obs_count=$(( TOTAL_OBSERVATION_COUNT - FULL_OBSERVATION_COUNT ))
older_obs=$(sqlite3 -separator '|||' "$DB_PATH" "
    SELECT id, created_at, type, title,
           LENGTH(COALESCE(narrative, ''))
    FROM observations
    ORDER BY created_at DESC
    LIMIT ${older_obs_count} OFFSET ${FULL_OBSERVATION_COUNT};
" 2>/dev/null || echo "")

# ── Count total observations in DB ────────────────────────────
total_in_db=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM observations;" 2>/dev/null || echo "0")

# ── Build context block ──────────────────────────────────────
snapshot_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

ctx="## Recent Memory (frozen snapshot)
<!-- SNAPSHOT_GENERATED_AT: ${snapshot_ts} -->
<!-- Total observations in DB: ${total_in_db} | Showing: up to ${TOTAL_OBSERVATION_COUNT} -->
"

# ── Section: Recent Sessions ─────────────────────────────────
if [ -n "$session_rows" ]; then
    ctx="${ctx}
### Recent Sessions
"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        s_id=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
        s_project=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
        s_started=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')
        s_summary=$(echo "$row" | awk -F'\\|\\|\\|' '{print $5}')
        s_completed=$(echo "$row" | awk -F'\\|\\|\\|' '{print $6}')
        s_tools=$(echo "$row" | awk -F'\\|\\|\\|' '{print $7}')

        # Format: compact bullet
        bullet="- **${s_started}** (${s_project}): ${s_summary}"
        if [ -n "$s_completed" ] && [ "$s_completed" != "" ]; then
            bullet="${bullet} — ${s_completed}"
        fi
        ctx="${ctx}${bullet}
"
    done <<< "$session_rows"
fi

# ── Section: Older observations table ─────────────────────────
if [ -n "$older_obs" ]; then
    ctx="${ctx}
### Observation Timeline

| ID | Time | Type | Title | ~Tokens |
|----|------|------|-------|---------|
"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        o_id=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
        o_time=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
        o_type=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')
        o_title=$(echo "$row" | awk -F'\\|\\|\\|' '{print $4}')
        o_narr_len=$(echo "$row" | awk -F'\\|\\|\\|' '{print $5}')

        # Estimate tokens: ~4 chars per token
        est_tokens=$(( (o_narr_len + 3) / 4 ))

        # Truncate title to 80 chars for table readability
        if [ ${#o_title} -gt 80 ]; then
            o_title="${o_title:0:77}..."
        fi

        ctx="${ctx}| ${o_id} | ${o_time} | ${o_type} | ${o_title} | ${est_tokens} |
"
    done <<< "$older_obs"
fi

# ── Section: Full recent observations ─────────────────────────
if [ -n "$full_obs" ]; then
    ctx="${ctx}
### Recent Observations (full detail)
"
    while IFS= read -r row; do
        [ -z "$row" ] && continue
        o_id=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
        o_type=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
        o_title=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')
        o_subtitle=$(echo "$row" | awk -F'\\|\\|\\|' '{print $4}')
        o_narrative=$(echo "$row" | awk -F'\\|\\|\\|' '{print $5}')
        o_facts=$(echo "$row" | awk -F'\\|\\|\\|' '{print $6}')
        o_created=$(echo "$row" | awk -F'\\|\\|\\|' '{print $7}')

        ctx="${ctx}
#### [${o_type}] ${o_title}
_${o_created}_
"
        if [ -n "$o_subtitle" ]; then
            ctx="${ctx}${o_subtitle}
"
        fi

        if [ -n "$o_narrative" ]; then
            # Truncate individual narrative to ~2000 chars to stay within budget
            if [ ${#o_narrative} -gt 2000 ]; then
                o_narrative="${o_narrative:0:1997}..."
            fi
            ctx="${ctx}
${o_narrative}
"
        fi

        if [ "$o_facts" != "[]" ] && [ -n "$o_facts" ]; then
            ctx="${ctx}
**Facts:** ${o_facts}
"
        fi
    done <<< "$full_obs"
fi

# ── Section: Recent Learnings ─────────────────────────────────
# Only include if learnings table exists and has rows
has_learnings=$(sqlite3 "$DB_PATH" ".tables" 2>/dev/null | grep -c 'learnings' || echo "0")
if [ "$has_learnings" -gt 0 ]; then
    learnings_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")
    if [ "$learnings_count" -gt 0 ] 2>/dev/null; then
        learnings_rows=$(sqlite3 -separator '|||' "$DB_PATH" "
            SELECT content, COALESCE(category, 'general'), created_at
            FROM learnings
            ORDER BY created_at DESC
            LIMIT 10;
        " 2>/dev/null || echo "")

        if [ -n "$learnings_rows" ]; then
            ctx="${ctx}
### Recent Learnings
"
            while IFS= read -r row; do
                [ -z "$row" ] && continue
                l_content=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
                l_category=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
                l_created=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')

                # Truncate long learnings for context budget
                if [ ${#l_content} -gt 200 ]; then
                    l_content="${l_content:0:197}..."
                fi

                ctx="${ctx}- [${l_category}] ${l_content}
"
            done <<< "$learnings_rows"
        fi
    fi
fi

# ── Empty DB fallback ────────────────────────────────────────
if [ "$total_in_db" -eq 0 ] 2>/dev/null; then
    ctx="## Recent Memory (frozen snapshot)
<!-- SNAPSHOT_GENERATED_AT: ${snapshot_ts} -->
<!-- No observations recorded yet -->

_No memory observations captured yet. Context will appear after tool usage._
"
fi

# ── Enforce token budget ─────────────────────────────────────
ctx_len=${#ctx}
if [ "$ctx_len" -gt "$MAX_CHARS" ]; then
    # Truncate from the end (older content) with a note
    ctx="${ctx:0:$((MAX_CHARS - 80))}

...truncated (${ctx_len} chars exceeded ${MAX_CHARS} budget)
"
    ctx_len=${#ctx}
fi

# ── Write output ─────────────────────────────────────────────
printf '%s' "$ctx" > "$OUTPUT_FILE"

# ── Log injection stats ──────────────────────────────────────
END_TS=$(date +%s)
duration=$(( END_TS - START_TS ))
est_tokens=$(( (ctx_len + 3) / 4 ))

alba_log INFO inject-context "OK observations=${total_in_db} chars=${ctx_len} est_tokens=${est_tokens} duration=${duration}s"

exit 0
