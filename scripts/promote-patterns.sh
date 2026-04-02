#!/usr/bin/env bash
# promote-patterns.sh — Detect recurring learnings and promote to Claude Code rules
# Usage: bash scripts/promote-patterns.sh [--db PATH] [--rules-dir PATH]
#
# Scans learnings table for clusters of 3+ similar entries (by FTS5 term overlap
# within the same category), then generates auto-<slug>.md rule files.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────
ALBA_DIR="${ALBA_DIR:-$HOME/.alba}"
DB_PATH="${ALBA_DIR}/alba-memory.db"
RULES_DIR="$HOME/.claude/rules"
LOG_DIR="${ALBA_DIR}/logs"
LOG_FILE="${LOG_DIR}/pattern-promotion.log"
MIN_CLUSTER_SIZE=3
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse flags ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)       DB_PATH="$2"; shift 2 ;;
        --rules-dir) RULES_DIR="$2"; shift 2 ;;
        *)          echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# ── Logging ──────────────────────────────────────────────────
mkdir -p "$LOG_DIR" "$RULES_DIR"

log() {
    local msg
    msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

# ── Preflight checks ────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
    log "SKIP: Database not found at $DB_PATH"
    exit 0
fi

row_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM learnings;" 2>/dev/null || echo "0")
if [[ "$row_count" -eq 0 ]]; then
    log "SKIP: No learnings in database"
    exit 0
fi

# ── Apply migration 003 if needed ────────────────────────────
schema_version=$(sqlite3 "$DB_PATH" "SELECT value FROM meta WHERE key = 'schema_version';" 2>/dev/null || echo "0")
if [[ "$schema_version" -lt 3 ]]; then
    log "Applying migration 003-promoted-rules.sql"
    sqlite3 "$DB_PATH" < "${SCRIPT_DIR}/../migrations/003-promoted-rules.sql"
fi

# ── Stopwords ────────────────────────────────────────────────
STOPWORDS="a an the is it in on at to for of and or but not with from by as was were be been has had have do does did will would could should can may this that these those i we you they he she"

strip_stopwords() {
    local text="$1"
    # Lowercase, strip non-alnum (keep spaces), collapse whitespace
    local cleaned
    cleaned=$(echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]/ /g' | tr -s ' ')
    local result=""
    for word in $cleaned; do
        local is_stop=0
        for sw in $STOPWORDS; do
            if [[ "$word" == "$sw" ]]; then
                is_stop=1
                break
            fi
        done
        if [[ "$is_stop" -eq 0 && ${#word} -gt 1 ]]; then
            result="${result} ${word}"
        fi
    done
    echo "$result" | sed 's/^ //'
}

# Extract top N significant terms by frequency
top_terms() {
    local text="$1"
    local n="${2:-3}"
    local stripped
    stripped=$(strip_stopwords "$text")
    # Count word frequency, take top N
    echo "$stripped" | tr ' ' '\n' | sort | uniq -c | sort -rn | head -"$n" | awk '{print $2}'
}

# ── Slug generation ──────────────────────────────────────────
make_slug() {
    local text="$1"
    echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr -s ' ' | sed 's/ /-/g' | cut -c1-50
}

# ── Main logic ───────────────────────────────────────────────
patterns_detected=0
rules_created=0
rules_skipped=0

# Get distinct categories
categories=$(sqlite3 "$DB_PATH" "SELECT DISTINCT category FROM learnings WHERE category IS NOT NULL AND category != '';")

if [[ -z "$categories" ]]; then
    log "SKIP: No categorized learnings found"
    exit 0
fi

# Track all clusters across categories to avoid double-processing
declare -a all_cluster_ids=()

while IFS= read -r category; do
    [[ -z "$category" ]] && continue

    # Get all learnings in this category
    learning_data=$(sqlite3 -separator '|||' "$DB_PATH" \
        "SELECT id, content FROM learnings WHERE category = '$(echo "$category" | sed "s/'/''/g")' ORDER BY id;")

    [[ -z "$learning_data" ]] && continue

    # Build arrays of IDs and content
    declare -a ids=()
    declare -a contents=()
    while IFS= read -r row; do
        [[ -z "$row" ]] && continue
        local_id=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
        local_content=$(echo "$row" | awk -F'\\|\\|\\|' '{$1=""; print substr($0,2)}')
        ids+=("$local_id")
        contents+=("$local_content")
    done <<< "$learning_data"

    count=${#ids[@]}
    if [[ "$count" -lt "$MIN_CLUSTER_SIZE" ]]; then
        continue
    fi

    # Build adjacency via FTS5 term overlap
    # matches[i] = space-separated list of indices that i matched
    declare -a matches=()
    for ((i=0; i<count; i++)); do
        terms=$(top_terms "${contents[$i]}" 3)
        if [[ -z "$terms" ]]; then
            matches+=("")
            continue
        fi

        # Build FTS5 MATCH query: term1 OR term2 OR term3
        match_expr=""
        while IFS= read -r term; do
            [[ -z "$term" ]] && continue
            if [[ -n "$match_expr" ]]; then
                match_expr="${match_expr} OR ${term}"
            else
                match_expr="${term}"
            fi
        done <<< "$terms"

        # Query FTS5 scoped to this category
        escaped_cat=$(echo "$category" | sed "s/'/''/g")
        fts_hits=$(sqlite3 "$DB_PATH" \
            "SELECT rowid FROM learnings_fts WHERE learnings_fts MATCH '(${match_expr}) AND category:${escaped_cat}';" 2>/dev/null || true)

        matched_indices=""
        while IFS= read -r hit_id; do
            [[ -z "$hit_id" ]] && continue
            for ((j=0; j<count; j++)); do
                if [[ "${ids[$j]}" == "$hit_id" && "$j" -ne "$i" ]]; then
                    matched_indices="${matched_indices} ${j}"
                fi
            done
        done <<< "$fts_hits"

        matches+=("$matched_indices")
    done

    # Transitive closure to form clusters
    declare -a visited=()
    for ((i=0; i<count; i++)); do
        visited+=(0)
    done

    for ((i=0; i<count; i++)); do
        [[ "${visited[$i]}" -eq 1 ]] && continue

        # BFS from node i
        cluster=("$i")
        queue=("$i")
        visited[$i]=1

        while [[ ${#queue[@]} -gt 0 ]]; do
            current="${queue[0]}"
            queue=("${queue[@]:1}")

            for neighbor in ${matches[$current]}; do
                if [[ "${visited[$neighbor]}" -eq 0 ]]; then
                    visited[$neighbor]=1
                    cluster+=("$neighbor")
                    queue+=("$neighbor")
                fi
            done
        done

        if [[ ${#cluster[@]} -ge $MIN_CLUSTER_SIZE ]]; then
            patterns_detected=$((patterns_detected + 1))

            # Collect learning IDs for this cluster
            cluster_learning_ids=""
            for idx in "${cluster[@]}"; do
                if [[ -n "$cluster_learning_ids" ]]; then
                    cluster_learning_ids="${cluster_learning_ids},${ids[$idx]}"
                else
                    cluster_learning_ids="${ids[$idx]}"
                fi
            done

            # Check if any of these learning IDs are already promoted
            already_promoted=0
            for idx in "${cluster[@]}"; do
                lid="${ids[$idx]}"
                hit=$(sqlite3 "$DB_PATH" \
                    "SELECT COUNT(*) FROM promoted_rules WHERE ',' || source_learning_ids || ',' LIKE '%,${lid},%';" 2>/dev/null || echo "0")
                if [[ "$hit" -gt 0 ]]; then
                    already_promoted=1
                    break
                fi
            done

            if [[ "$already_promoted" -eq 1 ]]; then
                rules_skipped=$((rules_skipped + 1))
                continue
            fi

            # Generate slug from first learning's content
            slug=$(make_slug "${contents[${cluster[0]}]}")
            if [[ -z "$slug" ]]; then
                slug="pattern-${patterns_detected}"
            fi

            # Build rule markdown content
            rule_content="<!-- auto-promoted -->
# Auto-Promoted Pattern: ${slug}

## Pattern

Recurring pattern detected across ${#cluster[@]} learnings in category '${category}'.

"
            # Synthesize description from cluster content
            for idx in "${cluster[@]}"; do
                rule_content="${rule_content}- ${contents[$idx]}
"
            done

            rule_content="${rule_content}
## Source Learnings

"
            for idx in "${cluster[@]}"; do
                rule_content="${rule_content}- [Learning #${ids[$idx]}] ${contents[$idx]}
"
            done

            rule_content="${rule_content}
## When to Apply

Category: \`${category}\`
"

            # Compute content hash
            content_hash=$(echo -n "$rule_content" | shasum -a 256 | awk '{print $1}')

            # Check idempotency via content_hash
            hash_exists=$(sqlite3 "$DB_PATH" \
                "SELECT COUNT(*) FROM promoted_rules WHERE content_hash = '${content_hash}';" 2>/dev/null || echo "0")
            if [[ "$hash_exists" -gt 0 ]]; then
                rules_skipped=$((rules_skipped + 1))
                continue
            fi

            # Write rule file
            rule_file="${RULES_DIR}/auto-${slug}.md"
            echo -n "$rule_content" > "$rule_file"

            # Insert into promoted_rules
            now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
            sqlite3 "$DB_PATH" \
                "INSERT INTO promoted_rules (rule_name, source_learning_ids, content_hash, created_at) VALUES ('auto-${slug}', '${cluster_learning_ids}', '${content_hash}', '${now}');"

            rules_created=$((rules_created + 1))
            log "PROMOTED: auto-${slug}.md (${#cluster[@]} learnings: ${cluster_learning_ids})"
        fi
    done

    # Clean up arrays for next category
    unset ids contents matches visited
done <<< "$categories"

log "SUMMARY: patterns=${patterns_detected} created=${rules_created} skipped=${rules_skipped}"
echo "Pattern promotion complete: ${rules_created} rule(s) created, ${rules_skipped} skipped"
