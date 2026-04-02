#!/bin/bash
# ==========================================================
# Alba Army — Heartbeat Monitor
# Runs every 15 min during army hours (23h-6h)
# Detects stuck agents, retries once, moves failures
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
ACTIVE_DIR="${ARMY_BASE}/active"
QUEUE_DIR="${ARMY_BASE}/queue"
FAILED_DIR="${ARMY_BASE}/failed"
LOG_FILE="${ARMY_BASE}/logs/army-heartbeat.log"
LOG_TAG="army-heartbeat"

# Stuck threshold in seconds (from config: 45 min)
STUCK_THRESHOLD_SEC=$((45 * 60))

# ---- Ensure directories ----
mkdir -p "$ACTIVE_DIR" "$QUEUE_DIR" "$FAILED_DIR" "${ARMY_BASE}/logs"

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "$msg" >> "$LOG_FILE"
}

rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 1000 ]; then
        tail -500 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "Log rotated"
    fi
}

# ---- Read config value ----
config_get_int() {
    python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
keys = '$1'.split('.')
val = cfg
for k in keys:
    val = val[k]
print(int(val))
" 2>/dev/null || echo "$2"
}

# ---- Task field access ----
task_get() {
    local file="$1" field="$2"
    python3 -c "
import json
with open('${file}') as f:
    print(json.load(f).get('${field}', ''))
" 2>/dev/null
}

task_set() {
    local file="$1" field="$2" value="$3"
    python3 -c "
import json
with open('${file}') as f:
    task = json.load(f)
task['${field}'] = '${value}'
with open('${file}', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False, default=str)
" 2>/dev/null
}

# ---- Load stuck threshold from config ----
STUCK_THRESHOLD_MINUTES=$(config_get_int "dispatch.stuck_threshold_minutes" 45)
STUCK_THRESHOLD_SEC=$((STUCK_THRESHOLD_MINUTES * 60))

# ---- Check active tasks for stuck agents ----
check_stuck_agents() {
    local now stuck_count healthy_count
    now=$(date +%s)
    stuck_count=0
    healthy_count=0

    for task_file in "${ACTIVE_DIR}"/*.json; do
        [ -f "$task_file" ] || continue

        local filename task_id session_name
        filename=$(basename "$task_file")
        task_id=$(task_get "$task_file" "id")
        session_name="army-${task_id}"

        # Check heartbeat file
        local heartbeat_file="${ACTIVE_DIR}/.heartbeat-${task_id}"
        local last_heartbeat=0

        if [ -f "$heartbeat_file" ]; then
            last_heartbeat=$(cat "$heartbeat_file" 2>/dev/null || echo "0")
        else
            # No heartbeat file — use dispatched_at
            local dispatched_at
            dispatched_at=$(task_get "$task_file" "dispatched_at")
            if [ -n "$dispatched_at" ]; then
                last_heartbeat=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$dispatched_at" "+%s" 2>/dev/null || echo "0")
            fi
        fi

        local elapsed=$((now - last_heartbeat))

        # Check if tmux session is still alive
        if ! tmux has-session -t "$session_name" 2>/dev/null; then
            # Session gone but task still in active — let dispatch collect it
            log "ORPHAN: ${task_id} — tmux session gone (will be collected by dispatch)"
            healthy_count=$((healthy_count + 1))
            continue
        fi

        if [ "$elapsed" -gt "$STUCK_THRESHOLD_SEC" ]; then
            stuck_count=$((stuck_count + 1))
            local elapsed_min=$((elapsed / 60))
            log "STUCK: ${task_id} — no progress for ${elapsed_min}m (threshold: ${STUCK_THRESHOLD_MINUTES}m)"

            handle_stuck_agent "$task_file" "$task_id" "$session_name"
        else
            healthy_count=$((healthy_count + 1))
            local elapsed_min=$((elapsed / 60))
            log "HEALTHY: ${task_id} — last activity ${elapsed_min}m ago"
        fi
    done

    log "HEARTBEAT: ${healthy_count} healthy, ${stuck_count} stuck"
}

# ---- Handle a stuck agent ----
handle_stuck_agent() {
    local task_file="$1" task_id="$2" session_name="$3"
    local filename
    filename=$(basename "$task_file")

    local retry_count priority max_retries
    retry_count=$(task_get "$task_file" "retry_count")
    retry_count=${retry_count:-0}
    priority=$(task_get "$task_file" "priority")

    max_retries=$(python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
print(cfg.get('priority', {}).get('${priority}', {}).get('retry_limit', 1))
" 2>/dev/null || echo "1")

    # Kill the stuck tmux session
    log "KILLING: stuck session ${session_name}"
    tmux kill-session -t "$session_name" 2>/dev/null

    # Capture partial output if available
    local partial_output=""
    if [ -f "${ACTIVE_DIR}/.stdout-${task_id}.log" ]; then
        partial_output=$(tail -c 1000 "${ACTIVE_DIR}/.stdout-${task_id}.log" 2>/dev/null)
    fi

    if [ "$retry_count" -lt "$max_retries" ]; then
        # Retry: move back to queue
        retry_count=$((retry_count + 1))
        task_set "$task_file" "retry_count" "$retry_count"
        task_set "$task_file" "status" "queued"
        task_set "$task_file" "error" "Stuck after ${STUCK_THRESHOLD_MINUTES}m (retry ${retry_count}/${max_retries})"
        mv "$task_file" "${QUEUE_DIR}/${filename}"
        log "RETRY-STUCK: ${task_id} moved back to queue (attempt ${retry_count}/${max_retries})"
    else
        # Double failure — move to failed
        task_set "$task_file" "status" "failed"
        task_set "$task_file" "completed_at" "$(date '+%Y-%m-%dT%H:%M:%S%z')"
        task_set "$task_file" "error" "Stuck ${max_retries}+ times. Last partial: ${partial_output:0:200}"

        # Save partial result if available
        if [ -n "$partial_output" ]; then
            python3 -c "
import json
with open('${task_file}') as f:
    task = json.load(f)
task['result'] = {'status': 'partial', 'summary': '''${partial_output:0:500}'''}
with open('${task_file}', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False, default=str)
" 2>/dev/null
        fi

        mv "$task_file" "${FAILED_DIR}/${filename}"
        log "FAILED-STUCK: ${task_id} exhausted all retries"
    fi

    # Cleanup temp files
    rm -f "${ACTIVE_DIR}/.heartbeat-${task_id}" \
          "${ACTIVE_DIR}/.exitcode-${task_id}" \
          "${ACTIVE_DIR}/.stdout-${task_id}.log" \
          "${ACTIVE_DIR}/.stderr-${task_id}.log" \
          "${ACTIVE_DIR}/.result-${task_id}.json" \
          "${ACTIVE_DIR}/.prompt-${task_id}.txt" \
          2>/dev/null
}

# ---- System health ----
check_system_health() {
    # Disk
    local disk_pct
    disk_pct=$(df / | awk 'NR==2 {gsub(/%/,""); print $5}')
    if [ "$disk_pct" -ge 95 ]; then
        log "SYSTEM-CRITICAL: Disk at ${disk_pct}%"
    elif [ "$disk_pct" -ge 90 ]; then
        log "SYSTEM-WARNING: Disk at ${disk_pct}%"
    fi

    # Count army tmux sessions
    local army_sessions=0
    army_sessions=$(tmux list-sessions 2>/dev/null | grep -c '^army-' 2>/dev/null || true)
    army_sessions=${army_sessions:-0}
    log "SYSTEM: ${army_sessions} army tmux sessions, disk ${disk_pct}%"
}

# ==== Main ====
log "=== Heartbeat check starting ==="

check_stuck_agents
check_system_health

rotate_log

log "=== Heartbeat check complete ==="
exit 0
