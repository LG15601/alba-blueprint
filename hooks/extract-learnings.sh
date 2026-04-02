#!/usr/bin/env bash
# Alba — Learning Extraction Hook (Stop)
# Extracts learnings from session observations (bugfix/decision types) and
# ingests entries from ~/logs/learnings.jsonl. Deduplicates via content_hash.
#
# Non-blocking: forks a background writer and returns immediately.
# Fail-open: never blocks session shutdown.

# ── Config ────────────────────────────────────────────────────
DB_PATH="${ALBA_MEMORY_DB:-$HOME/.alba/alba-memory.db}"
LOG_FILE="${HOME}/.alba/logs/extract-learnings.log"
SESSION_ID="${CLAUDE_SESSION_ID:-default-$(date +%Y%m%d)}"
JSONL_FILE="${HOME}/logs/learnings.jsonl"

# Skip if DB doesn't exist (memory not initialized)
[ -f "$DB_PATH" ] || exit 0

# Skip if learnings table doesn't exist (migration not applied)
sqlite3 "$DB_PATH" ".tables" 2>/dev/null | grep -q 'learnings' || exit 0

# ── Fork background writer (parent returns immediately) ───────
(
    mkdir -p "$(dirname "$LOG_FILE")"

    inserted=0
    skipped=0
    jsonl_inserted=0
    jsonl_skipped=0

    # ── SQL-safe escaping ─────────────────────────────────────
    esc() { printf '%s' "$1" | sed "s/'/''/g"; }

    # ── Extract learnings from session observations ───────────
    # Pull bugfix and decision observations — these carry actionable knowledge
    obs_rows=$(sqlite3 -separator '|||' "$DB_PATH" "
        SELECT type, title, COALESCE(subtitle, ''), COALESCE(narrative, '')
        FROM observations
        WHERE session_id = '${SESSION_ID}'
          AND type IN ('bugfix', 'decision')
        ORDER BY created_at ASC;
    " 2>/dev/null || echo "")

    if [ -n "$obs_rows" ]; then
        while IFS= read -r row; do
            [ -z "$row" ] && continue

            o_type=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
            o_title=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
            o_subtitle=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')
            o_narrative=$(echo "$row" | awk -F'\\|\\|\\|' '{print $4}')

            # Build learning content from title + subtitle
            content="${o_title}"
            if [ -n "$o_subtitle" ]; then
                content="${content}: ${o_subtitle}"
            fi

            # Skip empty content
            [ -z "$content" ] && continue

            # Truncate to reasonable size
            if [ ${#content} -gt 1000 ]; then
                content="${content:0:1000}"
            fi

            # Compute content hash for dedup
            content_hash=$(printf '%s' "$content" | shasum -a 256 | cut -d' ' -f1)

            # Map observation type to learning category
            category="$o_type"

            content_safe=$(esc "$content")
            hash_safe=$(esc "$content_hash")
            category_safe=$(esc "$category")

            # INSERT OR IGNORE — content_hash UNIQUE constraint handles dedup
            sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO learnings (
                session_id, source, content, content_hash, category, created_at
            ) VALUES (
                '${SESSION_ID}',
                'observation',
                '${content_safe}',
                '${hash_safe}',
                '${category_safe}',
                datetime('now')
            );" 2>>"$LOG_FILE"

            if [ $? -eq 0 ]; then
                # Check if row was actually inserted (changes() = 0 means dedup)
                changes=$(sqlite3 "$DB_PATH" "SELECT changes();" 2>/dev/null || echo "0")
                if [ "$changes" -gt 0 ]; then
                    inserted=$((inserted + 1))
                else
                    skipped=$((skipped + 1))
                fi
            fi
        done <<< "$obs_rows"
    fi

    # ── Ingest learnings.jsonl ────────────────────────────────
    if [ -f "$JSONL_FILE" ] && [ -s "$JSONL_FILE" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue

            # Extract .learning field (or .content as fallback)
            learning=$(echo "$line" | jq -r '.learning // .content // empty' 2>/dev/null)
            [ -z "$learning" ] && continue

            # Extract optional category
            j_category=$(echo "$line" | jq -r '.category // "general"' 2>/dev/null)

            # Truncate
            if [ ${#learning} -gt 1000 ]; then
                learning="${learning:0:1000}"
            fi

            content_hash=$(printf '%s' "$learning" | shasum -a 256 | cut -d' ' -f1)

            learning_safe=$(esc "$learning")
            hash_safe=$(esc "$content_hash")
            cat_safe=$(esc "$j_category")

            sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO learnings (
                session_id, source, content, content_hash, category, created_at
            ) VALUES (
                '${SESSION_ID}',
                'jsonl',
                '${learning_safe}',
                '${hash_safe}',
                '${cat_safe}',
                datetime('now')
            );" 2>>"$LOG_FILE"

            if [ $? -eq 0 ]; then
                changes=$(sqlite3 "$DB_PATH" "SELECT changes();" 2>/dev/null || echo "0")
                if [ "$changes" -gt 0 ]; then
                    jsonl_inserted=$((jsonl_inserted + 1))
                else
                    jsonl_skipped=$((jsonl_skipped + 1))
                fi
            fi
        done < "$JSONL_FILE"

        # Truncate jsonl after processing to prevent re-ingestion
        : > "$JSONL_FILE"
    fi

    # ── Log stats ─────────────────────────────────────────────
    total_inserted=$((inserted + jsonl_inserted))
    total_skipped=$((skipped + jsonl_skipped))
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] OK session=${SESSION_ID} obs_inserted=${inserted} obs_skipped=${skipped} jsonl_inserted=${jsonl_inserted} jsonl_skipped=${jsonl_skipped} total_inserted=${total_inserted} total_skipped=${total_skipped}" >> "$LOG_FILE"

) > /dev/null 2>&1 &

exit 0
