#!/bin/bash
# ==========================================================
# Alba Army — Graceful Shutdown
# Runs at 05:30 — signals agents to wrap up, waits, force-kills
# Usage: army-shutdown.sh
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
ACTIVE_DIR="${ARMY_BASE}/active"
FAILED_DIR="${ARMY_BASE}/failed"
QUEUE_DIR="${ARMY_BASE}/queue"
LOG_FILE="${ARMY_BASE}/logs/army-shutdown.log"
LOG_TAG="army-shutdown"
DISPATCH_PIDFILE="/tmp/army-dispatch.pid"

GRACE_PERIOD_SEC=300  # 5 minutes

# ---- Ensure directories ----
mkdir -p "$FAILED_DIR" "${ARMY_BASE}/logs"

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "$msg" >> "$LOG_FILE"
}

# ---- Task helpers ----
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

# ==== Shutdown sequence ====
log "========================================="
log "ARMY SHUTDOWN INITIATED"
log "========================================="

# ---- Step 1: Stop the dispatcher ----
log "Step 1: Stopping dispatcher..."
if [ -f "$DISPATCH_PIDFILE" ]; then
    dpid=$(cat "$DISPATCH_PIDFILE" 2>/dev/null)
    if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
        kill "$dpid" 2>/dev/null
        rm -f "$DISPATCH_PIDFILE"
        log "Dispatcher stopped (PID ${dpid})"
    else
        rm -f "$DISPATCH_PIDFILE"
        log "Dispatcher not running (cleaned stale PID)"
    fi
else
    log "Dispatcher PID file not found"
fi

# ---- Step 2: Drain queue — move remaining queued tasks to failed ----
log "Step 2: Draining queue..."
DRAINED=0
for task_file in "${QUEUE_DIR}"/*.json; do
    [ -f "$task_file" ] || continue
    local_filename=$(basename "$task_file")
    task_set "$task_file" "status" "failed"
    task_set "$task_file" "completed_at" "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    task_set "$task_file" "error" "Army shutdown before dispatch — task not started"
    mv "$task_file" "${FAILED_DIR}/${local_filename}"
    DRAINED=$((DRAINED + 1))
done
log "Drained ${DRAINED} queued task(s)"

# ---- Step 3: List active agents ----
ACTIVE_TASKS=()
ACTIVE_SESSIONS=()
for task_file in "${ACTIVE_DIR}"/*.json; do
    [ -f "$task_file" ] || continue
    task_id=$(task_get "$task_file" "id")
    ACTIVE_TASKS+=("$task_file")
    ACTIVE_SESSIONS+=("army-${task_id}")
done

ACTIVE_COUNT=${#ACTIVE_TASKS[@]}
log "Step 3: ${ACTIVE_COUNT} active task(s) found"

if [ "$ACTIVE_COUNT" -eq 0 ]; then
    log "No active tasks — shutdown complete"
    log "========================================="
    exit 0
fi

# ---- Step 4: Signal wrap-up (send SIGTERM via tmux) ----
log "Step 4: Signaling ${ACTIVE_COUNT} agent(s) to wrap up..."
for session_name in "${ACTIVE_SESSIONS[@]}"; do
    if tmux has-session -t "$session_name" 2>/dev/null; then
        # Send Ctrl+C to give the agent a chance to save state
        tmux send-keys -t "$session_name" C-c 2>/dev/null
        log "Sent SIGINT to ${session_name}"
    fi
done

# ---- Step 5: Grace period ----
log "Step 5: Grace period (${GRACE_PERIOD_SEC}s / $((GRACE_PERIOD_SEC / 60))m)..."
GRACE_START=$(date +%s)
GRACE_CHECK_INTERVAL=30  # Check every 30 seconds

while true; do
    ELAPSED=$(( $(date +%s) - GRACE_START ))
    if [ "$ELAPSED" -ge "$GRACE_PERIOD_SEC" ]; then
        break
    fi

    # Check if all sessions have ended naturally
    ALL_DONE=true
    for session_name in "${ACTIVE_SESSIONS[@]}"; do
        if tmux has-session -t "$session_name" 2>/dev/null; then
            ALL_DONE=false
            break
        fi
    done

    if [ "$ALL_DONE" = true ]; then
        log "All agents finished gracefully within grace period ($((ELAPSED))s)"
        break
    fi

    REMAINING=$(( (GRACE_PERIOD_SEC - ELAPSED) / 60 ))
    log "Grace period: ${REMAINING}m remaining, waiting..."
    sleep "$GRACE_CHECK_INTERVAL"
done

# ---- Step 6: Force-kill remaining ----
log "Step 6: Force-killing remaining agents..."
KILLED=0
for i in "${!ACTIVE_TASKS[@]}"; do
    task_file="${ACTIVE_TASKS[$i]}"
    session_name="${ACTIVE_SESSIONS[$i]}"

    [ -f "$task_file" ] || continue

    task_id=$(task_get "$task_file" "id")
    filename=$(basename "$task_file")

    if tmux has-session -t "$session_name" 2>/dev/null; then
        tmux kill-session -t "$session_name" 2>/dev/null
        log "FORCE-KILLED: ${session_name}"
        KILLED=$((KILLED + 1))
    fi

    # Capture partial results
    local partial_output=""
    if [ -f "${ACTIVE_DIR}/.stdout-${task_id}.log" ]; then
        partial_output=$(tail -c 2000 "${ACTIVE_DIR}/.stdout-${task_id}.log" 2>/dev/null)
    fi

    # Update task and move to failed
    python3 -c "
import json, os
with open('${task_file}') as f:
    task = json.load(f)
task['status'] = 'failed'
task['completed_at'] = '$(date '+%Y-%m-%dT%H:%M:%S%z')'
task['error'] = 'Army shutdown — agent force-killed after grace period'
# Save partial results if available
stdout_path = '${ACTIVE_DIR}/.stdout-${task_id}.log'
if os.path.exists(stdout_path):
    with open(stdout_path) as sf:
        content = sf.read()[-2000:]
    task['result'] = {'status': 'partial', 'summary': 'Interrupted by army shutdown', 'partial_output': content[:500]}
with open('${task_file}', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False, default=str)
" 2>/dev/null

    mv "$task_file" "${FAILED_DIR}/${filename}" 2>/dev/null

    # Cleanup temp files
    rm -f "${ACTIVE_DIR}/.heartbeat-${task_id}" \
          "${ACTIVE_DIR}/.exitcode-${task_id}" \
          "${ACTIVE_DIR}/.stdout-${task_id}.log" \
          "${ACTIVE_DIR}/.stderr-${task_id}.log" \
          "${ACTIVE_DIR}/.result-${task_id}.json" \
          2>/dev/null
done

log "Force-killed ${KILLED} agent(s)"

# ---- Step 7: Final cleanup ----
log "Step 7: Final cleanup..."
# Kill any orphan army-* tmux sessions
ORPHANS=$(tmux list-sessions 2>/dev/null | grep '^army-' | awk -F: '{print $1}')
for orphan in $ORPHANS; do
    tmux kill-session -t "$orphan" 2>/dev/null
    log "Cleaned orphan session: ${orphan}"
done

# Clean up any leftover temp files in active/
rm -f "${ACTIVE_DIR}"/.heartbeat-* \
      "${ACTIVE_DIR}"/.exitcode-* \
      "${ACTIVE_DIR}"/.stdout-* \
      "${ACTIVE_DIR}"/.stderr-* \
      "${ACTIVE_DIR}"/.result-* \
      "${ACTIVE_DIR}"/.prompt-* \
      2>/dev/null

log "========================================="
log "ARMY SHUTDOWN COMPLETE"
log "  Drained:     ${DRAINED} queued task(s)"
log "  Active:      ${ACTIVE_COUNT} task(s) at shutdown"
log "  Force-killed: ${KILLED} agent(s)"
log "========================================="

exit 0
