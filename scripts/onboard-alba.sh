#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Alba — Onboarding Wizard
# Interactive setup for new installations
# Usage: bash onboard-alba.sh [--check] [--phase N]
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

ENV_FILE="$HOME/.alba/.env"
LOG_FILE="$HOME/.alba/logs/onboarding.log"
mkdir -p "$HOME/.alba/logs"

# Track completed steps for progress
TOTAL_STEPS=0
DONE_STEPS=0

# ─── Helpers ──────────────────────────────────────────────────

ok()   { echo -e "  ${GREEN}✅${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠️${NC}  $1"; }
fail() { echo -e "  ${RED}❌${NC} $1"; }
info() { echo -e "  ${BLUE}ℹ${NC}  $1"; }
step() { echo -e "\n${CYAN}${BOLD}─── $1 ───${NC}"; }
ask()  { echo -en "  ${BOLD}$1${NC} "; }

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG_FILE"; }

banner() {
  echo ""
  echo -e "${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}║          ${CYAN}ALBA — Onboarding Wizard${NC}${BOLD}                ║${NC}"
  echo -e "${BOLD}║   ${DIM}The Ultimate AI Agent Setup${NC}${BOLD}                     ║${NC}"
  echo -e "${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
  echo ""
}

separator() {
  echo -e "${DIM}───────────────────────────────────────────────────${NC}"
}

# Progress bar — shows [████░░░░░░] 3/10
progress_bar() {
  local current=$1 total=$2
  local width=20
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local pct=$(( current * 100 / total ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  echo -e "  ${DIM}[${GREEN}${bar}${NC}${DIM}] ${current}/${total} (${pct}%)${NC}"
}

advance_progress() {
  DONE_STEPS=$(( DONE_STEPS + 1 ))
  progress_bar "$DONE_STEPS" "$TOTAL_STEPS"
}

# Write a key to .env (create or update)
set_env_key() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$ENV_FILE")"
  [ -f "$ENV_FILE" ] || touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    # Update existing (macOS sed)
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
  log "Set ${key} (${#value} chars)"
}

# Read a key from .env
get_env_key() {
  local key="$1"
  grep "^${key}=" "$ENV_FILE" 2>/dev/null | cut -d= -f2- || echo ""
}

# Masked input — reads securely, shows masked preview, stores in global REPLY_SECRET
REPLY_SECRET=""
read_secret() {
  local prompt="$1"
  REPLY_SECRET=""
  echo -en "  ${BOLD}${prompt}:${NC} "
  local value=""
  read -rs value
  if [ -n "$value" ]; then
    local len=${#value}
    if [ "$len" -gt 6 ]; then
      local masked="${value:0:3}$(printf '%*s' $((len-6)) '' | tr ' ' '•')${value:$((len-3))}"
      echo -e " ${DIM}[${masked}]${NC}"
    else
      echo -e " ${DIM}[set]${NC}"
    fi
    REPLY_SECRET="$value"
  else
    echo -e " ${DIM}[skipped]${NC}"
    REPLY_SECRET=""
  fi
}

# Validate API key format — returns 0 if valid, 1 if not
validate_key_format() {
  local key_name="$1" value="$2"
  case "$key_name" in
    BRAVE_API_KEY)
      # Brave keys are typically BSA* or alphanumeric, 20+ chars
      if [[ ${#value} -ge 10 && "$value" =~ ^[A-Za-z0-9_-]+$ ]]; then return 0; fi
      warn "Brave key seems short or has invalid characters (expected alphanumeric, 10+ chars)"
      return 1
      ;;
    ELEVENLABS_API_KEY)
      # ElevenLabs keys are hex-like, 32 chars
      if [[ ${#value} -ge 20 ]]; then return 0; fi
      warn "ElevenLabs key seems short (expected 20+ chars)"
      return 1
      ;;
    EXA_API_KEY)
      # Exa keys are typically 30+ alphanumeric
      if [[ ${#value} -ge 10 ]]; then return 0; fi
      warn "Exa key seems short (expected 10+ chars)"
      return 1
      ;;
    X_API_KEY|X_API_SECRET|X_ACCESS_TOKEN|X_ACCESS_TOKEN_SECRET|X_BEARER_TOKEN)
      if [[ ${#value} -ge 10 ]]; then return 0; fi
      warn "Twitter/X key seems short (expected 10+ chars)"
      return 1
      ;;
    *)
      # Default: just check non-empty
      [ -n "$value" ] && return 0 || return 1
      ;;
  esac
}

# Retry wrapper — runs a function with retry prompt on failure
# Usage: with_retry "Step name" function_name [args...]
with_retry() {
  local step_name="$1"; shift
  local func="$1"; shift
  while true; do
    if "$func" "$@"; then
      return 0
    fi
    echo ""
    ask "Retry '${step_name}'? (y/n/s=skip): "
    local reply=""
    read -r reply
    case "$reply" in
      y|Y) continue ;;
      s|S) warn "Skipped: ${step_name}"; return 1 ;;
      *)   warn "Skipped: ${step_name}"; return 1 ;;
    esac
  done
}

# ─── Check Mode ───────────────────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
  echo "Alba Onboarding — Status Check"
  separator

  errors=0

  # Permissions
  echo "Permissions:"
  if screencapture -x /tmp/alba-test-screenshot.png 2>/dev/null; then
    rm -f /tmp/alba-test-screenshot.png; ok "Screen Recording"
  else
    fail "Screen Recording — not granted"
    errors=$((errors + 1))
  fi

  # Services
  echo "Services:"
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code $(claude --version 2>/dev/null | head -1)"
  else
    fail "Claude Code not installed"
    errors=$((errors + 1))
  fi
  if command -v gws >/dev/null 2>&1; then
    ok "Google Workspace CLI installed"
  else
    warn "gws not installed"
  fi

  # API Keys
  echo "API Keys:"
  [ -f "$ENV_FILE" ] && source "$ENV_FILE" 2>/dev/null
  for key in BRAVE_API_KEY EXA_API_KEY ELEVENLABS_API_KEY X_API_KEY; do
    val="${!key:-}"
    if [ -n "$val" ]; then ok "$key configured"; else warn "$key not set"; fi
  done

  # Env file security
  echo "Security:"
  if [ -f "$ENV_FILE" ]; then
    perms=$(stat -f '%A' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE" 2>/dev/null)
    if [[ "$perms" == "600" ]]; then
      ok ".env permissions: 600 (owner-only)"
    else
      warn ".env permissions: $perms (should be 600)"
      errors=$((errors + 1))
    fi
  else
    info "No .env file yet"
  fi

  # Crontab
  echo "Scheduled Tasks:"
  cron_count=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | grep -v '^PATH' | grep -v '^HOME' | wc -l | tr -d ' ')
  if [ "$cron_count" -gt 0 ]; then
    ok "Crontab: $cron_count tasks"
  else
    warn "No crontab"
  fi

  # Alba process
  echo "Runtime:"
  if pgrep -f "claude.*channels.*telegram" >/dev/null 2>&1; then
    ok "Alba agent running"
  else
    warn "Alba agent not running"
  fi

  separator

  if [ "$errors" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All critical checks passed.${NC}"
  else
    echo -e "  ${YELLOW}${BOLD}${errors} issue(s) found — see above.${NC}"
  fi
  exit "$errors"
fi

# ─── Phase Selection ──────────────────────────────────────────
PHASE="${2:-all}"
if [[ "${1:-}" == "--phase" ]]; then PHASE="$2"; fi

# Set total steps based on phase
case "$PHASE" in
  1) TOTAL_STEPS=3 ;;
  2) TOTAL_STEPS=2 ;;
  3) TOTAL_STEPS=4 ;;
  *) TOTAL_STEPS=9 ;;
esac

# ═══════════════════════════════════════════════════════════════
# MAIN WIZARD
# ═══════════════════════════════════════════════════════════════

banner
echo -e "  This wizard will configure Alba in 3 phases:"
echo -e "  ${BOLD}1.${NC} macOS Permissions ${DIM}(Screen Recording, Accessibility)${NC}"
echo -e "  ${BOLD}2.${NC} Service Authentication ${DIM}(Google, Claude)${NC}"
echo -e "  ${BOLD}3.${NC} API Keys ${DIM}(Brave, ElevenLabs, Twitter/X — optional)${NC}"
echo ""
ask "Press Enter to start (or Ctrl+C to cancel)..."
read -r

log "Onboarding started (phase=$PHASE)"

# ═══════════════════════════════════════════════════════════════
# PHASE 1: macOS Permissions
# ═══════════════════════════════════════════════════════════════
if [[ "$PHASE" == "all" || "$PHASE" == "1" ]]; then
  step "PHASE 1 — macOS Permissions"

  # Screen Recording
  check_screen_recording() {
    echo ""
    echo -e "  ${BOLD}Screen Recording${NC} — required for Computer Use"
    if screencapture -x /tmp/alba-test-screenshot.png 2>/dev/null; then
      rm -f /tmp/alba-test-screenshot.png
      ok "Screen Recording already granted"
      return 0
    else
      warn "Screen Recording not granted"
      echo ""
      echo -e "  To enable:"
      echo -e "  ${CYAN}System Settings → Privacy & Security → Screen Recording${NC}"
      echo -e "  → Toggle ON for your terminal app (Terminal.app or iTerm2)"
      echo ""
      ask "Press Enter after granting permission (or 's' to skip)..."
      local reply=""
      read -r reply
      if [[ "$reply" == "s" || "$reply" == "S" ]]; then
        warn "Skipped — Computer Use will be limited"
        return 0
      fi
      if screencapture -x /tmp/alba-test-screenshot.png 2>/dev/null; then
        rm -f /tmp/alba-test-screenshot.png
        ok "Screen Recording now granted!"
        return 0
      else
        fail "Still not granted"
        return 1
      fi
    fi
  }
  with_retry "Screen Recording" check_screen_recording || true
  advance_progress

  # Accessibility
  echo ""
  echo -e "  ${BOLD}Accessibility${NC} — required for Computer Use automation"
  echo -e "  ${CYAN}System Settings → Privacy & Security → Accessibility${NC}"
  echo -e "  → Toggle ON for your terminal app"
  echo ""
  ask "Is Accessibility enabled? (y/n/s to skip): "
  read -r reply
  case "$reply" in
    y|Y) ok "Accessibility confirmed" ;;
    s|S) warn "Skipped — Computer Use will be limited" ;;
    *) warn "Not confirmed — enable it later for full Computer Use" ;;
  esac
  advance_progress

  # Full Disk Access
  echo ""
  echo -e "  ${BOLD}Full Disk Access${NC} ${DIM}(recommended)${NC}"
  echo -e "  ${CYAN}System Settings → Privacy & Security → Full Disk Access${NC}"
  echo -e "  → Toggle ON for your terminal app"
  ask "Is Full Disk Access enabled? (y/n/s to skip): "
  read -r reply
  case "$reply" in
    y|Y) ok "Full Disk Access confirmed" ;;
    *) info "Optional — most features work without it" ;;
  esac
  advance_progress

  log "Phase 1 complete"
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 2: Service Authentication
# ═══════════════════════════════════════════════════════════════
if [[ "$PHASE" == "all" || "$PHASE" == "2" ]]; then
  step "PHASE 2 — Service Authentication"

  # Claude Code
  check_claude() {
    echo ""
    echo -e "  ${BOLD}Claude Code${NC}"
    if command -v claude >/dev/null 2>&1; then
      ok "Claude Code installed ($(claude --version 2>/dev/null | head -1))"
      info "If not logged in, run: claude login"
      return 0
    else
      fail "Claude Code not found"
      echo "  Install: npm install -g @anthropic-ai/claude-code"
      return 1
    fi
  }
  with_retry "Claude Code check" check_claude || true
  advance_progress

  # Google Workspace
  check_gws() {
    echo ""
    echo -e "  ${BOLD}Google Workspace CLI${NC} — for Gmail, Calendar, Drive"
    if command -v gws >/dev/null 2>&1; then
      ok "gws installed"
      ask "Run 'gws auth login' now? (y/n): "
      local reply=""
      read -r reply
      if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
        echo ""
        info "Opening browser for Google OAuth..."
        if gws auth login 2>&1; then
          ok "Google auth complete"
        else
          warn "gws auth failed"
          return 1
        fi
      else
        info "Run 'gws auth login' later for Gmail/Calendar/Drive"
      fi
      return 0
    else
      warn "gws not installed"
      ask "Install Google Workspace CLI? (y/n): "
      local reply=""
      read -r reply
      if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
        if npm install -g @googleworkspace/cli 2>&1 | tail -1; then
          ok "gws installed — run 'gws auth login' to authenticate"
          return 0
        else
          fail "Installation failed"
          return 1
        fi
      fi
      return 0
    fi
  }
  with_retry "Google Workspace" check_gws || true
  advance_progress

  log "Phase 2 complete"
fi

# ═══════════════════════════════════════════════════════════════
# PHASE 3: API Keys
# ═══════════════════════════════════════════════════════════════
if [[ "$PHASE" == "all" || "$PHASE" == "3" ]]; then
  step "PHASE 3 — API Keys"
  echo ""
  echo -e "  Keys are stored in ${BOLD}~/.alba/.env${NC} (chmod 600)"
  echo -e "  Press ${BOLD}Enter${NC} to skip any key you don't have yet."
  echo ""

  # Ensure .env exists with secure permissions
  mkdir -p "$(dirname "$ENV_FILE")"
  [ -f "$ENV_FILE" ] || touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  # ── Collect a key with validation + retry ──
  # Usage: collect_api_key "Display Name" "KEY_NAME" "description" "get url" ["curl_test_cmd"]
  collect_api_key() {
    local display="$1" key_name="$2" desc="$3" url="$4" curl_test="${5:-}"

    separator
    echo -e "  ${BOLD}${display}${NC} — ${desc}"
    echo -e "  ${DIM}Get from: ${url}${NC}"
    local existing
    existing=$(get_env_key "$key_name")
    if [ -n "$existing" ]; then
      ok "Already set"
      ask "Update? (y/N): "
      local reply=""
      read -r reply
      if [[ "$reply" != "y" && "$reply" != "Y" ]]; then
        return 0
      fi
    fi

    while true; do
      read_secret "$display Key" 
      if [ -z "$REPLY_SECRET" ]; then
        return 0  # User skipped
      fi

      # Format validation
      if ! validate_key_format "$key_name" "$REPLY_SECRET"; then
        ask "Save anyway? (y/n/r=retry): "
        local reply=""
        read -r reply
        case "$reply" in
          y|Y) ;;
          r|R) continue ;;
          *) return 0 ;;
        esac
      fi

      set_env_key "$key_name" "$REPLY_SECRET"

      # Live validation via curl if provided
      if [ -n "$curl_test" ]; then
        local test_cmd="${curl_test/\{KEY\}/$REPLY_SECRET}"
        if eval "$test_cmd" 2>/dev/null; then
          ok "$display key validated ✓"
        else
          warn "Could not validate — key saved, will test at runtime"
          ask "Retry with different key? (y/N): "
          local reply=""
          read -r reply
          if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
            continue
          fi
        fi
      else
        ok "$display key saved"
      fi
      REPLY_SECRET=""
      break
    done
  }

  # ── Brave Search ──
  echo ""
  collect_api_key \
    "Brave Search API" \
    "BRAVE_API_KEY" \
    "web search for Alba" \
    "https://brave.com/search/api/" \
    'curl -sf --connect-timeout 5 -H "X-Subscription-Token: {KEY}" "https://api.search.brave.com/res/v1/web/search?q=test&count=1" | grep -q "web"'
  advance_progress

  # ── ElevenLabs ──
  echo ""
  collect_api_key \
    "ElevenLabs" \
    "ELEVENLABS_API_KEY" \
    "text-to-speech voice for Alba" \
    "https://elevenlabs.io/app/settings/api-keys"
  advance_progress

  # ── Exa ──
  echo ""
  collect_api_key \
    "Exa" \
    "EXA_API_KEY" \
    "deep web search" \
    "https://exa.ai"
  advance_progress

  # ── Twitter/X ──
  echo ""
  separator
  echo -e "  ${BOLD}Twitter/X API${NC} — post, search, monitor"
  echo -e "  ${DIM}Get from: https://developer.x.com${NC}"
  ask "Configure Twitter/X keys? (y/N): "
  read -r reply
  if [[ "$reply" == "y" || "$reply" == "Y" ]]; then
    for x_key_info in \
      "X API Key:X_API_KEY" \
      "X API Secret:X_API_SECRET" \
      "X Access Token:X_ACCESS_TOKEN" \
      "X Access Token Secret:X_ACCESS_TOKEN_SECRET" \
      "X Bearer Token:X_BEARER_TOKEN"; do
      local_label="${x_key_info%%:*}"
      local_key="${x_key_info##*:}"
      read_secret "$local_label"
      if [ -n "$REPLY_SECRET" ]; then
        if validate_key_format "$local_key" "$REPLY_SECRET"; then
          set_env_key "$local_key" "$REPLY_SECRET"
        else
          ask "Save anyway? (y/N): "
          read -r save_reply
          if [[ "$save_reply" == "y" || "$save_reply" == "Y" ]]; then
            set_env_key "$local_key" "$REPLY_SECRET"
          fi
        fi
        REPLY_SECRET=""
      fi
    done
    ok "Twitter/X keys saved"
  else
    info "Skipped — configure later with: bash onboard-alba.sh --phase 3"
  fi
  advance_progress

  # Secure the env file
  chmod 600 "$ENV_FILE"

  log "Phase 3 complete"
fi

# ═══════════════════════════════════════════════════════════════
# FINAL STATUS
# ═══════════════════════════════════════════════════════════════
step "ONBOARDING COMPLETE"
echo ""

# Run status check
bash "$0" --check || true

echo ""
separator
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo ""
echo -e "  ${CYAN}1.${NC} Launch Alba:     ${BOLD}bash scripts/start-alba.sh${NC}"
echo -e "  ${CYAN}2.${NC} Re-run setup:    ${BOLD}bash scripts/onboard-alba.sh --phase N${NC} (1, 2, or 3)"
echo -e "  ${CYAN}3.${NC} Check status:    ${BOLD}bash scripts/onboard-alba.sh --check${NC}"
echo ""
echo -e "  ${GREEN}${BOLD}Alba is ready. 🚀${NC}"
echo ""

log "Onboarding complete"
