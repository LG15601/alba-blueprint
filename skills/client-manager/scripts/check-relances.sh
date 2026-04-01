#!/usr/bin/env bash
# ============================================================================
# Relance Checker — Orchestra Intelligence Client Manager
# ============================================================================
# Identifies clients and prospects needing follow-up:
# - No response after 3 days → flag PREP relance
# - No contact in 14+ days → alert
# - Invoice overdue → alert
# - Pipeline actions overdue → flag
#
# Usage: ./check-relances.sh [--json] [--send-telegram]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENTS_FILE="$SCRIPT_DIR/clients.json"
PIPELINE_FILE="$SCRIPT_DIR/pipeline.json"
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

JSON_OUTPUT=false
SEND_TELEGRAM=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --json) JSON_OUTPUT=true; shift ;;
    --send-telegram) SEND_TELEGRAM=true; shift ;;
    *) shift ;;
  esac
done

# Source GOG
if [[ -f "$HOME/.secrets/.env" ]]; then
  source "$HOME/.secrets/.env" 2>/dev/null || true
fi
if [[ -z "${GOG_KEYRING_PASSWORD:-}" ]]; then
  echo "ERROR: GOG_KEYRING_PASSWORD not found in env or $HOME/.secrets/.env" >&2
  exit 1
fi
export GOG_KEYRING_PASSWORD

mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Helpers
# ============================================================================
days_since() {
  local date_str="$1"
  if [[ -z "$date_str" || "$date_str" == "null" ]]; then echo "999"; return; fi
  local target_epoch
  target_epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null || echo "0")
  if [[ "$target_epoch" == "0" ]]; then echo "999"; return; fi
  echo $(( (TODAY_EPOCH - target_epoch) / 86400 ))
}

# ============================================================================
# Check 1: Clients with no recent contact
# ============================================================================
echo -e "${BOLD}🔔 Relance Check — $TIMESTAMP${NC}"
echo ""

RELANCES_JSON="[]"
ALERT_COUNT=0
URGENT_COUNT=0

echo -e "${BOLD}1️⃣  Client Contact Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CLIENT_IDS=$(jq -r '.clients[].id' "$CLIENTS_FILE")

for CLIENT_ID in $CLIENT_IDS; do
  CLIENT=$(jq ".clients[] | select(.id == \"$CLIENT_ID\")" "$CLIENTS_FILE")

  NAME=$(echo "$CLIENT" | jq -r '.name')
  TIER=$(echo "$CLIENT" | jq -r '.tier')
  STATUS=$(echo "$CLIENT" | jq -r '.status')
  MRR=$(echo "$CLIENT" | jq -r '.contract.mrr // 0')
  LC_DATE=$(echo "$CLIENT" | jq -r '.health.last_contact_date // "null"')
  LC_SUBJ=$(echo "$CLIENT" | jq -r '.health.last_contact_subject // "N/A"')
  CONTACT_EMAIL=$(echo "$CLIENT" | jq -r '.contact.primary.email // "N/A"')
  CONTACT_NAME=$(echo "$CLIENT" | jq -r '.contact.primary.name // "N/A"')

  DAYS=$(days_since "$LC_DATE")

  # Skip internal products and unknown status
  if [[ "$STATUS" == "inactive" && "$TIER" != "bronze" ]]; then continue; fi

  # Tier-based thresholds
  case "$TIER" in
    platinum) WARN_DAYS=3; ALERT_DAYS=7; URGENT_DAYS=14 ;;
    gold)     WARN_DAYS=5; ALERT_DAYS=14; URGENT_DAYS=21 ;;
    silver)   WARN_DAYS=7; ALERT_DAYS=14; URGENT_DAYS=30 ;;
    bronze)   WARN_DAYS=14; ALERT_DAYS=30; URGENT_DAYS=60 ;;
    prospect) WARN_DAYS=3; ALERT_DAYS=7; URGENT_DAYS=14 ;;
    internal) WARN_DAYS=14; ALERT_DAYS=30; URGENT_DAYS=60 ;;
    *)        WARN_DAYS=7; ALERT_DAYS=14; URGENT_DAYS=30 ;;
  esac

  LEVEL="ok"
  ACTION=""

  if (( DAYS >= URGENT_DAYS )); then
    LEVEL="urgent"
    ACTION="🔴 YOURS — Ludo must personally reach out to $CONTACT_NAME"
    echo -e "  ${RED}🔴 URGENT${NC} ${BOLD}$NAME${NC} — No contact in ${DAYS} days (threshold: ${URGENT_DAYS}d)"
    echo -e "     → $ACTION"
    URGENT_COUNT=$((URGENT_COUNT + 1))
    ALERT_COUNT=$((ALERT_COUNT + 1))
  elif (( DAYS >= ALERT_DAYS )); then
    LEVEL="alert"
    ACTION="🟡 PREP — Draft follow-up email to $CONTACT_NAME ($CONTACT_EMAIL)"
    echo -e "  ${YELLOW}🟡 ALERT${NC} ${BOLD}$NAME${NC} — No contact in ${DAYS} days (threshold: ${ALERT_DAYS}d)"
    echo -e "     → $ACTION"
    ALERT_COUNT=$((ALERT_COUNT + 1))
  elif (( DAYS >= WARN_DAYS )); then
    LEVEL="warn"
    ACTION="📋 DISPATCH — Schedule touchpoint with $CONTACT_NAME"
    echo -e "  ${BLUE}📋 WARN${NC}  ${BOLD}$NAME${NC} — ${DAYS} days since last contact"
    echo -e "     → $ACTION"
  else
    if (( DAYS < 999 )); then
      echo -e "  ${GREEN}✅ OK${NC}    ${BOLD}$NAME${NC} — Last contact ${DAYS}d ago ✓"
    fi
  fi

  if [[ "$LEVEL" != "ok" ]]; then
    RELANCES_JSON=$(echo "$RELANCES_JSON" | jq --arg id "$CLIENT_ID" --arg name "$NAME" \
      --arg level "$LEVEL" --argjson days "$DAYS" --arg action "$ACTION" \
      --arg contact "$CONTACT_EMAIL" --arg last_subj "$LC_SUBJ" \
      '. + [{"client_id": $id, "name": $name, "level": $level, "days_since_contact": $days, "action": $action, "contact_email": $contact, "last_subject": $last_subj}]')
  fi
done

echo ""

# ============================================================================
# Check 2: Pipeline actions overdue
# ============================================================================
echo -e "${BOLD}2️⃣  Pipeline Action Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DEAL_COUNT=$(jq '.deals | length' "$PIPELINE_FILE")
for i in $(seq 0 $((DEAL_COUNT - 1))); do
  DEAL=$(jq ".deals[$i]" "$PIPELINE_FILE")

  PROSPECT=$(echo "$DEAL" | jq -r '.prospect')
  NEXT_DATE=$(echo "$DEAL" | jq -r '.next_action_date // "null"')
  NEXT_ACT=$(echo "$DEAL" | jq -r '.next_action // "Review"')
  STAGE=$(echo "$DEAL" | jq -r '.stage')
  STATUS=$(echo "$DEAL" | jq -r '.status // "active"')

  if [[ "$STATUS" == "won" || "$STATUS" == "lost" ]]; then continue; fi

  if [[ "$NEXT_DATE" != "null" ]]; then
    DAYS_UNTIL=$(days_since "$NEXT_DATE")
    # days_since returns positive for past dates
    if (( DAYS_UNTIL > 0 && DAYS_UNTIL < 999 )); then
      echo -e "  ${RED}⏰ OVERDUE${NC} ${BOLD}$PROSPECT${NC} — Action was due $NEXT_DATE ($DAYS_UNTIL days ago)"
      echo -e "     → $NEXT_ACT"
      ALERT_COUNT=$((ALERT_COUNT + 1))

      RELANCES_JSON=$(echo "$RELANCES_JSON" | jq --arg name "$PROSPECT" \
        --arg action "$NEXT_ACT" --arg date "$NEXT_DATE" --argjson days "$DAYS_UNTIL" \
        '. + [{"client_id": "pipeline", "name": $name, "level": "overdue", "days_since_contact": $days, "action": $action, "contact_email": "", "last_subject": "Pipeline: " + $date}]')
    elif (( DAYS_UNTIL == 0 )); then
      echo -e "  ${YELLOW}📅 TODAY${NC}  ${BOLD}$PROSPECT${NC} — Action due today"
      echo -e "     → $NEXT_ACT"
    else
      echo -e "  ${GREEN}✅ OK${NC}    ${BOLD}$PROSPECT${NC} — Next action: $NEXT_DATE"
    fi
  fi
done

echo ""

# ============================================================================
# Check 3: Email response tracking (sent emails without reply)
# ============================================================================
echo -e "${BOLD}3️⃣  Unanswered Outbound Email Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check sent emails in last 7 days
SENT_EMAILS=$(gog gmail list -a sales@orchestraintelligence.fr "in:sent newer_than:7d -in:trash" -p 2>/dev/null | grep "^[a-f0-9]" | head -10)

if [[ -n "$SENT_EMAILS" ]]; then
  SENT_COUNT=$(echo "$SENT_EMAILS" | wc -l | tr -d ' ')
  echo -e "  📧 $SENT_COUNT emails sent in last 7 days"

  # Check which ones got replies (simplified: look for threads)
  while IFS=$'\t' read -r MSG_ID DATE FROM SUBJECT REST; do
    # Check if the thread has replies
    if [[ "$SUBJECT" == *"Re:"* || "$SUBJECT" == *"RE:"* ]]; then
      continue  # This is already a reply
    fi

    # Extract recipient domain to check for response
    TO_INFO=$(echo "$REST" | cut -f1)
    echo -e "  📤 Sent: ${SUBJECT:0:60}... ($DATE)"
  done <<< "$SENT_EMAILS"
else
  echo -e "  ${GREEN}✅${NC} No sent emails to track (or GOG unavailable)"
fi

echo ""

# ============================================================================
# Check 4: Invoice tracking (via Qonto if available)
# ============================================================================
echo -e "${BOLD}4️⃣  Invoice & Payment Check${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

QONTO_SCRIPT="$HOME/Desktop/Alba/04-WORKSPACE/scripts/qonto_cli.py"
if [[ -f "$QONTO_SCRIPT" ]]; then
  echo -e "  📊 Qonto CLI available — run manually: python3 $QONTO_SCRIPT"
else
  echo -e "  ℹ️  Qonto CLI not found. Invoice tracking manual for now."
fi

# Check for invoice-related emails
INVOICE_EMAILS=$(gog gmail list -a sales@orchestraintelligence.fr "(facture OR invoice OR impayé OR overdue) newer_than:30d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")
echo -e "  📧 $INVOICE_EMAILS invoice-related emails in last 30 days"

echo ""

# ============================================================================
# Summary
# ============================================================================
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}📊 Relance Summary${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

TOTAL_RELANCES=$(echo "$RELANCES_JSON" | jq 'length')

if (( TOTAL_RELANCES == 0 )); then
  echo -e "${GREEN}✅ All clear — no relances needed today!${NC}"
else
  echo -e "  Total flags: ${BOLD}$TOTAL_RELANCES${NC}"
  echo -e "  Urgent (YOURS): ${RED}$URGENT_COUNT${NC}"
  echo -e "  Alerts (PREP): ${YELLOW}$((ALERT_COUNT - URGENT_COUNT))${NC}"
fi

# Save results
RELANCE_FILE="$OUTPUT_DIR/relances-$TIMESTAMP.json"
echo "$RELANCES_JSON" | jq '.' > "$RELANCE_FILE"
echo ""
echo -e "💾 Saved to ${BOLD}$RELANCE_FILE${NC}"

# ============================================================================
# Generate relance drafts for PREP items
# ============================================================================
PREP_COUNT=$(echo "$RELANCES_JSON" | jq '[.[] | select(.level == "alert")] | length')
if (( PREP_COUNT > 0 )); then
  echo ""
  echo -e "${BOLD}📝 PREP — Draft Relance Templates${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  echo "$RELANCES_JSON" | jq -c '.[] | select(.level == "alert")' | while read -r item; do
    NAME=$(echo "$item" | jq -r '.name')
    EMAIL=$(echo "$item" | jq -r '.contact_email')
    DAYS=$(echo "$item" | jq -r '.days_since_contact')
    LAST=$(echo "$item" | jq -r '.last_subject')

    echo ""
    echo -e "  ${YELLOW}📧 Relance: $NAME${NC}"
    echo "  To: $EMAIL"
    echo "  Subject: Suivi — Orchestra Intelligence x $NAME"
    echo "  ---"
    echo "  Bonjour,"
    echo ""
    echo "  Je me permets de revenir vers vous suite à notre dernier échange"
    echo "  (\"$LAST\" — il y a ${DAYS} jours)."
    echo ""
    echo "  Avez-vous eu l'occasion de réfléchir à notre proposition ?"
    echo "  Je reste disponible pour un point rapide si besoin."
    echo ""
    echo "  Cordialement,"
    echo "  Ludovic Goutel"
    echo "  Orchestra Intelligence"
    echo ""
  done
fi

if $JSON_OUTPUT; then
  echo ""
  cat "$RELANCE_FILE"
fi
