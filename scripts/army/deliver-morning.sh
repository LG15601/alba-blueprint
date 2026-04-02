#!/bin/bash
# ==========================================================
# Alba Army — Morning Report Delivery via Telegram
# Reads today's report and sends via Telegram MCP reply tool
# Usage: deliver-morning.sh [YYYY-MM-DD]
# ==========================================================
set -u

# ---- PATH for launchd ----
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.nvm/versions/node/v22.22.2/bin:$HOME/bin:$PATH"

# ---- Config ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
ARMY_BASE="$HOME/.alba/army"
REPORTS_DIR="${ARMY_BASE}/reports"
LOG_FILE="${ARMY_BASE}/logs/deliver-morning.log"
LOG_TAG="army-deliver"
ALBA_PROJECT_DIR="$HOME/AZW/alba-blueprint"

# Target date (default: today)
REPORT_DATE="${1:-$(date '+%Y-%m-%d')}"
REPORT_FILE="${REPORTS_DIR}/${REPORT_DATE}.md"

# ---- Ensure directories ----
mkdir -p "${ARMY_BASE}/logs"

# ---- Centralized logging ----
source "$(dirname "$0")/../alba-log.sh"
log() {
    alba_log INFO deliver-morning "$1"
}

# ---- Preflight ----
if [ ! -f "$REPORT_FILE" ]; then
    log "No report found for ${REPORT_DATE}, compiling now..."
    bash "${SCRIPT_DIR}/compile-report.sh" "$REPORT_DATE"
    if [ ! -f "$REPORT_FILE" ]; then
        log "ERROR: failed to compile report for ${REPORT_DATE}"
        exit 1
    fi
fi

# ---- Read report content ----
REPORT_CONTENT=$(cat "$REPORT_FILE")
if [ -z "$REPORT_CONTENT" ]; then
    log "ERROR: report file empty"
    exit 1
fi

log "Delivering morning report for ${REPORT_DATE} ($(wc -l < "$REPORT_FILE") lines)"

# ---- Read Telegram chat_id from env ----
# Load .env for TELEGRAM_BOSS_CHAT_ID
if [ -f "$HOME/.alba/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$HOME/.alba/.env"
    set +a
fi

CHAT_ID="${TELEGRAM_BOSS_CHAT_ID:-}"

if [ -z "$CHAT_ID" ]; then
    log "WARNING: TELEGRAM_BOSS_CHAT_ID not set in ~/.alba/.env"
    log "Report saved at ${REPORT_FILE} but could not be delivered"
    echo "WARNING: No TELEGRAM_BOSS_CHAT_ID configured. Report at: ${REPORT_FILE}"
    exit 1
fi

# ---- Method 1: Send via Alba's main session (if running) ----
# Inject a message into the alba-agent tmux session to trigger Telegram reply
send_via_alba_session() {
    if ! tmux has-session -t alba-agent 2>/dev/null; then
        return 1
    fi

    # Build the command for Alba to execute
    # We pipe the report through Alba's session so it uses the Telegram MCP tool
    local prompt
    prompt=$(cat <<PROMPT
Envoie ce rapport de nuit a Ludovic sur Telegram (chat_id: ${CHAT_ID}):

${REPORT_CONTENT}

Utilise l'outil reply de Telegram pour envoyer. Formate proprement pour Telegram (pas trop long par message).
PROMPT
)

    # Write to a temp file to avoid escaping issues
    local tmpfile="/tmp/alba-morning-report-prompt.txt"
    echo "$prompt" > "$tmpfile"

    tmux send-keys -t alba-agent "$(cat "$tmpfile")" Enter 2>/dev/null
    rm -f "$tmpfile"

    log "Injected report into alba-agent session"
    return 0
}

# ---- Method 2: Send via standalone Claude Code with Telegram MCP ----
send_via_standalone() {
    local claude_cmd
    claude_cmd="$(command -v claude 2>/dev/null || echo '/opt/homebrew/bin/claude')"

    if [ ! -x "$claude_cmd" ] && ! command -v claude >/dev/null 2>&1; then
        log "ERROR: claude CLI not found"
        return 1
    fi

    local prompt
    prompt="Envoie ce rapport de nuit a Ludovic sur Telegram (chat_id: ${CHAT_ID}). Utilise l'outil reply de Telegram. Formate proprement pour Telegram (pas trop long par message, decoupe si necessaire).

${REPORT_CONTENT}"

    echo "$prompt" | "$claude_cmd" \
        --dangerously-skip-permissions \
        --max-turns 5 \
        -p \
        2>>"$LOG_FILE"

    if [ $? -eq 0 ]; then
        log "Report sent via standalone Claude"
        return 0
    else
        log "ERROR: standalone Claude delivery failed"
        return 1
    fi
}

# ---- Method 3: Fallback — just log it ----
send_fallback() {
    log "FALLBACK: Could not deliver report via Telegram"
    log "Report content saved at: ${REPORT_FILE}"

    # Also try macOS notification
    osascript -e "display notification \"Rapport nuit pret: ${REPORT_FILE}\" with title \"Alba Army\"" 2>/dev/null || true

    return 0
}

# ---- Delivery chain: try each method ----
log "Attempting delivery via alba-agent session..."
if send_via_alba_session; then
    log "SUCCESS: report delivered via alba-agent session"
    exit 0
fi

log "Alba session not available, trying standalone Claude..."
if send_via_standalone; then
    log "SUCCESS: report delivered via standalone Claude"
    exit 0
fi

log "Standalone delivery failed, using fallback..."
send_fallback
exit 1
