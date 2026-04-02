#!/bin/bash
# ==========================================================
# Alba Army — Todo Parser
# Takes raw text (from Telegram), outputs structured task JSON
# Usage: parse-todo.sh "raw text" | parse-todo.sh --stdin
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
QUEUE_DIR="${ARMY_BASE}/queue"
LOG_FILE="${ARMY_BASE}/logs/parse-todo.log"
LOG_TAG="army-parse"

# ---- Ensure directories ----
mkdir -p "$QUEUE_DIR" "${ARMY_BASE}/logs"

# ---- Centralized logging ----
source "$(dirname "$0")/../alba-log.sh"
log() {
    alba_log INFO parse-todo "$1"
}

# ---- Rotate log ----
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 1000 ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "Log rotated"
    fi
}

# ---- Validate config ----
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FATAL: config.json not found at $CONFIG_FILE" >&2
    exit 1
fi

# ---- Read input ----
RAW_INPUT=""
if [ "${1:-}" = "--stdin" ]; then
    RAW_INPUT=$(cat)
elif [ -n "${1:-}" ]; then
    RAW_INPUT="$1"
else
    echo "Usage: parse-todo.sh \"raw text\" | parse-todo.sh --stdin" >&2
    exit 1
fi

if [ -z "$RAW_INPUT" ]; then
    log "ERROR: empty input"
    echo "ERROR: empty input" >&2
    exit 1
fi

log "Parsing todo input (${#RAW_INPUT} chars)"

# ---- Normalize text: lowercase, strip accents for matching ----
normalize() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | \
        sed 'y/àâäéèêëïîôùûüçÀÂÄÉÈÊËÏÎÔÙÛÜÇ/aaaeeeeiioouucAAAEEEEIIOOUUC/'
}

# ---- Category detection ----
detect_category() {
    local text
    text=$(normalize "$1")

    # Check each category's keywords from config (hardcoded for shell perf)
    # Email
    for kw in mail email e-mail envoyer repondre relancer inbox courrier; do
        if echo "$text" | grep -qi "$kw"; then echo "email"; return; fi
    done
    # Prospection
    for kw in prospect lead "client potentiel" outreach demarchage pipeline crm; do
        if echo "$text" | grep -qi "$kw"; then echo "prospection"; return; fi
    done
    # Content
    for kw in article blog post contenu rediger ecrire newsletter social twitter; do
        if echo "$text" | grep -qi "$kw"; then echo "content"; return; fi
    done
    # Code
    for kw in code coder dev developper feature bug fix deployer script api site app; do
        if echo "$text" | grep -qi "$kw"; then echo "code"; return; fi
    done
    # Client
    for kw in client livrable deliverable facture invoice meeting reunion compte-rendu suivi; do
        if echo "$text" | grep -qi "$kw"; then echo "client"; return; fi
    done
    # Research
    for kw in recherche research analyser etudier benchmark veille competitor marche; do
        if echo "$text" | grep -qi "$kw"; then echo "research"; return; fi
    done
    # Personal
    for kw in perso personnel rdv rendez-vous acheter commander rappeler reservation; do
        if echo "$text" | grep -qi "$kw"; then echo "personal"; return; fi
    done

    # Default
    echo "research"
}

# ---- Priority detection ----
detect_priority() {
    local text
    text=$(normalize "$1")

    # P0 — critical
    for kw in urgent critique asap immediatement "tout de suite" blocker bloquant; do
        if echo "$text" | grep -qi "$kw"; then echo "P0"; return; fi
    done
    # P1 — high
    for kw in important prioritaire vite rapidement "des que possible"; do
        if echo "$text" | grep -qi "$kw"; then echo "P1"; return; fi
    done
    # P3 — low
    for kw in "pas presse" "quand tu as le temps" "un jour" bonus optionnel "si possible"; do
        if echo "$text" | grep -qi "$kw"; then echo "P3"; return; fi
    done

    # Default — P2 medium
    echo "P2"
}

# ---- Agent lookup from category ----
get_agent_for_category() {
    local category="$1"
    # Read from config.json using python (available on macOS)
    python3 -c "
import json, sys
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
agent = cfg.get('agents', {}).get('${category}', {})
print(json.dumps({
    'name': agent.get('name', 'agent-research'),
    'model': agent.get('model', 'claude-sonnet-4-20250514'),
    'max_turns': agent.get('max_turns', 30)
}))
" 2>/dev/null || echo '{"name":"agent-research","model":"claude-sonnet-4-20250514","max_turns":30}'
}

# ---- Split input into individual tasks ----
# Supports: numbered lists, bullet points, newline-separated, or single task
split_tasks() {
    local input="$1"
    # Remove leading/trailing whitespace
    input=$(echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Split on common list patterns: "1.", "2.", "-", "*", "•"
    # or newlines if no list markers found
    if echo "$input" | grep -qE '^[[:space:]]*([-*•]|[0-9]+[\.\)])'; then
        # List format: split on list markers
        echo "$input" | sed -E 's/^[[:space:]]*([-*•]|[0-9]+[\.\)])[[:space:]]*//' | grep -v '^[[:space:]]*$'
    elif echo "$input" | grep -qc $'\n' | grep -qv '^0$'; then
        # Multi-line: each non-empty line is a task
        echo "$input" | grep -v '^[[:space:]]*$'
    else
        # Single task
        echo "$input"
    fi
}

# ---- Generate task ID ----
generate_task_id() {
    local ts category seq
    ts=$(date '+%Y%m%d-%H%M%S')
    category="$1"
    seq=$(printf '%04d' "$((RANDOM % 10000))")
    echo "${ts}-${category}-${seq}"
}

# ---- Create task JSON ----
create_task_json() {
    local raw_line="$1"
    local category priority agent_json task_id created_at

    category=$(detect_category "$raw_line")
    priority=$(detect_priority "$raw_line")
    agent_json=$(get_agent_for_category "$category")
    task_id=$(generate_task_id "$category")
    created_at=$(date '+%Y-%m-%dT%H:%M:%S%z')

    # Build JSON with python for proper escaping
    python3 -c "
import json, sys

raw = sys.stdin.read()
agent = json.loads('${agent_json}')

task = {
    'id': '${task_id}',
    'raw_input': raw.strip(),
    'category': '${category}',
    'priority': '${priority}',
    'status': 'queued',
    'agent': agent,
    'created_at': '${created_at}',
    'dispatched_at': None,
    'completed_at': None,
    'retry_count': 0,
    'result': None,
    'error': None,
    'source': 'telegram'
}

print(json.dumps(task, indent=2, ensure_ascii=False, default=str))
" <<< "$raw_line"
}

# ---- Main ----
TASK_COUNT=0
CREATED_FILES=()

while IFS= read -r line; do
    # Skip empty lines
    [ -z "$(echo "$line" | tr -d '[:space:]')" ] && continue

    task_json=$(create_task_json "$line")
    if [ -z "$task_json" ]; then
        log "ERROR: failed to create JSON for line: $line"
        continue
    fi

    # Extract task ID from JSON
    task_id=$(echo "$task_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
    priority=$(echo "$task_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['priority'])")
    category=$(echo "$task_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['category'])")

    # Write to queue with priority prefix for natural sort ordering
    filename="${priority}-${task_id}.json"
    filepath="${QUEUE_DIR}/${filename}"
    echo "$task_json" > "$filepath"

    CREATED_FILES+=("$filepath")
    TASK_COUNT=$((TASK_COUNT + 1))
    log "QUEUED: ${filename} [${category}/${priority}] — ${line:0:80}"
done < <(split_tasks "$RAW_INPUT")

# ---- Summary ----
if [ "$TASK_COUNT" -eq 0 ]; then
    log "WARNING: no tasks extracted from input"
    echo "WARNING: no tasks extracted from input" >&2
    exit 1
fi

log "SUCCESS: ${TASK_COUNT} task(s) queued"
echo "OK: ${TASK_COUNT} task(s) queued in ${QUEUE_DIR}"
for f in "${CREATED_FILES[@]}"; do
    echo "  $(basename "$f")"
done

rotate_log
exit 0
