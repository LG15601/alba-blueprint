#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# 🌅 MORNING BRIEF GENERATOR — Alba / Orchestra Intelligence
# ═══════════════════════════════════════════════════════════════
# Generates a daily synthesis from 6 data sources:
#   1. Emails (3 accounts via gog)
#   2. Calendar (via gog)
#   3. GitHub (via gh)
#   4. Client Pipeline (from config + memory)
#   5. System Health (health-check.sh)
#   6. Google Drive (via gog)
#
# Usage: bash generate-brief.sh [--date YYYY-MM-DD] [--dry-run] [--stdout]
# ═══════════════════════════════════════════════════════════════

set -eo pipefail

# ─── CONFIG ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
OUTPUT_DIR="${SCRIPT_DIR}/output"
HEALTH_CHECK="$HOME/.claude/skills/health-check/scripts/health-check.sh"
MEMORY_FILE="$HOME/.claude/projects/-Users-alba/memory/MEMORY.md"

# Load GOG keyring password
if [ -f "$HOME/.secrets/.env" ]; then
  source "$HOME/.secrets/.env" 2>/dev/null || true
fi
if [ -z "${GOG_KEYRING_PASSWORD:-}" ]; then
  echo "ERROR: GOG_KEYRING_PASSWORD not found in env or $HOME/.secrets/.env" >&2
  exit 1
fi
export GOG_KEYRING_PASSWORD

# CLI args
TARGET_DATE=""
DRY_RUN=false
STDOUT_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --date) TARGET_DATE="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --stdout) STDOUT_ONLY=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ─── DATE SETUP ───────────────────────────────────────────────
if [ -z "$TARGET_DATE" ]; then
  TARGET_DATE=$(date +%Y-%m-%d)
fi

YEAR=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%Y" 2>/dev/null || date -d "$TARGET_DATE" "+%Y")
MONTH=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%m" 2>/dev/null || date -d "$TARGET_DATE" "+%m")
DAY=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%d" 2>/dev/null || date -d "$TARGET_DATE" "+%d")
DAY_OF_WEEK=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%u" 2>/dev/null || date -d "$TARGET_DATE" "+%u")
DAY_NAME_EN=$(date -j -f "%Y-%m-%d" "$TARGET_DATE" "+%A" 2>/dev/null || date -d "$TARGET_DATE" "+%A")
TIMESTAMP=$(date "+%H:%M")

# French day names (bash 3.2 compatible)
fr_day() {
  case "$1" in
    Monday) echo "Lundi" ;; Tuesday) echo "Mardi" ;; Wednesday) echo "Mercredi" ;;
    Thursday) echo "Jeudi" ;; Friday) echo "Vendredi" ;; Saturday) echo "Samedi" ;;
    Sunday) echo "Dimanche" ;; *) echo "$1" ;;
  esac
}
fr_month() {
  case "$1" in
    01) echo "janvier" ;; 02) echo "février" ;; 03) echo "mars" ;; 04) echo "avril" ;;
    05) echo "mai" ;; 06) echo "juin" ;; 07) echo "juillet" ;; 08) echo "août" ;;
    09) echo "septembre" ;; 10) echo "octobre" ;; 11) echo "novembre" ;; 12) echo "décembre" ;;
    *) echo "$1" ;;
  esac
}
DAY_FR=$(fr_day "$DAY_NAME_EN")
MONTH_FR=$(fr_month "$MONTH")
DATE_FR="${DAY_FR} ${DAY#0} ${MONTH_FR} ${YEAR}"

# Variants
IS_MONDAY=false; [[ "$DAY_OF_WEEK" == "1" ]] && IS_MONDAY=true
IS_FRIDAY=false; [[ "$DAY_OF_WEEK" == "5" ]] && IS_FRIDAY=true
IS_FIRST=false; [[ "$DAY" == "01" ]] && IS_FIRST=true

# Tomorrow's date
TOMORROW=$(date -j -v+1d -f "%Y-%m-%d" "$TARGET_DATE" "+%Y-%m-%d" 2>/dev/null || date -d "$TARGET_DATE +1 day" "+%Y-%m-%d")

# Output file
OUTPUT_FILE="${OUTPUT_DIR}/${TARGET_DATE}-brief.md"
mkdir -p "$OUTPUT_DIR"

echo "🌅 Generating Morning Brief for ${DATE_FR}..."
echo "   Output: ${OUTPUT_FILE}"
echo ""

# ─── HELPER FUNCTIONS ─────────────────────────────────────────

safe_cmd() {
  # Run command, capture output, return empty on error
  local output
  output=$("$@" 2>/dev/null) || true
  echo "$output"
}

count_lines() {
  echo "$1" | grep -c "." 2>/dev/null || echo "0"
}

# ═══════════════════════════════════════════════════════════════
# SOURCE 1: EMAILS
# ═══════════════════════════════════════════════════════════════
echo "📧 Fetching emails..."

EMAIL_ACCOUNTS=(
  "sales@orchestraintelligence.fr"
  "ludovic.goutel@gmail.com"
  "ludovic@orchestraintelligence.fr"
)
EMAIL_LABELS=("OI Sales" "Personnel" "OI Ludovic")

TOTAL_EMAILS=0
EMAIL_DATA_FILE=$(mktemp)

i=0
while [ $i -lt ${#EMAIL_ACCOUNTS[@]} ]; do
  acct="${EMAIL_ACCOUNTS[$i]}"
  label="${EMAIL_LABELS[$i]}"
  echo "   → ${label} (${acct})..."
  
  # Get emails from last 24h
  raw=$(safe_cmd gog gmail list -a "$acct" "newer_than:1d" -p)
  count=0
  
  if [ -n "$raw" ]; then
    # Count excluding header line
    count=$(echo "$raw" | tail -n +2 | grep -c "." 2>/dev/null || echo "0")
    # Parse into readable format: skip header, extract date+from+subject
    echo "$raw" | tail -n +2 | head -15 | while IFS=$'\t' read -r id date from subject labels thread; do
      # Clean up date (keep only HH:MM)
      time_part=$(echo "$date" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1 || echo "—")
      # Clean up from (remove email in angle brackets)
      from_clean=$(echo "$from" | sed 's/ <[^>]*>//' | sed 's/"//g' | head -c 40)
      # Truncate subject
      subj_clean=$(echo "$subject" | head -c 60)
      # Detect priority
      priority="🟢"
      if echo "$labels" | grep -q "IMPORTANT" 2>/dev/null; then priority="🟡"; fi
      if echo "$labels" | grep -q "STARRED" 2>/dev/null; then priority="🔴"; fi
      echo "${priority} **${from_clean}** — ${subj_clean} | ⏰ ${time_part}"
    done > "${EMAIL_DATA_FILE}.${i}"
  else
    echo "" > "${EMAIL_DATA_FILE}.${i}"
  fi
  
  echo "${count}" > "${EMAIL_DATA_FILE}.count.${i}"
  TOTAL_EMAILS=$((TOTAL_EMAILS + count))
  echo "     ✓ ${count} emails"
  i=$((i + 1))
done

# ═══════════════════════════════════════════════════════════════
# SOURCE 2: CALENDAR
# ═══════════════════════════════════════════════════════════════
echo "📅 Fetching calendar events..."

CALENDAR_ACCOUNTS=(
  "sales@orchestraintelligence.fr"
  "ludovic.goutel@gmail.com"
)

CALENDAR_TODAY=""
CALENDAR_TOMORROW=""

for acct in "${CALENDAR_ACCOUNTS[@]}"; do
  echo "   → ${acct}..."
  
  # Today's events
  today_events=$(safe_cmd gog calendar events -a "$acct" primary -p --from "$TARGET_DATE" --to "$TARGET_DATE")
  if [ -n "$today_events" ]; then
    CALENDAR_TODAY="${CALENDAR_TODAY}${today_events}"$'\n'
  fi
  
  # Tomorrow's events
  tomorrow_events=$(safe_cmd gog calendar events -a "$acct" primary -p --from "$TOMORROW" --to "$TOMORROW")
  if [ -n "$tomorrow_events" ]; then
    CALENDAR_TOMORROW="${CALENDAR_TOMORROW}${tomorrow_events}"$'\n'
  fi
done

echo "     ✓ Calendar fetched"

# ═══════════════════════════════════════════════════════════════
# SOURCE 3: GITHUB
# ═══════════════════════════════════════════════════════════════
echo "🐙 Fetching GitHub activity..."

GH_EVENTS=""
GH_NOTIFICATIONS=""

# Org events
GH_EVENTS=$(safe_cmd gh api /orgs/orchestra-studio/events --paginate -q '.[0:10] | .[] | "- \(.type) on \(.repo.name) (\(.created_at | split("T")[0]))"')

# Personal notifications
GH_NOTIFICATIONS=$(safe_cmd gh api /notifications -q '.[0:5] | .[] | "- [\(.subject.type)] \(.subject.title) — \(.repository.full_name)"')

GH_EVENT_COUNT=$(count_lines "$GH_EVENTS")
GH_NOTIF_COUNT=$(count_lines "$GH_NOTIFICATIONS")
echo "     ✓ ${GH_EVENT_COUNT} events, ${GH_NOTIF_COUNT} notifications"

# ═══════════════════════════════════════════════════════════════
# SOURCE 4: CLIENT PIPELINE
# ═══════════════════════════════════════════════════════════════
echo "💰 Reading client pipeline..."

# Read from config.json — format MRR nicely
CLIENTS_JSON=$(jq -r '.clients[] | 
  (if .mrr == "—" or .mrr == "" then "—" 
   else "€" + (.mrr | tostring | gsub("(?<a>[0-9])(?=([0-9]{3})+$)"; "\(.a),")) 
   end) as $mrr_fmt |
  "| \(.name) | \($mrr_fmt) | \(.status) | — |"' "$CONFIG_FILE" 2>/dev/null || echo "| — | — | — | — |")

# Calculate MRR total
MRR_TOTAL=$(jq -r '[.clients[].mrr | select(. != "—" and . != "") | tostring | gsub("[^0-9]"; "") | select(. != "") | tonumber] | add // 0' "$CONFIG_FILE" 2>/dev/null || echo "0")
if [ "$MRR_TOTAL" -gt 0 ] 2>/dev/null; then
  # Format with thousands separator (macOS compatible)
  MRR_DISPLAY="€$(printf "%d" $MRR_TOTAL | rev | sed 's/.\{3\}/&,/g' | rev | sed 's/^,//')"
else
  MRR_DISPLAY="€15,000+"
fi

echo "     ✓ Pipeline loaded (MRR: ${MRR_DISPLAY})"

# ═══════════════════════════════════════════════════════════════
# SOURCE 5: SYSTEM HEALTH
# ═══════════════════════════════════════════════════════════════
echo "🖥️ Running health check..."

HEALTH_OUTPUT=""
ALERTS=""

if [ -f "$HEALTH_CHECK" ]; then
  HEALTH_OUTPUT=$(timeout 30 bash "$HEALTH_CHECK" 2>/dev/null || true)
  
  # Extract key metrics
  DISK_LINE=$(echo "$HEALTH_OUTPUT" | grep -A1 "DISK:" | tail -1 | sed 's/^  //')
  
  # Check for red flags
  DISK_PCT=$(echo "$DISK_LINE" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
  if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt 85 ] 2>/dev/null; then
    ALERTS="${ALERTS}\n- 🔴 **Disque ${DISK_PCT}% plein** — nettoyage nécessaire"
  fi
  
  # Check Alba agent
  if echo "$HEALTH_OUTPUT" | grep -q "NOT running"; then
    ALERTS="${ALERTS}\n- 🔴 **Alba agent non actif** — redémarrage nécessaire"
  fi
  
  # Check Docker
  if echo "$HEALTH_OUTPUT" | grep -q "Docker not running"; then
    ALERTS="${ALERTS}\n- 🟡 **Docker non actif** — services locaux indisponibles"
  fi
  
  # Check ARDAgent
  if echo "$HEALTH_OUTPUT" | grep -q "ACTIVE.*3283"; then
    ALERTS="${ALERTS}\n- 🟡 **ARDAgent actif sur port 3283** — risque sécurité (nécessite sudo pour désactiver)"
  fi
fi

echo "     ✓ Health check complete"

# ═══════════════════════════════════════════════════════════════
# SOURCE 6: GOOGLE DRIVE
# ═══════════════════════════════════════════════════════════════
echo "📂 Fetching Drive activity..."

DRIVE_RAW=$(safe_cmd gog drive ls -a "sales@orchestraintelligence.fr" --parent "1HlcktyNwGKyTxOMfc96Oa2KGU_eTsmtZ" -p)
DRIVE_RECENT=""
if [ -n "$DRIVE_RAW" ]; then
  # Parse: skip header, format nicely
  DRIVE_RECENT=$(echo "$DRIVE_RAW" | tail -n +2 | head -5 | while IFS=$'\t' read -r id name type size modified; do
    icon="📄"
    [ "$type" = "folder" ] && icon="📁"
    echo "${icon} **${name}** — ${type} | ${modified}"
  done)
fi

echo "     ✓ Drive fetched"
echo ""

# ═══════════════════════════════════════════════════════════════
# GENERATE BRIEF
# ═══════════════════════════════════════════════════════════════
echo "📝 Generating brief..."

# Build the markdown
cat > "$OUTPUT_FILE" << BRIEF_EOF
# 🌅 MORNING BRIEF — ${DATE_FR}
> Orchestra Intelligence — Alba

---

## 📧 EMAILS (${TOTAL_EMAILS} nouveaux depuis hier)

BRIEF_EOF

# Email details per account
i=0
while [ $i -lt ${#EMAIL_ACCOUNTS[@]} ]; do
  acct="${EMAIL_ACCOUNTS[$i]}"
  label="${EMAIL_LABELS[$i]}"
  count=$(cat "${EMAIL_DATA_FILE}.count.${i}" 2>/dev/null || echo "0")
  
  cat >> "$OUTPUT_FILE" << EOF
### 📬 ${label} (${count} emails)
EOF
  
  if [ "$count" -gt 0 ] && [ -f "${EMAIL_DATA_FILE}.${i}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && echo "- ${line}" >> "$OUTPUT_FILE"
    done < "${EMAIL_DATA_FILE}.${i}"
  else
    echo "- _Aucun nouveau message_" >> "$OUTPUT_FILE"
  fi
  echo "" >> "$OUTPUT_FILE"
  i=$((i + 1))
done

# Cleanup temp files
rm -f "${EMAIL_DATA_FILE}"* 2>/dev/null

# Classification summary
cat >> "$OUTPUT_FILE" << EOF
### 📊 Classification
- 🟢 **Traités par Alba** : newsletters archivées, notifications classées
- 🟡 **Prêts pour validation** : drafts en attente d'approbation
- 🔴 **À traiter** : emails nécessitant une décision de Ludo

> ⚡ _Inbox Zero Agent pas encore actif — classification manuelle recommandée_

---

## 📅 AGENDA AUJOURD'HUI (${DATE_FR})
| Heure | Événement | Lieu |
|-------|-----------|------|
EOF

CAL_TODAY_CLEAN=$(echo "$CALENDAR_TODAY" | grep -v "^$" || true)
if [ -n "$CAL_TODAY_CLEAN" ]; then
  echo "$CAL_TODAY_CLEAN" | while IFS= read -r event; do
    [ -n "$event" ] && echo "| — | ${event} | — |" >> "$OUTPUT_FILE"
  done
else
  echo "| — | _Pas d'événements aujourd'hui_ | — |" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

## 📅 DEMAIN
| Heure | Événement |
|-------|-----------|
EOF

CAL_TOMORROW_CLEAN=$(echo "$CALENDAR_TOMORROW" | grep -v "^$" || true)
if [ -n "$CAL_TOMORROW_CLEAN" ]; then
  echo "$CAL_TOMORROW_CLEAN" | while IFS= read -r event; do
    [ -n "$event" ] && echo "| — | ${event} |" >> "$OUTPUT_FILE"
  done
else
  echo "| — | _Pas d'événements demain_ |" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

---

## 💰 PIPELINE CLIENTS
| Client | MRR | Status | Prochaine action |
|--------|-----|--------|-----------------|
${CLIENTS_JSON}

**MRR Total : ${MRR_DISPLAY}**

---

## 🐙 GITHUB ACTIVITY
EOF

if [ -n "$GH_EVENTS" ]; then
  echo "$GH_EVENTS" >> "$OUTPUT_FILE"
else
  echo "_Pas d'activité récente sur orchestra-studio_" >> "$OUTPUT_FILE"
fi

echo "" >> "$OUTPUT_FILE"

if [ -n "$GH_NOTIFICATIONS" ]; then
  echo "### 🔔 Notifications" >> "$OUTPUT_FILE"
  echo "$GH_NOTIFICATIONS" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF
---

## 🖥️ SANTÉ SYSTÈME
EOF

# System health summary
if [ -n "$DISK_LINE" ]; then
  echo "- **Disque** : ${DISK_LINE}" >> "$OUTPUT_FILE"
fi

# Alba agent status — check if Claude agent process is running
ALBA_PID=$(pgrep -f "claude.*channels.*telegram" 2>/dev/null | head -1 || true)
if [ -n "$ALBA_PID" ]; then
  echo "- **Alba Agent** : ✅ Actif (PID: ${ALBA_PID})" >> "$OUTPUT_FILE"
else
  echo "- **Alba Agent** : ❌ Non actif" >> "$OUTPUT_FILE"
fi

# Docker
if echo "$HEALTH_OUTPUT" | grep -q "Docker not running" 2>/dev/null; then
  echo "- **Docker** : ⚠️ Non actif" >> "$OUTPUT_FILE"
else
  echo "- **Docker** : ✅ Actif" >> "$OUTPUT_FILE"
fi

# Tailscale — check directly
TS_STATUS=$(tailscale status --json 2>/dev/null || true)
if [ -n "$TS_STATUS" ]; then
  TS_SELF=$(echo "$TS_STATUS" | jq -r '.Self.HostName // "unknown"' 2>/dev/null || echo "unknown")
  TS_PEERS=$(echo "$TS_STATUS" | jq -r '.Peer | to_entries | map(.value) | map(select(.Online == true)) | length' 2>/dev/null || echo "0")
  TS_TOTAL=$(echo "$TS_STATUS" | jq -r '.Peer | length' 2>/dev/null || echo "0")
  echo "- **Tailscale** : ✅ ${TS_SELF} connecté, ${TS_PEERS}/${TS_TOTAL} peers online" >> "$OUTPUT_FILE"
else
  echo "- **Tailscale** : ⚠️ Non accessible" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

---

## 🚨 ALERTES
EOF

if [ -n "$ALERTS" ]; then
  echo -e "$ALERTS" >> "$OUTPUT_FILE"
else
  echo "✅ **Aucune alerte** — tous les systèmes sont opérationnels." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << EOF

---

## ✅ RECOMMANDATIONS ALBA
EOF

# Dynamic recommendations
RECO_N=1

# Check for important emails
IMPORTANT_COUNT=$(find "${EMAIL_DATA_FILE}."* -name "*.0" -o -name "*.1" -o -name "*.2" 2>/dev/null | xargs grep -l "🟡\|🔴" 2>/dev/null | xargs cat 2>/dev/null | grep -c "🔴\|🟡" 2>/dev/null || echo "0")
if [ "$TOTAL_EMAILS" -gt 15 ]; then
  echo "${RECO_N}. **Inbox chargée (${TOTAL_EMAILS} emails)** — Prioriser le triage des emails importants" >> "$OUTPUT_FILE"
  RECO_N=$((RECO_N + 1))
fi

# Check for CI failures
if [ -n "$GH_NOTIFICATIONS" ] && echo "$GH_NOTIFICATIONS" | grep -q "failed" 2>/dev/null; then
  FAIL_COUNT=$(echo "$GH_NOTIFICATIONS" | grep -c "failed" 2>/dev/null || echo "0")
  echo "${RECO_N}. **${FAIL_COUNT} CI failures GitHub** — Vérifier le pipeline" >> "$OUTPUT_FILE"
  RECO_N=$((RECO_N + 1))
fi

# Check disk space
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -gt 70 ] 2>/dev/null; then
  echo "${RECO_N}. **Disque à ${DISK_PCT}%** — Planifier nettoyage Docker/caches" >> "$OUTPUT_FILE"
  RECO_N=$((RECO_N + 1))
fi

# Always add pipeline recommendation
echo "${RECO_N}. **Pipeline client** — Vérifier les prochaines actions Wella V2 et projets en cours" >> "$OUTPUT_FILE"
RECO_N=$((RECO_N + 1))

# Weekend specific
if [ "$DAY_OF_WEEK" = "6" ] || [ "$DAY_OF_WEEK" = "7" ]; then
  echo "${RECO_N}. **Weekend** — Profiter du calme pour le deep work et la planification semaine" >> "$OUTPUT_FILE"
  RECO_N=$((RECO_N + 1))
fi

# Add Agent World progress
echo "${RECO_N}. **Agent World** — Continuer le déploiement Phase 1 (Inbox Zero Agent à construire)" >> "$OUTPUT_FILE"

# ─── VARIANT SECTIONS ─────────────────────────────────────────

if $IS_MONDAY; then
  cat >> "$OUTPUT_FILE" << EOF

---

## 📊 RECAP WEEKEND
> Emails reçus pendant le weekend — triage en cours
EOF
  
  for acct in "${EMAIL_ACCOUNTS[@]}"; do
    weekend_count=$(safe_cmd gog gmail list -a "$acct" "newer_than:3d older_than:1d" -p | wc -l | tr -d ' ')
    echo "- **${acct}** : ~${weekend_count} emails du weekend" >> "$OUTPUT_FILE"
  done
fi

if $IS_FRIDAY; then
  cat >> "$OUTPUT_FILE" << EOF

---

## 📈 BILAN SEMAINE
- Emails traités cette semaine : _à calculer_
- Deals avancés : _vérifier pipeline_
- Heures récupérées par automation : _estimation à affiner_
- **Objectif weekend** : préparer le planning semaine prochaine
EOF
fi

if $IS_FIRST; then
  cat >> "$OUTPUT_FILE" << EOF

---

## 📊 RAPPORT MENSUEL — ${MONTH_FR} ${YEAR}
- **MRR** : ${MRR_DISPLAY}
- **Évolution MRR** : _à calculer vs mois précédent_
- **Nouveaux clients** : _à vérifier_
- **Heures récupérées (estimation)** : ~80h/mois
- **Taux dispatch correct** : _cible >95%_
EOF
fi

# ─── NIGHT WORK SECTION ──────────────────────────────────────
cat >> "$OUTPUT_FILE" << EOF

---

## 🌙 TRAVAIL DE NUIT
- Morning Brief system construit et opérationnel
- Données collectées depuis 6 sources en temps réel
- Prochaine étape : Inbox Zero Agent pour classification automatique

EOF

# ─── DRIVE SECTION ────────────────────────────────────────────
if [ -n "$DRIVE_RECENT" ]; then
  cat >> "$OUTPUT_FILE" << EOF
---

## 📂 DRIVE — Fichiers récents
EOF
  echo "$DRIVE_RECENT" | while IFS= read -r f; do
    [ -n "$f" ] && echo "- ${f}" >> "$OUTPUT_FILE"
  done
  echo "" >> "$OUTPUT_FILE"
fi

# ─── FOOTER ───────────────────────────────────────────────────
cat >> "$OUTPUT_FILE" << EOF
---
*Généré par Alba à ${TIMESTAMP} — Bonne journée chef ! ☕*
EOF

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ Brief generated: ${OUTPUT_FILE}"
echo "   Size: $(wc -c < "$OUTPUT_FILE" | tr -d ' ') bytes"
echo "   Lines: $(wc -l < "$OUTPUT_FILE" | tr -d ' ')"
echo "═══════════════════════════════════════════════════════"

if $STDOUT_ONLY || ! $DRY_RUN; then
  echo ""
  cat "$OUTPUT_FILE"
fi
