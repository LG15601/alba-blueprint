#!/usr/bin/env bash
# extract-skills.sh — Auto-extract skills from successful multi-step session workflows
# Usage: bash scripts/extract-skills.sh [--db PATH] [--skills-dir PATH]
#
# Detects qualifying workflows (5+ observations with files_modified, no error-ending)
# and generates SKILL.md files. Security-scans via memory_guard.py before deployment.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────
ALBA_DIR="${ALBA_DIR:-$HOME/.alba}"
DB_PATH="${ALBA_DIR}/alba-memory.db"
SKILLS_DIR="$HOME/.claude/skills"
LOG_DIR="${ALBA_DIR}/logs"
LOG_FILE="${LOG_DIR}/extract-skills.log"
MIN_OBSERVATIONS=5
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Parse flags ──────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)         DB_PATH="$2"; shift 2 ;;
        --skills-dir) SKILLS_DIR="$2"; shift 2 ;;
        *)            echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# ── Logging ──────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

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

# ── Apply migration 004 if needed ────────────────────────────
schema_version=$(sqlite3 "$DB_PATH" "SELECT value FROM meta WHERE key = 'schema_version';" 2>/dev/null || echo "0")
if [[ "$schema_version" -lt 4 ]]; then
    log "Applying migration 004-extracted-skills.sql"
    sqlite3 "$DB_PATH" < "${SCRIPT_DIR}/../migrations/004-extracted-skills.sql"
fi

# ── Get current (most recent) session ID ─────────────────────
session_id=$(sqlite3 "$DB_PATH" "SELECT id FROM sessions ORDER BY started_at DESC LIMIT 1;" 2>/dev/null || echo "")
if [[ -z "$session_id" ]]; then
    log "SKIP: No sessions found in database"
    exit 0
fi

log "Processing session: $session_id"

# ── Query observations for this session ──────────────────────
total_obs=$(sqlite3 "$DB_PATH" \
    "SELECT COUNT(*) FROM observations WHERE session_id = '$(echo "$session_id" | sed "s/'/''/g")';" 2>/dev/null || echo "0")

if [[ "$total_obs" -lt "$MIN_OBSERVATIONS" ]]; then
    log "SKIP: Session has $total_obs observations (need >= $MIN_OBSERVATIONS)"
    exit 0
fi

# ── Error-ending check: last 3+ observations are all 'bugfix' type ─
escaped_sid=$(echo "$session_id" | sed "s/'/''/g")
tail_count=3
tail_types=$(sqlite3 "$DB_PATH" \
    "SELECT type FROM observations WHERE session_id = '${escaped_sid}' ORDER BY created_at DESC LIMIT ${tail_count};")

all_bugfix=true
bugfix_count=0
while IFS= read -r obs_type; do
    [[ -z "$obs_type" ]] && continue
    bugfix_count=$((bugfix_count + 1))
    if [[ "$obs_type" != "bugfix" ]]; then
        all_bugfix=false
    fi
done <<< "$tail_types"

if [[ "$all_bugfix" == true && "$bugfix_count" -ge "$tail_count" ]]; then
    log "SKIP: Session ends with ${bugfix_count} consecutive bugfix observations (error-ending)"
    exit 0
fi

# ── Collect observations with non-empty files_modified ───────
# files_modified is a JSON array — non-empty means length > 0 and not null/empty string
obs_with_files=$(sqlite3 -separator '|||' "$DB_PATH" \
    "SELECT id, title, files_modified FROM observations
     WHERE session_id = '${escaped_sid}'
       AND files_modified IS NOT NULL
       AND files_modified != ''
       AND files_modified != '[]'
     ORDER BY created_at;" 2>/dev/null || echo "")

if [[ -z "$obs_with_files" ]]; then
    log "SKIP: No observations with files_modified in session"
    exit 0
fi

# Count qualifying observations
qualifying_count=0
declare -a obs_ids=()
declare -a obs_titles=()
declare -a obs_files=()

while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    local_id=$(echo "$row" | awk -F'\\|\\|\\|' '{print $1}')
    local_title=$(echo "$row" | awk -F'\\|\\|\\|' '{print $2}')
    local_files=$(echo "$row" | awk -F'\\|\\|\\|' '{print $3}')
    obs_ids+=("$local_id")
    obs_titles+=("$local_title")
    obs_files+=("$local_files")
    qualifying_count=$((qualifying_count + 1))
done <<< "$obs_with_files"

if [[ "$qualifying_count" -lt "$MIN_OBSERVATIONS" ]]; then
    log "SKIP: Only $qualifying_count observations with files_modified (need >= $MIN_OBSERVATIONS)"
    exit 0
fi

log "QUALIFYING: $qualifying_count observations with files_modified"

# ── Slug generation ──────────────────────────────────────────
# Collect all file paths, count frequency, take top 3 basenames
all_file_paths=""
for files_json in "${obs_files[@]}"; do
    # Extract paths from JSON array: ["path1","path2"] → path1\npath2
    extracted=$(echo "$files_json" | python3 -c "
import sys, json
try:
    paths = json.load(sys.stdin)
    if isinstance(paths, list):
        for p in paths:
            print(p)
except: pass
" 2>/dev/null || echo "")
    if [[ -n "$extracted" ]]; then
        all_file_paths="${all_file_paths}${extracted}"$'\n'
    fi
done

# Get top 3 most-modified basenames
slug_parts=$(echo "$all_file_paths" | grep -v '^$' | xargs -I{} basename {} 2>/dev/null \
    | sort | uniq -c | sort -rn | head -3 | awk '{print $2}' \
    | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' \
    | paste -sd '-' -)

if [[ -z "$slug_parts" ]]; then
    slug_parts="workflow-$(date +%s)"
fi
slug="auto-${slug_parts}"

log "Generated slug: $slug"

# ── Build SKILL.md content ───────────────────────────────────
# Collect unique file paths
unique_files=$(echo "$all_file_paths" | grep -v '^$' | sort -u)

# Build observation IDs list (comma-separated)
obs_id_list=""
for oid in "${obs_ids[@]}"; do
    if [[ -n "$obs_id_list" ]]; then
        obs_id_list="${obs_id_list},${oid}"
    else
        obs_id_list="${oid}"
    fi
done

# First observation title as description
first_title="${obs_titles[0]}"

skill_content="---
name: ${slug}
description: \"${first_title}\"
user-invocable: false
disable-model-invocation: true
---

# Workflow: ${slug}

Auto-extracted from session workflow.

## Workflow Steps
"

step_num=1
for title in "${obs_titles[@]}"; do
    skill_content="${skill_content}
${step_num}. ${title}"
    step_num=$((step_num + 1))
done

skill_content="${skill_content}

## Files Involved
"

while IFS= read -r fpath; do
    [[ -z "$fpath" ]] && continue
    skill_content="${skill_content}
- \`${fpath}\`"
done <<< "$unique_files"

skill_content="${skill_content}
"

# ── Dedup via content hash ───────────────────────────────────
content_hash=$(echo -n "$skill_content" | shasum -a 256 | awk '{print $1}')

changes=$(sqlite3 "$DB_PATH" \
    "INSERT OR IGNORE INTO extracted_skills (skill_name, source_observation_ids, content_hash, created_at)
     VALUES ('${slug}', '${obs_id_list}', '${content_hash}', '$(date -u '+%Y-%m-%dT%H:%M:%SZ')');
     SELECT changes();")
if [[ "$changes" -eq 0 ]]; then
    log "DEDUP: Skill content hash already exists — skipping"
    exit 0
fi

# ── Security scan via memory_guard.py ────────────────────────
guard_script="${SCRIPT_DIR}/security/memory_guard.py"
if [[ -f "$guard_script" ]]; then
    if ! echo "$skill_content" | python3 "$guard_script" --stdin >/dev/null 2>&1; then
        log "SECURITY: memory_guard.py rejected skill content — skipping deployment"
        exit 0
    fi
    log "SECURITY: Content passed memory_guard.py scan"
else
    log "WARNING: memory_guard.py not found at $guard_script — skipping security scan"
fi

# ── Deploy SKILL.md ──────────────────────────────────────────
skill_dir="${SKILLS_DIR}/${slug}"
if ! mkdir -p "$skill_dir" 2>/dev/null; then
    log "ERROR: Cannot create skills directory $skill_dir — skipping deployment"
    exit 0
fi

echo -n "$skill_content" > "${skill_dir}/SKILL.md"

# Update skill_path in DB
sqlite3 "$DB_PATH" \
    "UPDATE extracted_skills SET skill_path = '${skill_dir}' WHERE content_hash = '${content_hash}';"

log "DEPLOYED: ${skill_dir}/SKILL.md (observations: ${obs_id_list})"
echo "Skill extraction complete: deployed ${slug}"
