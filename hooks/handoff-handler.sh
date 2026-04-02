#!/bin/bash
# Alba — Handoff Handler (PostToolUse)
# Parses subagent results, generates structured handoff documents,
# tracks retry counts, and triggers escalation after maxRetries failures.
# Always exits 0 — handoff processing should never block.

set -uo pipefail
# Note: no set -e — we must never exit non-zero (D005 fail-open)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${DELEGATION_CONFIG:-$(cd "$SCRIPT_DIR/.." && pwd)/config/delegation-limits.json}"
STATE_FILE="${DELEGATION_STATE:-$HOME/.alba/delegation-state.json}"
LOG_FILE="${DELEGATION_LOG:-$HOME/logs/delegation.log}"
HANDOFF_DIR="${HANDOFF_DIR:-$HOME/.alba/handoffs}"
TEMPLATE_DIR="${TEMPLATE_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/config/handoff-templates}"
LOCK_DIR="/tmp/alba-delegation.lock"
LOCK_STALE_SECONDS=60

# --- Logging ---
log_handoff() {
    local msg="$1"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] HANDOFF: $msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Lock management (mkdir-based, same as gate/cleanup hooks) ---
acquire_lock() {
    local retries=5
    local wait=1
    while [ "$retries" -gt 0 ]; do
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            echo $$ > "$LOCK_DIR/pid"
            return 0
        fi
        if [ -d "$LOCK_DIR" ]; then
            local lock_age
            if [ "$(uname)" = "Darwin" ]; then
                lock_age=$(( $(date +%s) - $(stat -f '%m' "$LOCK_DIR" 2>/dev/null || echo 0) ))
            else
                lock_age=$(( $(date +%s) - $(stat -c '%Y' "$LOCK_DIR" 2>/dev/null || echo 0) ))
            fi
            if [ "$lock_age" -gt "$LOCK_STALE_SECONDS" ]; then
                rm -rf "$LOCK_DIR"
                continue
            fi
        fi
        retries=$((retries - 1))
        sleep "$wait"
    done
    return 1
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

# --- Read stdin (non-blocking, M005 pattern) ---
INPUT=""
if read -t 1 -r FIRST_LINE 2>/dev/null; then
    REST=$(cat 2>/dev/null) || true
    INPUT="${FIRST_LINE}${REST}"
fi

if [ -z "$INPUT" ]; then
    exit 0
fi

# --- Validate JSON ---
if ! echo "$INPUT" | jq . >/dev/null 2>&1; then
    log_handoff "Malformed stdin — not valid JSON"
    exit 0
fi

# --- Only process Agent|Task tool completions ---
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
case "$TOOL_NAME" in
    subagent|Agent|Task) ;;
    *)
        # Not a subagent completion — nothing to do
        exit 0
        ;;
esac

# --- Extract session_id (3-path jq chain from S01) ---
SESSION_ID=""
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || true
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.tool_output.session_id // empty' 2>/dev/null) || true
fi
if [ -z "$SESSION_ID" ]; then
    SESSION_ID=$(echo "$INPUT" | jq -r '.subagent.session_id // empty' 2>/dev/null) || true
fi
if [ -z "$SESSION_ID" ]; then
    log_handoff "No session_id found in input — cannot track handoff"
    exit 0
fi

# --- Extract task_id ---
TASK_ID=$(echo "$INPUT" | jq -r '.tool_output.task_id // .task_id // "unknown"' 2>/dev/null) || TASK_ID="unknown"

# --- Load handoff config ---
DEFAULT_MAX_RETRIES=3
if [ -f "$CONFIG_FILE" ] && jq . "$CONFIG_FILE" >/dev/null 2>&1; then
    MAX_RETRIES=$(jq -r '.handoff.maxRetries // 3' "$CONFIG_FILE" 2>/dev/null) || MAX_RETRIES=$DEFAULT_MAX_RETRIES
else
    MAX_RETRIES=$DEFAULT_MAX_RETRIES
    log_handoff "Config missing or malformed — using default maxRetries=$DEFAULT_MAX_RETRIES"
fi

# --- Determine handoff type from result content ---
# Priority: explicit handoff_type field > pass/fail signals > default "standard"
HANDOFF_TYPE=""

# Check explicit field
HANDOFF_TYPE=$(echo "$INPUT" | jq -r '.tool_output.handoff_type // .handoff_type // empty' 2>/dev/null) || true

if [ -z "$HANDOFF_TYPE" ]; then
    # Check for QA pass/fail signals in tool_output
    RESULT_TEXT=$(echo "$INPUT" | jq -r '.tool_output.result // .tool_output.summary // .result // ""' 2>/dev/null) || RESULT_TEXT=""
    QA_VERDICT=$(echo "$INPUT" | jq -r '.tool_output.verdict // .tool_output.qa_verdict // empty' 2>/dev/null) || true

    if [ -n "$QA_VERDICT" ]; then
        case "$QA_VERDICT" in
            pass|PASS|passed|PASSED) HANDOFF_TYPE="qa-pass" ;;
            fail|FAIL|failed|FAILED) HANDOFF_TYPE="qa-fail" ;;
            *) HANDOFF_TYPE="standard" ;;
        esac
    elif echo "$RESULT_TEXT" | grep -qi "qa.*pass\|verification.*pass\|all.*checks.*pass"; then
        HANDOFF_TYPE="qa-pass"
    elif echo "$RESULT_TEXT" | grep -qi "qa.*fail\|verification.*fail\|checks.*fail"; then
        HANDOFF_TYPE="qa-fail"
    else
        HANDOFF_TYPE="standard"
    fi
fi

# --- Load state for retry tracking ---
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
if [ ! -f "$STATE_FILE" ] || ! jq . "$STATE_FILE" >/dev/null 2>&1; then
    echo '{"children":[]}' > "$STATE_FILE" 2>/dev/null || true
    log_handoff "State file missing or corrupt — reset to empty"
fi

STATE=$(cat "$STATE_FILE" 2>/dev/null) || STATE='{"children":[]}'

# Get current retry_count for this session
RETRY_COUNT=$(echo "$STATE" | jq --arg sid "$SESSION_ID" '
    [.children[] | select(.session_id == $sid)] | first // {} | .retry_count // 0
' 2>/dev/null) || RETRY_COUNT=0

# --- Handle QA retry logic ---
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TIMESTAMP_FILE=$(date -u '+%Y%m%d-%H%M%S')

case "$HANDOFF_TYPE" in
    qa-pass)
        # Generate qa-pass handoff — extract evidence from result
        EVIDENCE=$(echo "$INPUT" | jq -c '.tool_output.evidence // []' 2>/dev/null) || EVIDENCE="[]"
        CHECKLIST=$(echo "$INPUT" | jq -c '.tool_output.verification_checklist // []' 2>/dev/null) || CHECKLIST="[]"

        HANDOFF_DOC=$(jq -n \
            --arg type "qa-pass" \
            --arg task_id "$TASK_ID" \
            --argjson evidence "$EVIDENCE" \
            --argjson checklist "$CHECKLIST" \
            --arg ts "$TIMESTAMP" \
            '{
                type: $type,
                task_id: $task_id,
                evidence: $evidence,
                verification_checklist: $checklist,
                all_passed: true,
                timestamp: $ts
            }')
        log_handoff "type=qa-pass task_id=$TASK_ID retry_count=$RETRY_COUNT"
        ;;

    qa-fail)
        # Increment retry count
        RETRY_COUNT=$((RETRY_COUNT + 1))

        if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
            # Escalation — max retries exhausted
            HANDOFF_TYPE="escalation"

            # Build failure_history from accumulated data
            FAILURE_HISTORY=$(echo "$INPUT" | jq -c --argjson attempt "$RETRY_COUNT" '
                .tool_output.failure_history // [{
                    attempt: $attempt,
                    issue_summary: (.tool_output.issue_summary // .tool_output.result // "QA verification failed"),
                    fix_attempted: (.tool_output.fix_attempted // "See previous attempts")
                }]
            ' 2>/dev/null) || FAILURE_HISTORY="[]"

            ROOT_CAUSE=$(echo "$INPUT" | jq -r '.tool_output.root_cause_analysis // "Repeated QA failures — requires investigation"' 2>/dev/null) || ROOT_CAUSE="Repeated QA failures — requires investigation"
            RECOMMENDED=$(echo "$INPUT" | jq -r '.tool_output.recommended_resolution // "Manual review required"' 2>/dev/null) || RECOMMENDED="Manual review required"
            IMPACT=$(echo "$INPUT" | jq -r '.tool_output.impact_assessment // "Blocking downstream work"' 2>/dev/null) || IMPACT="Blocking downstream work"

            HANDOFF_DOC=$(jq -n \
                --arg type "escalation" \
                --arg task_id "$TASK_ID" \
                --argjson failure_history "$FAILURE_HISTORY" \
                --arg root_cause "$ROOT_CAUSE" \
                --arg recommended "$RECOMMENDED" \
                --arg impact "$IMPACT" \
                --argjson retry_count "$RETRY_COUNT" \
                --arg ts "$TIMESTAMP" \
                '{
                    type: $type,
                    task_id: $task_id,
                    failure_history: $failure_history,
                    root_cause_analysis: $root_cause,
                    recommended_resolution: $recommended,
                    impact_assessment: $impact,
                    retry_count: $retry_count,
                    timestamp: $ts
                }')
            log_handoff "type=escalation task_id=$TASK_ID retry_count=$RETRY_COUNT (max $MAX_RETRIES reached)"
        else
            # Generate qa-fail handoff with fix instructions
            ISSUE_LIST=$(echo "$INPUT" | jq -c '.tool_output.issue_list // []' 2>/dev/null) || ISSUE_LIST="[]"
            FIX_INSTRUCTIONS=$(echo "$INPUT" | jq -r '.tool_output.fix_instructions // "Review and fix the reported issues"' 2>/dev/null) || FIX_INSTRUCTIONS="Review and fix the reported issues"

            HANDOFF_DOC=$(jq -n \
                --arg type "qa-fail" \
                --arg task_id "$TASK_ID" \
                --argjson issue_list "$ISSUE_LIST" \
                --arg fix "$FIX_INSTRUCTIONS" \
                --argjson retry_count "$RETRY_COUNT" \
                --arg ts "$TIMESTAMP" \
                '{
                    type: $type,
                    task_id: $task_id,
                    issue_list: $issue_list,
                    fix_instructions: $fix,
                    retry_count: $retry_count,
                    timestamp: $ts
                }')
            log_handoff "type=qa-fail task_id=$TASK_ID retry_count=$RETRY_COUNT/$MAX_RETRIES"
        fi

        # Update retry_count in state (under lock)
        if acquire_lock; then
            trap 'release_lock 2>/dev/null || true' EXIT
            # Re-read state in case it changed
            if [ -f "$STATE_FILE" ] && jq . "$STATE_FILE" >/dev/null 2>&1; then
                STATE=$(cat "$STATE_FILE")
            fi
            STATE=$(echo "$STATE" | jq --arg sid "$SESSION_ID" --argjson rc "$RETRY_COUNT" --arg ht "$HANDOFF_TYPE" '
                .children = [.children[] |
                    if .session_id == $sid then
                        .retry_count = $rc | .handoff_type = $ht
                    else . end
                ]
            ')
            echo "$STATE" | jq . > "$STATE_FILE"
            release_lock
            trap - EXIT
        else
            log_handoff "Failed to acquire lock for retry_count update — state not persisted"
        fi
        ;;

    completion)
        # Generate completion handoff
        SUMMARY=$(echo "$INPUT" | jq -r '.tool_output.summary // "Task completed"' 2>/dev/null) || SUMMARY="Task completed"
        ARTIFACTS=$(echo "$INPUT" | jq -c '.tool_output.artifacts_produced // []' 2>/dev/null) || ARTIFACTS="[]"
        LEARNINGS=$(echo "$INPUT" | jq -c '.tool_output.learnings // []' 2>/dev/null) || LEARNINGS="[]"
        NEXT_STEPS=$(echo "$INPUT" | jq -c '.tool_output.next_steps // []' 2>/dev/null) || NEXT_STEPS="[]"

        HANDOFF_DOC=$(jq -n \
            --arg type "completion" \
            --arg task_id "$TASK_ID" \
            --arg summary "$SUMMARY" \
            --argjson artifacts "$ARTIFACTS" \
            --argjson learnings "$LEARNINGS" \
            --argjson next_steps "$NEXT_STEPS" \
            --arg ts "$TIMESTAMP" \
            '{
                type: $type,
                task_id: $task_id,
                summary: $summary,
                artifacts_produced: $artifacts,
                learnings: $learnings,
                next_steps: $next_steps,
                timestamp: $ts
            }')
        log_handoff "type=completion task_id=$TASK_ID"
        ;;

    *)
        # Standard handoff (default)
        HANDOFF_TYPE="standard"
        CONTEXT=$(echo "$INPUT" | jq -r '.tool_output.context // "Agent handoff"' 2>/dev/null) || CONTEXT="Agent handoff"
        FROM_AGENT=$(echo "$INPUT" | jq -r '.tool_output.from_agent // .session_id // "unknown"' 2>/dev/null) || FROM_AGENT="unknown"
        TO_AGENT=$(echo "$INPUT" | jq -r '.tool_output.to_agent // "unspecified"' 2>/dev/null) || TO_AGENT="unspecified"
        DELIVERABLE=$(echo "$INPUT" | jq -r '.tool_output.deliverable_request // "See context"' 2>/dev/null) || DELIVERABLE="See context"
        CRITERIA=$(echo "$INPUT" | jq -c '.tool_output.acceptance_criteria // []' 2>/dev/null) || CRITERIA="[]"

        HANDOFF_DOC=$(jq -n \
            --arg type "standard" \
            --arg from "$FROM_AGENT" \
            --arg to "$TO_AGENT" \
            --arg context "$CONTEXT" \
            --arg deliverable "$DELIVERABLE" \
            --argjson criteria "$CRITERIA" \
            --arg ts "$TIMESTAMP" \
            '{
                type: $type,
                from_agent: $from,
                to_agent: $to,
                context: $context,
                deliverable_request: $deliverable,
                acceptance_criteria: $criteria,
                timestamp: $ts
            }')
        log_handoff "type=standard task_id=$TASK_ID"
        ;;
esac

# --- Write handoff document ---
mkdir -p "$HANDOFF_DIR" 2>/dev/null || true
HANDOFF_FILE="$HANDOFF_DIR/${TIMESTAMP_FILE}-${HANDOFF_TYPE}.json"
if echo "$HANDOFF_DOC" | jq . > "$HANDOFF_FILE" 2>/dev/null; then
    log_handoff "Written to $HANDOFF_FILE"
else
    log_handoff "Failed to write handoff file to $HANDOFF_FILE"
fi

exit 0
