#!/usr/bin/env bash
# alba-consolidate.sh — Nightly memory consolidation
#
# Three-gate trigger → Four-phase consolidation → Cron-safe
#
# Gates:
#   1. 24h since last consolidation
#   2. Minimum 5 sessions since last consolidation
#   3. flock-based exclusive lock
#
# Phases:
#   1. Orient  — read MEMORY.md, count observations by type
#   2. Gather  — query recent observations, detect contradictions
#   3. Consolidate — append new insights, merge duplicates, fix dates
#   4. Prune   — enforce 200-line cap, drop stale low-value entries
#
# Usage:
#   bash scripts/alba-consolidate.sh [--force]
#   --force  skips gate 1 (24h) and gate 2 (5 sessions) checks

set -euo pipefail

# ── Configuration ────────────────────────────────────────────
ALBA_DIR="${ALBA_DIR:-$HOME/.alba}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${ALBA_DIR}/alba-memory.db"
MEMORY_FILE="${ALBA_DIR}/MEMORY.md"
LAST_CONSOLIDATION_FILE="${ALBA_DIR}/last-consolidation"
LOCK_FILE="${ALBA_DIR}/consolidation.lk"
LOG_DIR="${ALBA_DIR}/logs"
LOG_FILE="${LOG_DIR}/consolidation.log"
MAX_LINES=200
MAX_AGE_DAYS=90
MIN_SESSIONS=5
MIN_INTERVAL_SECONDS=86400  # 24h

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# ── Shared logging ───────────────────────────────────────────
source "$(dirname "$0")/alba-log.sh"

log() {
    alba_log INFO consolidation "$1"
}

die() {
    alba_log ERROR consolidation "$1"
    echo "ERROR: $1" >&2
    exit 1
}

ensure_dirs() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$(dirname "$MEMORY_FILE")"
}

# ── Gate 1: 24h since last consolidation ─────────────────────
check_interval() {
    if [[ "$FORCE" == "true" ]]; then
        log "Gate 1: SKIPPED (--force)"
        return 0
    fi

    if [[ ! -f "$LAST_CONSOLIDATION_FILE" ]]; then
        log "Gate 1: PASS (no prior consolidation)"
        return 0
    fi

    local last_ts
    last_ts=$(cat "$LAST_CONSOLIDATION_FILE" 2>/dev/null || echo "0")
    local now_ts
    now_ts=$(date +%s)
    local elapsed=$((now_ts - last_ts))

    if [[ "$elapsed" -lt "$MIN_INTERVAL_SECONDS" ]]; then
        local remaining=$(( (MIN_INTERVAL_SECONDS - elapsed) / 3600 ))
        log "Gate 1: FAIL — last consolidation ${elapsed}s ago, need ${MIN_INTERVAL_SECONDS}s (${remaining}h remaining)"
        echo "Skipping: last consolidation was $((elapsed / 3600))h ago (need 24h)"
        return 1
    fi

    log "Gate 1: PASS (${elapsed}s since last consolidation)"
    return 0
}

# ── Gate 2: Minimum 5 sessions since last consolidation ──────
check_session_count() {
    if [[ "$FORCE" == "true" ]]; then
        log "Gate 2: SKIPPED (--force)"
        return 0
    fi

    if [[ ! -f "$DB_PATH" ]]; then
        log "Gate 2: FAIL — database not found at $DB_PATH"
        echo "Skipping: memory database not found"
        return 1
    fi

    local since_ts="1970-01-01T00:00:00"
    if [[ -f "$LAST_CONSOLIDATION_FILE" ]]; then
        local epoch
        epoch=$(cat "$LAST_CONSOLIDATION_FILE" 2>/dev/null || echo "0")
        # Convert epoch to ISO-8601 for SQLite comparison
        since_ts=$(date -r "$epoch" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "1970-01-01T00:00:00")
    fi

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions WHERE started_at > '$since_ts';" 2>/dev/null || echo "0")

    if [[ "$count" -lt "$MIN_SESSIONS" ]]; then
        log "Gate 2: FAIL — only $count sessions since last consolidation (need $MIN_SESSIONS)"
        echo "Skipping: only $count sessions since last consolidation (need $MIN_SESSIONS)"
        return 1
    fi

    log "Gate 2: PASS ($count sessions since last consolidation)"
    return 0
}

# ── Gate 3: Exclusive lock ───────────────────────────────────
# Lock is acquired via the exec block at the bottom of main()

# ── Phase 1: Orient ──────────────────────────────────────────
phase_orient() {
    log "Phase 1: Orient"

    # Count current MEMORY.md lines
    local mem_lines=0
    if [[ -f "$MEMORY_FILE" ]]; then
        mem_lines=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
    fi
    log "  MEMORY.md: $mem_lines lines"

    # Count observations by type
    if [[ -f "$DB_PATH" ]]; then
        local type_counts
        type_counts=$(sqlite3 "$DB_PATH" "SELECT type, COUNT(*) FROM observations GROUP BY type ORDER BY COUNT(*) DESC;" 2>/dev/null || echo "(no data)")
        log "  Observation counts: $(echo "$type_counts" | tr '\n' ', ')"
    else
        log "  Database not found — skipping observation counts"
    fi
}

# ── Phase 2: Gather ──────────────────────────────────────────
# Collects recent observations and detects potential contradictions
# Outputs gathered data to a temp file for Phase 3
phase_gather() {
    log "Phase 2: Gather"

    local gather_file="$1"
    local since_ts="1970-01-01T00:00:00"
    if [[ -f "$LAST_CONSOLIDATION_FILE" ]]; then
        local epoch
        epoch=$(cat "$LAST_CONSOLIDATION_FILE" 2>/dev/null || echo "0")
        since_ts=$(date -r "$epoch" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "1970-01-01T00:00:00")
    fi

    if [[ ! -f "$DB_PATH" ]]; then
        log "  No database — nothing to gather"
        return 0
    fi

    # Query recent observations (title + type + narrative + created_at)
    # Use ||| as delimiter since titles/narratives may contain pipes
    local obs_count
    obs_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM observations WHERE created_at > '$since_ts';" 2>/dev/null || echo "0")
    log "  Found $obs_count new observations since last consolidation"

    if [[ "$obs_count" -eq 0 ]]; then
        return 0
    fi

    # Export recent observations for consolidation
    sqlite3 -separator '|||' "$DB_PATH" \
        "SELECT type, title, COALESCE(narrative,''), created_at
         FROM observations
         WHERE created_at > '$since_ts'
         ORDER BY created_at ASC;" > "$gather_file" 2>/dev/null || true

    local exported
    exported=$(wc -l < "$gather_file" | tr -d ' ')
    log "  Exported $exported observations to gather file"

    # Detect potential contradictions: observations with same title but different narrative
    local contradictions
    contradictions=$(sqlite3 "$DB_PATH" \
        "SELECT title, COUNT(DISTINCT narrative) as narr_count
         FROM observations
         WHERE narrative IS NOT NULL AND narrative != ''
         GROUP BY title
         HAVING narr_count > 1
         LIMIT 10;" 2>/dev/null || echo "")

    if [[ -n "$contradictions" ]]; then
        log "  Potential contradictions found:"
        while IFS='|' read -r title count; do
            log "    '$title' has $count different narratives"
        done <<< "$contradictions"
    else
        log "  No contradictions detected"
    fi
}

# ── Phase 3: Consolidate ─────────────────────────────────────
# Append new insights, merge duplicates, convert relative dates
phase_consolidate() {
    log "Phase 3: Consolidate"

    local gather_file="$1"

    if [[ ! -s "$gather_file" ]]; then
        log "  Nothing to consolidate"
        return 0
    fi

    # Initialize MEMORY.md if it doesn't exist
    if [[ ! -f "$MEMORY_FILE" ]]; then
        cat > "$MEMORY_FILE" <<'EOF'
# Memory Index

## Identity & Preferences

## Feedback & Rules

## Projects & Context

## References
EOF
        log "  Created initial MEMORY.md"
    fi

    # Build a set of existing titles for dedup
    local existing_titles_file
    existing_titles_file=$(mktemp)
    grep -E '^\s*-\s+' "$MEMORY_FILE" 2>/dev/null | sed 's/^[[:space:]]*-[[:space:]]*//' | sed 's/[[:space:]]*$//' > "$existing_titles_file" || true

    local added=0
    local skipped_dup=0
    local today
    today=$(date '+%Y-%m-%d')

    # Parse with awk for correct multi-char delimiter (IFS='|||' treats each | individually)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        type=$(echo "$line" | awk -F'\\|\\|\\|' '{print $1}')
        title=$(echo "$line" | awk -F'\\|\\|\\|' '{print $2}')
        narrative=$(echo "$line" | awk -F'\\|\\|\\|' '{print $3}')
        created_at=$(echo "$line" | awk -F'\\|\\|\\|' '{print $4}')

        # Strip whitespace
        type=$(echo "$type" | xargs)
        title=$(echo "$title" | xargs)

        [[ -z "$title" ]] && continue

        # Dedup: skip if this title already exists in MEMORY.md
        if grep -qFx "$title" "$existing_titles_file" 2>/dev/null; then
            skipped_dup=$((skipped_dup + 1))
            continue
        fi

        # Convert relative dates in title/narrative to absolute
        # (simple heuristic: replace "today" with actual date)
        title=$(echo "$title" | sed "s/\btoday\b/$today/gi")
        title=$(echo "$title" | sed "s/\byesterday\b/$(date -v-1d '+%Y-%m-%d' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || echo 'yesterday')/gi")

        # Determine which section to append to based on type
        local section=""
        case "$type" in
            decision|discovery)  section="## Projects & Context" ;;
            bugfix|refactor)     section="## References" ;;
            feature|change)      section="## Projects & Context" ;;
            *)                   section="## References" ;;
        esac

        # Format the entry with date
        local date_prefix
        date_prefix=$(echo "$created_at" | cut -c1-10)  # YYYY-MM-DD
        local entry="- ${title} (${date_prefix})"

        # Append after the section header
        if grep -qF "$section" "$MEMORY_FILE" 2>/dev/null; then
            # Use awk to insert after the section header
            awk -v section="$section" -v entry="$entry" '
                $0 == section { print; print entry; next }
                { print }
            ' "$MEMORY_FILE" > "${MEMORY_FILE}.tmp"
            mv "${MEMORY_FILE}.tmp" "$MEMORY_FILE"
        else
            # Section doesn't exist — append at end
            echo "" >> "$MEMORY_FILE"
            echo "$section" >> "$MEMORY_FILE"
            echo "$entry" >> "$MEMORY_FILE"
        fi

        added=$((added + 1))
        echo "$title" >> "$existing_titles_file"

    done < "$gather_file"

    rm -f "$existing_titles_file"

    log "  Added $added new entries, skipped $skipped_dup duplicates"
}

# ── Phase 4: Prune ───────────────────────────────────────────
# Keep MEMORY.md under 200 lines, remove stale entries
phase_prune() {
    log "Phase 4: Prune"

    if [[ ! -f "$MEMORY_FILE" ]]; then
        log "  No MEMORY.md to prune"
        return 0
    fi

    local line_count
    line_count=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
    log "  Current line count: $line_count"

    # Remove entries older than 90 days (entries with date suffix like (2025-01-15))
    local cutoff_date
    cutoff_date=$(date -v-${MAX_AGE_DAYS}d '+%Y-%m-%d' 2>/dev/null || date -d "${MAX_AGE_DAYS} days ago" '+%Y-%m-%d' 2>/dev/null || echo "")

    if [[ -n "$cutoff_date" ]]; then
        local pruned_age=0
        local temp_file
        temp_file=$(mktemp)

        while IFS= read -r line; do
            # Check if line has a date suffix like (2025-01-15)
            if echo "$line" | grep -qE '\([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
                local entry_date
                entry_date=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}\)$' | tr -d ')')
                if [[ "$entry_date" < "$cutoff_date" ]]; then
                    pruned_age=$((pruned_age + 1))
                    continue  # skip this line (prune it)
                fi
            fi
            echo "$line" >> "$temp_file"
        done < "$MEMORY_FILE"

        if [[ "$pruned_age" -gt 0 ]]; then
            mv "$temp_file" "$MEMORY_FILE"
            log "  Pruned $pruned_age entries older than ${MAX_AGE_DAYS} days (before $cutoff_date)"
        else
            rm -f "$temp_file"
            log "  No entries older than ${MAX_AGE_DAYS} days to prune"
        fi
    fi

    # Enforce 200-line cap — remove oldest dated entries from bottom
    line_count=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
    if [[ "$line_count" -gt "$MAX_LINES" ]]; then
        local excess=$((line_count - MAX_LINES))
        log "  Over limit by $excess lines — truncating oldest entries"

        # Strategy: remove dated bullet lines from the end of the file first
        local temp_file
        temp_file=$(mktemp)
        local removed=0

        # Read file in reverse, skip dated entries until we've removed enough
        tac "$MEMORY_FILE" | while IFS= read -r line; do
            if [[ "$removed" -lt "$excess" ]] && echo "$line" | grep -qE '^\s*-.*\([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
                removed=$((removed + 1))
                continue
            fi
            echo "$line"
        done | tac > "$temp_file"

        mv "$temp_file" "$MEMORY_FILE"
        local new_count
        new_count=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
        log "  Truncated to $new_count lines"
    else
        log "  Within limit ($line_count / $MAX_LINES lines)"
    fi
}

# ── Main ─────────────────────────────────────────────────────
main() {
    ensure_dirs

    log "=== Consolidation started ==="

    # Gate 1: interval check
    if ! check_interval; then
        log "=== Consolidation skipped (gate 1) ==="
        exit 0
    fi

    # Gate 2: session count
    if ! check_session_count; then
        log "=== Consolidation skipped (gate 2) ==="
        exit 0
    fi

    # Gate 3: exclusive lock (mkdir-based, POSIX-portable)
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        # Check for stale lock (older than 1 hour)
        if [[ -d "$LOCK_FILE" ]]; then
            local lock_age
            lock_age=$(( $(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo "0") ))
            if [[ "$lock_age" -gt 3600 ]]; then
                log "Gate 3: Removing stale lock (age: ${lock_age}s)"
                rmdir "$LOCK_FILE" 2>/dev/null || true
                mkdir "$LOCK_FILE" 2>/dev/null || true
            else
                log "Gate 3: FAIL — another consolidation is running (lock age: ${lock_age}s)"
                echo "Skipping: another consolidation is already running"
                log "=== Consolidation skipped (gate 3) ==="
                exit 0
            fi
        fi
    fi
    # Clean up lock on exit
    trap 'rmdir "$LOCK_FILE" 2>/dev/null; rm -f "${gather_file:-}"' EXIT
    log "Gate 3: PASS (lock acquired)"

    # Create temp file for gather phase
    local gather_file
    gather_file=$(mktemp)

    # Execute four phases
    phase_orient
    phase_gather "$gather_file"
    phase_consolidate "$gather_file"
    phase_prune

    # Phase 5: Pattern promotion
    log "Phase 5: Pattern promotion"
    bash "$SCRIPT_DIR/promote-patterns.sh" >> "$LOG_FILE" 2>&1 || log "  Pattern promotion failed (non-fatal)"

    # Update last-consolidation timestamp
    date +%s > "$LAST_CONSOLIDATION_FILE"
    log "Updated last-consolidation timestamp"

    log "=== Consolidation completed successfully ==="
    echo "Consolidation complete"
}

main "$@"
