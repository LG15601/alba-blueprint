#!/bin/bash
# ==========================================================
# Alba Army — Main Dispatcher
# Reads queue/, sorts by priority, dispatches agents
# Usage: army-dispatch.sh [--once | --loop]
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
QUEUE_DIR="${ARMY_BASE}/queue"
ACTIVE_DIR="${ARMY_BASE}/active"
COMPLETED_DIR="${ARMY_BASE}/completed"
FAILED_DIR="${ARMY_BASE}/failed"
LOG_FILE="${ARMY_BASE}/logs/army-dispatch.log"
LOG_TAG="army-dispatch"
PIDFILE="/tmp/army-dispatch.pid"
ALBA_PROJECT_DIR="$HOME/AZW/alba-blueprint"

# ---- Ensure directories ----
mkdir -p "$QUEUE_DIR" "$ACTIVE_DIR" "$COMPLETED_DIR" "$FAILED_DIR" "${ARMY_BASE}/logs"

# ---- Logging ----
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    logger -t "$LOG_TAG" "$1" 2>/dev/null
    echo "$msg" >> "$LOG_FILE"
}

rotate_log() {
    if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 2000 ]; then
        tail -1000 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "Log rotated"
    fi
}

# ---- PID management ----
check_already_running() {
    if [ -f "$PIDFILE" ]; then
        local old_pid
        old_pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log "ERROR: Another dispatcher already running (PID $old_pid)"
            exit 1
        fi
    fi
}

write_pid() { echo $$ > "$PIDFILE"; }
cleanup_pid() { rm -f "$PIDFILE"; }

# ---- Config helpers (python3 for JSON) ----
config_get() {
    python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
keys = '$1'.split('.')
val = cfg
for k in keys:
    val = val[k]
print(val)
" 2>/dev/null
}

config_get_int() {
    local val
    val=$(config_get "$1" 2>/dev/null)
    echo "${val:-$2}"
}

# ---- Read dispatch limits from config ----
MAX_CONCURRENT=$(config_get_int "dispatch.max_concurrent_agents" 3)
MAX_TASKS_PER_NIGHT=$(config_get_int "dispatch.max_total_tasks_per_night" 20)
DISPATCH_COOLDOWN=$(config_get_int "dispatch.dispatch_cooldown_seconds" 10)

# ---- Count active agents ----
count_active() {
    local count=0
    for f in "${ACTIVE_DIR}"/*.json; do
        [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
}

# ---- Count dispatched tonight ----
count_dispatched_tonight() {
    local today
    today=$(date '+%Y-%m-%d')
    local count=0
    # Count active + completed + failed with today's date
    for dir in "$ACTIVE_DIR" "$COMPLETED_DIR" "$FAILED_DIR"; do
        for f in "${dir}"/*.json; do
            [ -f "$f" ] || continue
            if python3 -c "
import json, sys
with open('$f') as fh:
    t = json.load(fh)
da = t.get('dispatched_at', '')
if da and da.startswith('${today}'):
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
                count=$((count + 1))
            fi
        done
    done
    echo "$count"
}

# ---- Get task field ----
task_get() {
    local file="$1" field="$2"
    python3 -c "
import json
with open('${file}') as f:
    print(json.load(f).get('${field}', ''))
" 2>/dev/null
}

# ---- Update task field ----
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

# ---- Dispatch a single task ----
dispatch_task() {
    local task_file="$1"
    local filename
    filename=$(basename "$task_file")

    local task_id category priority agent_name agent_model agent_max_turns raw_input
    task_id=$(task_get "$task_file" "id")
    category=$(task_get "$task_file" "category")
    priority=$(task_get "$task_file" "priority")
    raw_input=$(task_get "$task_file" "raw_input")

    # Read agent config from task JSON
    agent_name=$(python3 -c "
import json
with open('${task_file}') as f:
    t = json.load(f)
print(t.get('agent', {}).get('name', 'agent-research'))
" 2>/dev/null)
    agent_model=$(python3 -c "
import json
with open('${task_file}') as f:
    t = json.load(f)
print(t.get('agent', {}).get('model', 'claude-sonnet-4-20250514'))
" 2>/dev/null)
    agent_max_turns=$(python3 -c "
import json
with open('${task_file}') as f:
    t = json.load(f)
print(t.get('agent', {}).get('max_turns', 30))
" 2>/dev/null)

    log "DISPATCHING: ${task_id} [${category}/${priority}] agent=${agent_name}"

    # Move to active/
    local active_file="${ACTIVE_DIR}/${filename}"
    mv "$task_file" "$active_file"
    task_set "$active_file" "status" "active"
    task_set "$active_file" "dispatched_at" "$(date '+%Y-%m-%dT%H:%M:%S%z')"

    # Write a heartbeat file for the agent so heartbeat can track it
    echo "$(date +%s)" > "${ACTIVE_DIR}/.heartbeat-${task_id}"

    # Launch agent in background tmux session
    local session_name="army-${task_id}"

    # Build the prompt and write to temp file (avoids quoting issues with raw input)
    local prompt_file="${ACTIVE_DIR}/.prompt-${task_id}.txt"
    cat > "$prompt_file" << PROMPT
Tu es un agent Alba (${agent_name}) travaillant sur une tache assignee.

TACHE: ${raw_input}

CATEGORIE: ${category}
PRIORITE: ${priority}
TASK_ID: ${task_id}

INSTRUCTIONS:
1. Execute la tache completement
2. Ecris ton resultat dans un fichier JSON temporaire
3. Sois precis, concis et efficace
4. Si tu ne peux pas completer la tache, explique pourquoi clairement

Quand tu as fini, ecris le resultat dans: ${ACTIVE_DIR}/.result-${task_id}.json
Format: {"status": "success|partial|failed", "summary": "...", "details": "...", "deliverables": [...]}
PROMPT

    # Launch via Claude Code in a detached tmux session
    tmux new-session -d -s "$session_name" \
        "cd '${ALBA_PROJECT_DIR}' && cat '${prompt_file}' | claude --dangerously-skip-permissions --model '${agent_model}' --max-turns ${agent_max_turns} -p 2>'${ACTIVE_DIR}/.stderr-${task_id}.log' | tee '${ACTIVE_DIR}/.stdout-${task_id}.log'; echo \$? > '${ACTIVE_DIR}/.exitcode-${task_id}'" \
        2>/dev/null

    if [ $? -eq 0 ]; then
        log "DISPATCHED: ${task_id} in tmux session ${session_name}"
        return 0
    else
        log "ERROR: failed to launch tmux session for ${task_id}"
        # Move back to queue for retry
        mv "$active_file" "$task_file"
        task_set "$task_file" "status" "queued"
        return 1
    fi
}

# ---- Collect results from finished agents ----
collect_results() {
    for task_file in "${ACTIVE_DIR}"/*.json; do
        [ -f "$task_file" ] || continue
        local filename task_id session_name
        filename=$(basename "$task_file")
        task_id=$(task_get "$task_file" "id")
        session_name="army-${task_id}"

        # Check if tmux session is still running
        if tmux has-session -t "$session_name" 2>/dev/null; then
            # Still running — update heartbeat
            echo "$(date +%s)" > "${ACTIVE_DIR}/.heartbeat-${task_id}"
            continue
        fi

        # Session finished — collect result
        local exit_code="1"
        if [ -f "${ACTIVE_DIR}/.exitcode-${task_id}" ]; then
            exit_code=$(cat "${ACTIVE_DIR}/.exitcode-${task_id}" 2>/dev/null || echo "1")
        fi

        local stdout_file="${ACTIVE_DIR}/.stdout-${task_id}.log"
        local result_file="${ACTIVE_DIR}/.result-${task_id}.json"

        if [ "$exit_code" = "0" ]; then
            # Success — read result or use stdout
            local result_summary=""
            if [ -f "$result_file" ]; then
                result_summary=$(cat "$result_file" 2>/dev/null)
            elif [ -f "$stdout_file" ]; then
                # Take last 2000 chars of stdout as summary
                result_summary=$(tail -c 2000 "$stdout_file" 2>/dev/null)
            fi

            task_set "$task_file" "status" "completed"
            task_set "$task_file" "completed_at" "$(date '+%Y-%m-%dT%H:%M:%S%z')"
            # Store result in JSON
            python3 -c "
import json
with open('${task_file}') as f:
    task = json.load(f)
task['status'] = 'completed'
task['completed_at'] = '$(date '+%Y-%m-%dT%H:%M:%S%z')'
# Try to parse result as JSON, fallback to string
try:
    import sys
    result_text = open('${result_file}').read() if __import__('os').path.exists('${result_file}') else open('${stdout_file}').read()[-2000:] if __import__('os').path.exists('${stdout_file}') else 'No output captured'
    try:
        task['result'] = json.loads(result_text)
    except:
        task['result'] = {'summary': result_text[:500], 'status': 'success'}
except Exception as e:
    task['result'] = {'summary': str(e), 'status': 'unknown'}
with open('${task_file}', 'w') as f:
    json.dump(task, f, indent=2, ensure_ascii=False, default=str)
" 2>/dev/null

            mv "$task_file" "${COMPLETED_DIR}/${filename}"
            log "COMPLETED: ${task_id}"
        else
            # Failed
            local error_msg=""
            if [ -f "${ACTIVE_DIR}/.stderr-${task_id}.log" ]; then
                error_msg=$(tail -c 1000 "${ACTIVE_DIR}/.stderr-${task_id}.log" 2>/dev/null)
            fi

            local retry_count
            retry_count=$(task_get "$task_file" "retry_count")
            retry_count=${retry_count:-0}

            # Check retry limit based on priority
            local priority max_retries
            priority=$(task_get "$task_file" "priority")
            max_retries=$(python3 -c "
import json
with open('${CONFIG_FILE}') as f:
    cfg = json.load(f)
print(cfg.get('priority', {}).get('${priority}', {}).get('retry_limit', 1))
" 2>/dev/null || echo "1")

            if [ "$retry_count" -lt "$max_retries" ]; then
                # Retry: move back to queue
                retry_count=$((retry_count + 1))
                task_set "$task_file" "retry_count" "$retry_count"
                task_set "$task_file" "status" "queued"
                task_set "$task_file" "error" "Attempt ${retry_count} failed: ${error_msg:0:200}"
                mv "$task_file" "${QUEUE_DIR}/${filename}"
                log "RETRY: ${task_id} (attempt ${retry_count}/${max_retries})"
            else
                # Move to failed
                task_set "$task_file" "status" "failed"
                task_set "$task_file" "completed_at" "$(date '+%Y-%m-%dT%H:%M:%S%z')"
                task_set "$task_file" "error" "Max retries exceeded. Last error: ${error_msg:0:200}"
                mv "$task_file" "${FAILED_DIR}/${filename}"
                log "FAILED: ${task_id} (exhausted ${max_retries} retries)"
            fi
        fi

        # Cleanup temp files
        rm -f "${ACTIVE_DIR}/.heartbeat-${task_id}" \
              "${ACTIVE_DIR}/.exitcode-${task_id}" \
              "${ACTIVE_DIR}/.stdout-${task_id}.log" \
              "${ACTIVE_DIR}/.stderr-${task_id}.log" \
              "${ACTIVE_DIR}/.result-${task_id}.json" \
              "${ACTIVE_DIR}/.prompt-${task_id}.txt" \
              2>/dev/null
    done
}

# ---- Dispatch loop iteration ----
dispatch_round() {
    # First collect any completed results
    collect_results

    local active_count dispatched_tonight
    active_count=$(count_active)
    dispatched_tonight=$(count_dispatched_tonight)

    # Check limits
    if [ "$dispatched_tonight" -ge "$MAX_TASKS_PER_NIGHT" ]; then
        log "LIMIT: max tasks per night reached (${dispatched_tonight}/${MAX_TASKS_PER_NIGHT})"
        return 0
    fi

    if [ "$active_count" -ge "$MAX_CONCURRENT" ]; then
        log "WAIT: max concurrent agents (${active_count}/${MAX_CONCURRENT})"
        return 0
    fi

    # Get sorted queue (files are prefixed with priority: P0-, P1-, etc.)
    local slots_available
    slots_available=$((MAX_CONCURRENT - active_count))

    local dispatched=0
    for task_file in $(ls -1 "${QUEUE_DIR}"/*.json 2>/dev/null | sort); do
        [ -f "$task_file" ] || continue

        if [ "$dispatched" -ge "$slots_available" ]; then
            break
        fi

        dispatch_task "$task_file"
        dispatched=$((dispatched + 1))

        # Cooldown between dispatches
        if [ "$dispatched" -lt "$slots_available" ]; then
            sleep "$DISPATCH_COOLDOWN"
        fi
    done

    if [ "$dispatched" -gt 0 ]; then
        log "ROUND: dispatched ${dispatched} task(s), active=$(count_active), tonight=${dispatched_tonight}"
    fi
}

# ---- Status ----
print_status() {
    local queue_count=0 active_count=0 completed_count=0 failed_count=0

    for f in "${QUEUE_DIR}"/*.json; do [ -f "$f" ] && queue_count=$((queue_count + 1)); done
    for f in "${ACTIVE_DIR}"/*.json; do [ -f "$f" ] && active_count=$((active_count + 1)); done
    for f in "${COMPLETED_DIR}"/*.json; do [ -f "$f" ] && completed_count=$((completed_count + 1)); done
    for f in "${FAILED_DIR}"/*.json; do [ -f "$f" ] && failed_count=$((failed_count + 1)); done

    echo "Army Dispatch Status:"
    echo "  Queue:     ${queue_count}"
    echo "  Active:    ${active_count} / ${MAX_CONCURRENT}"
    echo "  Completed: ${completed_count}"
    echo "  Failed:    ${failed_count}"
    echo "  Tonight:   $(count_dispatched_tonight) / ${MAX_TASKS_PER_NIGHT}"

    if [ -f "$PIDFILE" ]; then
        local dpid
        dpid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
            echo "  Dispatcher: running (PID ${dpid})"
        else
            echo "  Dispatcher: not running (stale PID file)"
        fi
    else
        echo "  Dispatcher: not running"
    fi
}

# ==== Command handling ====
case "${1:-once}" in
    once)
        # Single dispatch round
        log "Running single dispatch round"
        dispatch_round
        ;;
    loop)
        # Continuous dispatch loop (used by cron/launchd)
        check_already_running
        write_pid
        trap cleanup_pid EXIT

        log "Dispatcher started in loop mode (PID $$)"

        while true; do
            dispatch_round
            rotate_log
            sleep 60  # Check every minute
        done
        ;;
    collect)
        # Just collect results without dispatching new tasks
        collect_results
        ;;
    status)
        print_status
        ;;
    stop)
        if [ -f "$PIDFILE" ]; then
            dpid=$(cat "$PIDFILE" 2>/dev/null)
            if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
                kill "$dpid" 2>/dev/null
                rm -f "$PIDFILE"
                log "Dispatcher stopped (PID ${dpid})"
                echo "Dispatcher stopped"
            else
                rm -f "$PIDFILE"
                echo "Dispatcher not running (cleaned stale PID)"
            fi
        else
            echo "Dispatcher not running"
        fi
        ;;
    *)
        echo "Usage: army-dispatch.sh [once|loop|collect|status|stop]"
        exit 1
        ;;
esac

exit 0
