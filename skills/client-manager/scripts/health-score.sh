#!/usr/bin/env bash
# ============================================================================
# Health Score Calculator — Orchestra Intelligence Client Manager
# ============================================================================
# Calculates health scores for all clients using real email data (GOG CLI)
#
# Formula:
#   Health = (0.3 × Engagement) + (0.25 × Delivery) + (0.2 × Revenue) + (0.15 × Satisfaction) + (0.1 × Growth)
#
# Usage: ./health-score.sh [--client <id>] [--json] [--quiet]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENTS_FILE="$SCRIPT_DIR/clients.json"
OUTPUT_DIR="$SCRIPT_DIR/output"
TIMESTAMP=$(date +%Y-%m-%d)
TODAY_EPOCH=$(date +%s)

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Args
TARGET_CLIENT=""
JSON_OUTPUT=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --client) TARGET_CLIENT="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --quiet) QUIET=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Source GOG keyring password
if [[ -f "$HOME/.secrets/.env" ]]; then
  source "$HOME/.secrets/.env" 2>/dev/null || true
fi
if [[ -z "${GOG_KEYRING_PASSWORD:-}" ]]; then
  echo "ERROR: GOG_KEYRING_PASSWORD not found in env or $HOME/.secrets/.env" >&2
  exit 1
fi
export GOG_KEYRING_PASSWORD

# ============================================================================
# Helper: calculate days since a date
# ============================================================================
days_since() {
  local date_str="$1"
  if [[ -z "$date_str" || "$date_str" == "null" ]]; then
    echo "999"
    return
  fi
  local target_epoch
  target_epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null || echo "0")
  if [[ "$target_epoch" == "0" ]]; then
    echo "999"
    return
  fi
  echo $(( (TODAY_EPOCH - target_epoch) / 86400 ))
}

# ============================================================================
# Helper: engagement score from days since last contact
# ============================================================================
engagement_score() {
  local days=$1
  if (( days < 7 )); then echo 100
  elif (( days < 14 )); then echo 75
  elif (( days < 30 )); then echo 50
  elif (( days < 60 )); then echo 25
  else echo 10
  fi
}

# ============================================================================
# Helper: check real email activity via GOG
# ============================================================================
check_email_activity() {
  local domain="$1"
  local days="${2:-30}"

  if [[ -z "$domain" || "$domain" == "null" ]]; then
    echo "0"
    return
  fi

  local result count
  result=$(gog gmail list -a sales@orchestraintelligence.fr "(from:$domain OR to:$domain) newer_than:${days}d" -p 2>/dev/null || echo "")
  if [[ -z "$result" ]]; then
    echo "0"
  else
    count=$(echo "$result" | grep -c "^[a-f0-9]" || true)
    echo "${count:-0}"
  fi
}

# ============================================================================
# Helper: delivery score (based on project status)
# ============================================================================
delivery_score() {
  local phase="$1"
  local open_items="$2"

  case "$phase" in
    *"Production"*|*"Full Régime"*|*"complete"*|*"Complete"*) echo 90 ;;
    *"Maintenance"*|*"Active"*) echo 75 ;;
    *"Development"*|*"V2"*) echo 70 ;;
    *"Pre-deployment"*) echo 65 ;;
    *"Meeting"*|*"Demo"*) echo 50 ;;
    *"Dormant"*|*"Unknown"*) echo 20 ;;
    *) echo 50 ;;
  esac
}

# ============================================================================
# Helper: revenue score (based on MRR and tier)
# ============================================================================
revenue_score() {
  local mrr=$1
  if (( mrr >= 10000 )); then echo 100
  elif (( mrr >= 5000 )); then echo 80
  elif (( mrr >= 3000 )); then echo 70
  elif (( mrr >= 1000 )); then echo 50
  elif (( mrr > 0 )); then echo 30
  else echo 0
  fi
}

# ============================================================================
# Helper: risk level from health score
# ============================================================================
risk_from_score() {
  local score=$1
  if (( score >= 80 )); then echo "low"
  elif (( score >= 50 )); then echo "medium"
  else echo "high"
  fi
}

risk_emoji() {
  local risk="$1"
  case "$risk" in
    low) echo "🟢" ;;
    medium) echo "🟡" ;;
    high) echo "🔴" ;;
    *) echo "⚪" ;;
  esac
}

tier_emoji() {
  local tier="$1"
  case "$tier" in
    platinum) echo "🥇" ;;
    gold) echo "🥈" ;;
    silver) echo "🥉" ;;
    bronze) echo "🟤" ;;
    internal) echo "🏠" ;;
    prospect) echo "🎯" ;;
    *) echo "📋" ;;
  esac
}

# ============================================================================
# Main: Process each client
# ============================================================================
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install: brew install jq"
  exit 1
fi

if [[ ! -f "$CLIENTS_FILE" ]]; then
  echo "Error: $CLIENTS_FILE not found"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Email domain mapping for GOG lookups
get_email_domain() {
  case "$1" in
    wella) echo "wella.com" ;;
    smart-renovation) echo "smartrenovation" ;;
    imagin-funeraire) echo "imagincommunication.fr" ;;
    le-chantier-ia) echo "orchestraintelligence.fr" ;;
    carlance) echo "carlance.fr" ;;
    winppi) echo "winppi.fr" ;;
    revlon) echo "revlon.com" ;;
    *) echo "" ;;
  esac
}

RESULTS_JSON="["
FIRST=true

CLIENT_IDS=$(jq -r '.clients[].id' "$CLIENTS_FILE")

for CLIENT_ID in $CLIENT_IDS; do
  # Skip if targeting specific client
  if [[ -n "$TARGET_CLIENT" && "$CLIENT_ID" != "$TARGET_CLIENT" ]]; then
    continue
  fi

  CLIENT_DATA=$(jq -r ".clients[] | select(.id == \"$CLIENT_ID\")" "$CLIENTS_FILE")

  NAME=$(echo "$CLIENT_DATA" | jq -r '.name')
  TIER=$(echo "$CLIENT_DATA" | jq -r '.tier')
  STATUS=$(echo "$CLIENT_DATA" | jq -r '.status')
  MRR=$(echo "$CLIENT_DATA" | jq -r '.contract.mrr // 0')
  LAST_CONTACT=$(echo "$CLIENT_DATA" | jq -r '.health.last_contact_date // "null"')
  PHASE=$(echo "$CLIENT_DATA" | jq -r '.project.current_phase // "Unknown"')
  OPEN_ITEMS=$(echo "$CLIENT_DATA" | jq -r '.health.open_items | length // 0')

  if ! $QUIET; then
    echo -e "${BLUE}▸${NC} Scoring ${BOLD}$NAME${NC} ($CLIENT_ID)..."
  fi

  # --- 1. Engagement (0.3) ---
  DAYS_SINCE=$(days_since "$LAST_CONTACT")

  # Try live email check if domain mapped
  DOMAIN=$(get_email_domain "$CLIENT_ID")
  if [[ -n "$DOMAIN" ]]; then
    RECENT_EMAILS=$(check_email_activity "$DOMAIN" 7)
    RECENT_EMAILS=${RECENT_EMAILS:-0}
    if [[ "$RECENT_EMAILS" =~ ^[0-9]+$ ]] && (( RECENT_EMAILS > 0 && DAYS_SINCE > 7 )); then
      # Override: we found recent emails GOG didn't catch in stored data
      DAYS_SINCE=3
    fi
  fi

  ENGAGEMENT=$(engagement_score "$DAYS_SINCE")

  # --- 2. Delivery (0.25) ---
  DELIVERY=$(delivery_score "$PHASE" "$OPEN_ITEMS")

  # --- 3. Revenue (0.2) ---
  REVENUE=$(revenue_score "$MRR")

  # --- 4. Satisfaction (0.15) — proxy: no complaints + active communication
  SATISFACTION=70  # Default baseline
  if (( DAYS_SINCE < 7 )); then SATISFACTION=85; fi
  if [[ "$STATUS" == "inactive" ]]; then SATISFACTION=30; fi

  # --- 5. Growth (0.1) — proxy: upsell potential + pipeline activity
  GROWTH=50  # Default
  if [[ "$TIER" == "platinum" ]]; then GROWTH=80; fi
  if [[ "$TIER" == "prospect" ]]; then GROWTH=70; fi
  if [[ "$STATUS" == "inactive" ]]; then GROWTH=10; fi

  # --- Calculate weighted score ---
  SCORE=$(echo "scale=0; (0.30 * $ENGAGEMENT + 0.25 * $DELIVERY + 0.20 * $REVENUE + 0.15 * $SATISFACTION + 0.10 * $GROWTH) / 1" | bc)
  RISK=$(risk_from_score "$SCORE")

  # --- Update clients.json ---
  UPDATED=$(jq --arg id "$CLIENT_ID" --argjson score "$SCORE" --arg risk "$RISK" \
    '(.clients[] | select(.id == $id)).health.score = $score | (.clients[] | select(.id == $id)).health.risk_level = $risk' \
    "$CLIENTS_FILE")
  echo "$UPDATED" > "$CLIENTS_FILE"

  if ! $QUIET; then
    RISK_E=$(risk_emoji "$RISK")
    TIER_E=$(tier_emoji "$TIER")
    echo -e "  ${TIER_E} ${BOLD}$NAME${NC} → Score: ${BOLD}$SCORE/100${NC} $RISK_E $RISK"
    echo -e "    Engagement=$ENGAGEMENT (${DAYS_SINCE}d) | Delivery=$DELIVERY | Revenue=$REVENUE | Satisfaction=$SATISFACTION | Growth=$GROWTH"
  fi

  # Build JSON result
  if ! $FIRST; then RESULTS_JSON+=","; fi
  FIRST=false
  RESULTS_JSON+=$(cat <<EOF
{
  "id": "$CLIENT_ID",
  "name": "$NAME",
  "tier": "$TIER",
  "mrr": $MRR,
  "score": $SCORE,
  "risk": "$RISK",
  "days_since_contact": $DAYS_SINCE,
  "components": {
    "engagement": $ENGAGEMENT,
    "delivery": $DELIVERY,
    "revenue": $REVENUE,
    "satisfaction": $SATISFACTION,
    "growth": $GROWTH
  },
  "last_contact": "$LAST_CONTACT",
  "phase": "$PHASE"
}
EOF
)
done

RESULTS_JSON+="]"

# Save results
RESULTS_FILE="$OUTPUT_DIR/health-scores-$TIMESTAMP.json"
echo "$RESULTS_JSON" | jq '.' > "$RESULTS_FILE"

if $JSON_OUTPUT; then
  cat "$RESULTS_FILE"
fi

if ! $QUIET; then
  echo ""
  echo -e "${GREEN}✓${NC} Health scores saved to ${BOLD}$RESULTS_FILE${NC}"

  # Portfolio summary
  TOTAL_MRR=$(echo "$RESULTS_JSON" | jq '[.[].mrr] | add')
  AVG_SCORE=$(echo "$RESULTS_JSON" | jq '[.[].score] | add / length | floor')
  HIGH_RISK=$(echo "$RESULTS_JSON" | jq '[.[] | select(.risk == "high")] | length')
  ACTIVE=$(echo "$RESULTS_JSON" | jq '[.[] | select(.mrr > 0)] | length')

  echo ""
  echo -e "${BOLD}📊 Portfolio Summary${NC}"
  echo -e "  Total MRR: €$TOTAL_MRR"
  echo -e "  Avg Health: $AVG_SCORE/100"
  echo -e "  Active Revenue Clients: $ACTIVE"
  echo -e "  High Risk: $HIGH_RISK"
fi
