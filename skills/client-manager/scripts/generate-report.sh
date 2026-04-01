#!/usr/bin/env bash
# ============================================================================
# Client Status Report Generator — Orchestra Intelligence
# ============================================================================
# Generates a comprehensive Markdown report with health scores, pipeline,
# and actionable recommendations.
#
# Usage: ./generate-report.sh [--output <path>] [--no-email-check]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENTS_FILE="$SCRIPT_DIR/clients.json"
PIPELINE_FILE="$SCRIPT_DIR/pipeline.json"
OUTPUT_DIR="$SCRIPT_DIR/output"
TIMESTAMP=$(date +%Y-%m-%d)
TIME_NOW=$(date +%H:%M)
TODAY_EPOCH=$(date +%s)

OUTPUT_FILE="$OUTPUT_DIR/client-report-$TIMESTAMP.md"
SKIP_EMAIL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT_FILE="$2"; shift 2 ;;
    --no-email-check) SKIP_EMAIL=true; shift ;;
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
# Step 1: Run health scoring first
# ============================================================================
echo "📊 Running health scores..."
bash "$SCRIPT_DIR/health-score.sh" --quiet

HEALTH_FILE="$OUTPUT_DIR/health-scores-$TIMESTAMP.json"
if [[ ! -f "$HEALTH_FILE" ]]; then
  echo "Error: health scores file not generated"
  exit 1
fi

# ============================================================================
# Helper functions
# ============================================================================
days_since() {
  local date_str="$1"
  if [[ -z "$date_str" || "$date_str" == "null" ]]; then echo "N/A"; return; fi
  local target_epoch
  target_epoch=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null || echo "0")
  if [[ "$target_epoch" == "0" ]]; then echo "N/A"; return; fi
  local d=$(( (TODAY_EPOCH - target_epoch) / 86400 ))
  if (( d == 0 )); then echo "today"
  elif (( d == 1 )); then echo "yesterday"
  elif (( d < 7 )); then echo "${d} days ago"
  elif (( d < 30 )); then echo "$((d/7)) weeks ago"
  else echo "${d} days ago"
  fi
}

risk_emoji() {
  case "$1" in
    low) echo "🟢 Low" ;;
    medium) echo "🟡 Medium" ;;
    high) echo "🔴 High" ;;
    *) echo "⚪ Unknown" ;;
  esac
}

tier_emoji() {
  case "$1" in
    platinum) echo "🥇 Platinum" ;;
    gold) echo "🥈 Gold" ;;
    silver) echo "🥉 Silver" ;;
    bronze) echo "🟤 Bronze" ;;
    internal) echo "🏠 Internal" ;;
    prospect) echo "🎯 Prospect" ;;
    *) echo "📋 $1" ;;
  esac
}

stage_emoji() {
  case "$1" in
    lead) echo "📌 Lead" ;;
    contacted) echo "📧 Contacted" ;;
    meeting) echo "🤝 Meeting" ;;
    proposal) echo "📄 Proposal" ;;
    negotiation) echo "⚖️ Negotiation" ;;
    won) echo "✅ Won" ;;
    lost) echo "❌ Lost" ;;
    *) echo "$1" ;;
  esac
}

# ============================================================================
# Step 2: Gather recent email activity (if not skipped)
# ============================================================================
# Email activity cache file
EMAIL_CACHE="$OUTPUT_DIR/.email-cache-$TIMESTAMP"
if ! $SKIP_EMAIL; then
  echo "📧 Checking recent email activity..."
  {
    echo "wella=$(gog gmail list -a sales@orchestraintelligence.fr "from:wella.com newer_than:7d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")"
    echo "smart-renovation=$(gog gmail list -a sales@orchestraintelligence.fr "(smartrenovation OR smart\ renovation) newer_than:7d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")"
    echo "imagin-funeraire=$(gog gmail list -a sales@orchestraintelligence.fr "from:imagincommunication newer_than:7d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")"
    echo "carlance=$(gog gmail list -a sales@orchestraintelligence.fr "(from:carlance OR to:carlance) newer_than:7d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")"
    echo "revlon=$(gog gmail list -a sales@orchestraintelligence.fr "(from:revlon OR to:revlon) newer_than:7d" -p 2>/dev/null | grep -c "^[a-f0-9]" || echo "0")"
  } > "$EMAIL_CACHE"
fi

get_recent_emails() {
  local id="$1"
  if [[ -f "$EMAIL_CACHE" ]]; then
    grep "^${id}=" "$EMAIL_CACHE" 2>/dev/null | cut -d= -f2 || echo "N/A"
  else
    echo "N/A"
  fi
}

# ============================================================================
# Step 3: Build the report
# ============================================================================
echo "📝 Generating report..."

# Compute totals
TOTAL_MRR=$(jq '[.[].mrr] | add' "$HEALTH_FILE")
AVG_SCORE=$(jq '[.[].score] | add / length | floor' "$HEALTH_FILE")
ACTIVE_CLIENTS=$(jq '[.[] | select(.mrr > 0)] | length' "$HEALTH_FILE")
HIGH_RISK=$(jq '[.[] | select(.risk == "high")] | length' "$HEALTH_FILE")
MEDIUM_RISK=$(jq '[.[] | select(.risk == "medium")] | length' "$HEALTH_FILE")

# Pipeline totals
PIPELINE_DEALS=$(jq '.deals | length' "$PIPELINE_FILE")
PIPELINE_VALUE=$(jq '[.deals[] | (.estimated_mrr * .probability / 100)] | add | floor' "$PIPELINE_FILE")

cat > "$OUTPUT_FILE" <<HEADER
# 👥 Client Status Report — $TIMESTAMP

> Generated: $TIMESTAMP at $TIME_NOW CET by Alba Agent
> Source: GOG CLI (sales@orchestraintelligence.fr) + clients.json

---

## 📊 Portfolio Overview

| Metric | Value |
|--------|-------|
| **Total MRR** | **€$(printf "%'d" $TOTAL_MRR)** |
| **Portfolio Health** | **$AVG_SCORE/100** |
| **Active Revenue Clients** | $ACTIVE_CLIENTS |
| **High Risk** | $HIGH_RISK |
| **Medium Risk** | $MEDIUM_RISK |
| **Pipeline Deals** | $PIPELINE_DEALS |
| **Pipeline Weighted Value** | €$(printf "%'d" $PIPELINE_VALUE)/month |

---

## 📋 Client Health Matrix

| Client | Tier | MRR | Health | Last Contact | Risk |
|--------|------|-----|--------|-------------|------|
HEADER

# Add each client row
jq -c '.[]' "$HEALTH_FILE" | while read -r client; do
  ID=$(echo "$client" | jq -r '.id')
  NAME=$(echo "$client" | jq -r '.name')
  TIER=$(echo "$client" | jq -r '.tier')
  MRR=$(echo "$client" | jq -r '.mrr')
  SCORE=$(echo "$client" | jq -r '.score')
  RISK=$(echo "$client" | jq -r '.risk')
  LC=$(echo "$client" | jq -r '.last_contact')

  TIER_E=$(tier_emoji "$TIER")
  RISK_E=$(risk_emoji "$RISK")
  LC_HUMAN=$(days_since "$LC")

  if (( MRR > 0 )); then
    MRR_FMT="€$(printf "%'d" $MRR)"
  else
    MRR_FMT="—"
  fi

  echo "| **$NAME** | $TIER_E | $MRR_FMT | $SCORE/100 | $LC_HUMAN | $RISK_E |" >> "$OUTPUT_FILE"
done

# ============================================================================
# Step 4: Per-client detailed sections
# ============================================================================
cat >> "$OUTPUT_FILE" <<SECTION

---

## 📝 Per-Client Details

SECTION

CLIENT_COUNT=$(jq '.clients | length' "$CLIENTS_FILE")
for i in $(seq 0 $((CLIENT_COUNT - 1))); do
  CLIENT=$(jq ".clients[$i]" "$CLIENTS_FILE")

  ID=$(echo "$CLIENT" | jq -r '.id')
  NAME=$(echo "$CLIENT" | jq -r '.name')
  TIER=$(echo "$CLIENT" | jq -r '.tier')
  STATUS=$(echo "$CLIENT" | jq -r '.status')
  MRR=$(echo "$CLIENT" | jq -r '.contract.mrr // 0')
  PHASE=$(echo "$CLIENT" | jq -r '.project.current_phase // "N/A"')
  SCORE=$(echo "$CLIENT" | jq -r '.health.score // "N/A"')
  RISK=$(echo "$CLIENT" | jq -r '.health.risk_level // "unknown"')
  LC_DATE=$(echo "$CLIENT" | jq -r '.health.last_contact_date // "N/A"')
  LC_TYPE=$(echo "$CLIENT" | jq -r '.health.last_contact_type // "N/A"')
  LC_SUBJ=$(echo "$CLIENT" | jq -r '.health.last_contact_subject // "N/A"')
  MILESTONE=$(echo "$CLIENT" | jq -r '.project.next_milestone // "N/A"')
  NOTES=$(echo "$CLIENT" | jq -r '.notes // ""')

  TIER_E=$(tier_emoji "$TIER")
  RISK_E=$(risk_emoji "$RISK")
  LC_HUMAN=$(days_since "$LC_DATE")

  EMAILS_7D=$(get_recent_emails "$ID")

  cat >> "$OUTPUT_FILE" <<CLIENT_SECTION
### $TIER_E $NAME

| Field | Value |
|-------|-------|
| **Status** | $STATUS |
| **Phase** | $PHASE |
| **Health Score** | $SCORE/100 $RISK_E |
| **MRR** | €$MRR |
| **Last Contact** | $LC_HUMAN ($LC_DATE) via $LC_TYPE |
| **Last Subject** | $LC_SUBJ |
| **Emails (7d)** | $EMAILS_7D |
| **Next Milestone** | $MILESTONE |

CLIENT_SECTION

  # Open items
  OPEN_COUNT=$(echo "$CLIENT" | jq '.health.open_items | length')
  if (( OPEN_COUNT > 0 )); then
    echo "**Open Items:**" >> "$OUTPUT_FILE"
    for j in $(seq 0 $((OPEN_COUNT - 1))); do
      ITEM=$(echo "$CLIENT" | jq -r ".health.open_items[$j]")
      echo "- ⚠️ $ITEM" >> "$OUTPUT_FILE"
    done
    echo "" >> "$OUTPUT_FILE"
  fi

  # Recommendation
  echo "**Recommendation:**" >> "$OUTPUT_FILE"
  if [[ "$RISK" == "high" ]]; then
    echo "- 🔴 **URGENT**: Reactivate contact immediately. No meaningful engagement detected." >> "$OUTPUT_FILE"
  elif [[ "$RISK" == "medium" ]]; then
    echo "- 🟡 Schedule follow-up within 48h. Engagement is declining." >> "$OUTPUT_FILE"
  else
    echo "- 🟢 On track. Continue current cadence." >> "$OUTPUT_FILE"
  fi

  if [[ "$NOTES" != "" ]]; then
    echo "- 📌 $NOTES" >> "$OUTPUT_FILE"
  fi

  echo "" >> "$OUTPUT_FILE"
  echo "---" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
done

# ============================================================================
# Step 5: Sales Pipeline Section
# ============================================================================
cat >> "$OUTPUT_FILE" <<PIPELINE_HEADER

## 🎯 Sales Pipeline

| Deal | Prospect | Stage | Est. MRR | Probability | Next Action | Due |
|------|----------|-------|----------|-------------|-------------|-----|
PIPELINE_HEADER

DEAL_COUNT=$(jq '.deals | length' "$PIPELINE_FILE")
for i in $(seq 0 $((DEAL_COUNT - 1))); do
  DEAL=$(jq ".deals[$i]" "$PIPELINE_FILE")

  DEAL_ID=$(echo "$DEAL" | jq -r '.id')
  PROSPECT=$(echo "$DEAL" | jq -r '.prospect')
  STAGE=$(echo "$DEAL" | jq -r '.stage')
  EST_MRR=$(echo "$DEAL" | jq -r '.estimated_mrr')
  PROB=$(echo "$DEAL" | jq -r '.probability')
  NEXT_ACT=$(echo "$DEAL" | jq -r '.next_action // "—"')
  NEXT_DATE=$(echo "$DEAL" | jq -r '.next_action_date // "—"')

  STAGE_E=$(stage_emoji "$STAGE")

  echo "| $DEAL_ID | **$PROSPECT** | $STAGE_E | €$EST_MRR | ${PROB}% | $NEXT_ACT | $NEXT_DATE |" >> "$OUTPUT_FILE"
done

# ============================================================================
# Step 6: Alerts & Recommendations
# ============================================================================
cat >> "$OUTPUT_FILE" <<ALERTS_HEADER

---

## ⚠️ Alerts & Action Items

ALERTS_HEADER

ALERT_COUNT=0

# Check for high-risk clients
jq -c '.[] | select(.risk == "high")' "$HEALTH_FILE" | while read -r client; do
  NAME=$(echo "$client" | jq -r '.name')
  DAYS=$(echo "$client" | jq -r '.days_since_contact')
  echo "- 🔴 **$NAME** — No meaningful contact in ${DAYS}+ days. REACTIVATE immediately." >> "$OUTPUT_FILE"
  ALERT_COUNT=$((ALERT_COUNT + 1))
done

# Check for medium-risk clients
jq -c '.[] | select(.risk == "medium")' "$HEALTH_FILE" | while read -r client; do
  NAME=$(echo "$client" | jq -r '.name')
  DAYS=$(echo "$client" | jq -r '.days_since_contact')
  echo "- 🟡 **$NAME** — Contact declining (${DAYS} days). Schedule follow-up this week." >> "$OUTPUT_FILE"
  ALERT_COUNT=$((ALERT_COUNT + 1))
done

# Check pipeline deals past due
jq -c ".deals[] | select(.next_action_date < \"$TIMESTAMP\")" "$PIPELINE_FILE" 2>/dev/null | while read -r deal; do
  PROSPECT=$(echo "$deal" | jq -r '.prospect')
  ACTION=$(echo "$deal" | jq -r '.next_action')
  echo "- ⏰ **$PROSPECT** — Pipeline action overdue: $ACTION" >> "$OUTPUT_FILE"
done

# Check unanswered items
jq -c '.clients[] | select(.health.open_items | length > 3)' "$CLIENTS_FILE" | while read -r client; do
  NAME=$(echo "$client" | jq -r '.name')
  COUNT=$(echo "$client" | jq '.health.open_items | length')
  echo "- 📋 **$NAME** — $COUNT open items need attention." >> "$OUTPUT_FILE"
done

# Footer
cat >> "$OUTPUT_FILE" <<FOOTER

---

## 📅 Next Actions Summary

| Priority | Client | Action | Due |
|----------|--------|--------|-----|
FOOTER

# Generate next actions from pipeline
jq -c '.deals[] | select(.status != "won")' "$PIPELINE_FILE" 2>/dev/null | while read -r deal; do
  PROSPECT=$(echo "$deal" | jq -r '.prospect')
  ACTION=$(echo "$deal" | jq -r '.next_action // "Review status"')
  DUE=$(echo "$deal" | jq -r '.next_action_date // "ASAP"')
  PROB=$(echo "$deal" | jq -r '.probability // 0')

  if (( PROB >= 40 )); then PRIO="🔴 High"
  elif (( PROB >= 20 )); then PRIO="🟡 Medium"
  else PRIO="🟢 Low"
  fi

  echo "| $PRIO | **$PROSPECT** | $ACTION | $DUE |" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" <<FINAL

---

> 🤖 Report generated by Alba Agent — Orchestra Intelligence Client Manager
> Next update: $(date -v+1d +%Y-%m-%d) at 09:00 CET
FINAL

echo ""
echo "✅ Report generated: $OUTPUT_FILE"
echo "   $(wc -l < "$OUTPUT_FILE" | tr -d ' ') lines"
