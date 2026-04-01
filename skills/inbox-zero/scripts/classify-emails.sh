#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# classify-emails.sh — Inbox Zero Email Classifier (DPYS)
# Orchestra Intelligence — Agent World
# ═══════════════════════════════════════════════════════════════
# Classifies emails into: DISPATCH / PREP / YOURS / SKIP
# Engine: Rule-based with keyword matching + domain analysis
# Optional: Claude API (Haiku) for ambiguous cases
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.json"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOGS_DIR="${SCRIPT_DIR}/logs"
DATE_SLUG=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)

# ── Input: scan file (argument or today's) ──
SCAN_FILE="${1:-${OUTPUT_DIR}/${DATE_SLUG}-scan.json}"
if [ ! -f "$SCAN_FILE" ]; then
  echo "ERROR: Scan file not found: ${SCAN_FILE}" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

log() {
  local msg="[$(date +%H:%M:%S)] $1"
  echo "$msg" >> "${LOGS_DIR}/classify-${DATE_SLUG}.log"
  echo "$msg" >&2
}

# ══════════════════════════════════════════════════════════════
# CLASSIFICATION RULES ENGINE
# ══════════════════════════════════════════════════════════════

classify_email() {
  local email_json="$1"

  local from subject body labels account
  from=$(echo "$email_json" | jq -r '.from // ""' | tr '[:upper:]' '[:lower:]')
  subject=$(echo "$email_json" | jq -r '.subject // ""')
  subject_lower=$(echo "$subject" | tr '[:upper:]' '[:lower:]')
  body=$(echo "$email_json" | jq -r '.body // ""')
  body_lower=$(echo "$body" | tr '[:upper:]' '[:lower:]')
  labels_raw=$(echo "$email_json" | jq -r '.labels[]? // ""' 2>/dev/null)
  account=$(echo "$email_json" | jq -r '.account // ""')
  msg_id=$(echo "$email_json" | jq -r '.id // ""')

  # Extract sender domain
  local sender_domain sender_email
  sender_email=$(echo "$from" | grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+' | head -1 | tr '[:upper:]' '[:lower:]')
  sender_domain=$(echo "$sender_email" | cut -d'@' -f2)

  local classification="prep"  # Default: safe
  local confidence=0.5
  local priority="normal"
  local client="unknown"
  local reasoning=""
  local suggested_action=""
  local suggested_agent="alba-ceo"

  # ────────────────────────────────────────────────────
  # RULE 1: SKIP — Promotions / Social / Spam labels
  # ────────────────────────────────────────────────────
  if echo "$labels_raw" | grep -qiE "CATEGORY_PROMOTIONS|SPAM"; then
    classification="skip"
    confidence=0.95
    priority="low"
    reasoning="Gmail auto-categorized as promotions/spam"
    suggested_action="archive"
  fi

  if echo "$labels_raw" | grep -qi "CATEGORY_SOCIAL"; then
    classification="skip"
    confidence=0.90
    priority="low"
    reasoning="Social media notification"
    suggested_action="archive"
  fi

  # ────────────────────────────────────────────────────
  # RULE 2: SKIP — Known skip domains
  # ────────────────────────────────────────────────────
  local skip_domains="mail-rachat.lacentrale.fr leboncoin.fr cdiscount.com amazon.fr aliexpress.com wish.com shein.com temu.com deliveroo.fr deliveroo.com pinterest.com lafourche.fr ariase.com octobre.com ironman.com stello.fr hostinger.com smartlead.ai bolt.new replit.com bubble.io lindy.ai paradigm.xyz"
  for sd in $skip_domains; do
    if echo "$sender_domain" | grep -qi "$sd"; then
      classification="skip"
      confidence=0.95
      priority="low"
      reasoning="Known skip domain: ${sd}"
      suggested_action="archive"
      break
    fi
  done

  # ────────────────────────────────────────────────────
  # RULE 3: DISPATCH — Known automation/service domains
  # ────────────────────────────────────────────────────
  local dispatch_domains="github.com vercel.com supabase.io supabase.com render.com fly.io hetzner.com tailscale.com docker.com stripe.com qonto.com google.com reclaim.ai 404works.com openai.com medium.com protonmail.com proton.me ariba.com sap.com lego.com"
  if [ "$classification" != "skip" ]; then
    for dd in $dispatch_domains; do
      if echo "$sender_domain" | grep -qi "$dd"; then
        classification="dispatch"
        confidence=0.90
        priority="low"
        reasoning="Automated notification from ${dd}"
        suggested_action="log_and_archive"
        suggested_agent="code-ops"

        # Upgrade priority for billing/invoices
        if echo "$subject_lower" | grep -qiE "invoice|receipt|facture|reçu|payment|paiement|billing"; then
          priority="normal"
          reasoning="Billing notification from ${dd}"
          suggested_action="log_to_comptabilite"
          suggested_agent="comptabilite"
        fi

        # CI failures get higher priority
        if echo "$subject_lower" | grep -qiE "failed|failure|error|broken|échec"; then
          priority="high"
          reasoning="CI/Build failure from ${dd}"
          suggested_action="investigate"
        fi
        break
      fi
    done
  fi

  # ────────────────────────────────────────────────────
  # RULE 4: DISPATCH — Newsletters / noreply
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ]; then
    if echo "$sender_email" | grep -qiE "^(noreply|no-reply|newsletter|news@|mailer-daemon|notification|digest|updates|info@)"; then
      classification="dispatch"
      confidence=0.85
      priority="low"
      reasoning="Automated/noreply sender"
      suggested_action="log_and_archive"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 4b: SKIP — Newsletter / marketing patterns
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    if echo "$subject_lower" | grep -qiE "newsletter|weekly digest|weekly report|changelog|what.s new|kicks off|offerts|offre spéciale|% off|promo code|free trial|limited time|your subscription|now available in|try for free|introducing .* in |économisez|save up to"; then
      classification="skip"
      confidence=0.82
      priority="low"
      reasoning="Newsletter/marketing pattern detected in subject"
      suggested_action="archive"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 4c: DISPATCH — SaaS tool updates
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    local saas_domains="flutterflow.io attio.com augmentcode.com warp.dev cursor.com cursor.sh notion.so geelark.com startups.fyi"
    for sd2 in $saas_domains; do
      if echo "$sender_domain" | grep -qi "$sd2"; then
        classification="dispatch"
        confidence=0.85
        priority="low"
        reasoning="SaaS tool notification from ${sd2}"
        suggested_action="log_and_archive"
        break
      fi
    done
  fi

  # ────────────────────────────────────────────────────
  # RULE 5: YOURS — VIP / Tier 1 clients (OVERRIDE)
  # ────────────────────────────────────────────────────
  local vip_domains="wella.com henkel.com schwarzkopf.com"
  for vd in $vip_domains; do
    if echo "$sender_domain" | grep -qi "$vd"; then
      classification="prep"  # Minimum prep, check for yours
      confidence=0.90
      priority="high"
      client="wella"
      reasoning="VIP Tier 1 client: ${vd}"
      suggested_action="prepare_dossier"
      suggested_agent="client-manager"

      # Check if it needs to be YOURS (negotiation, urgent)
      if echo "$subject_lower $body_lower" | grep -qiE "urgent|asap|contrat|contract|négocia|negotiat|prix|price|budget|deadline"; then
        classification="yours"
        priority="critical"
        reasoning="VIP client with urgency/negotiation signals"
        suggested_action="immediate_attention"
      fi
      break
    fi
  done

  # ────────────────────────────────────────────────────
  # RULE 6: PREP — Tier 2-3 clients
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    local t2_domains="smartrenovation.ae smart-renovation.com"
    for td in $t2_domains; do
      if echo "$sender_domain" | grep -qi "$td"; then
        client="smart-renovation"
        priority="high"
        reasoning="Active client: Smart Renovation"
        suggested_action="prepare_response"
        suggested_agent="client-manager"
        break
      fi
    done

    local t3_domains="winppi.com molie.fr carlance.fr imagin-funeraire.fr"
    for td in $t3_domains; do
      if echo "$sender_domain" | grep -qi "$td"; then
        client=$(echo "$td" | cut -d'.' -f1)
        priority="normal"
        reasoning="Regular client: ${td}"
        suggested_action="prepare_response"
        suggested_agent="client-manager"
        break
      fi
    done
  fi

  # ────────────────────────────────────────────────────
  # RULE 7: YOURS — Negative tone / escalation signals
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] || [ "$classification" = "dispatch" ]; then
    if echo "$subject_lower $body_lower" | grep -qiE "mécontent|déçu|furieux|inacceptable|disappointed|angry|unacceptable|frustrated|problème grave|serious issue|escalation|plainte|complaint"; then
      classification="yours"
      confidence=0.85
      priority="critical"
      reasoning="Negative tone / escalation detected"
      suggested_action="immediate_attention"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 8: YOURS — Legal / RGPD / Contract keywords
  # ────────────────────────────────────────────────────
  if [ "$classification" != "skip" ] && [ "$classification" != "yours" ]; then
    if echo "$subject_lower $body_lower" | grep -qiE "juridique|legal|rgpd|gdpr|contrat|contract|avocat|lawyer|tribunal|court|huissier|mise en demeure|formal notice"; then
      classification="yours"
      confidence=0.90
      priority="critical"
      reasoning="Legal/compliance content detected"
      suggested_action="immediate_review"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 9: PREP — New business / prospect signals
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    if echo "$subject_lower $body_lower" | grep -qiE "devis|quote|budget|tarif|pricing|proposition|proposal|collaboration|partenariat|partnership|intéressé|interested"; then
      client="prospect"
      priority="high"
      reasoning="Potential new business inquiry"
      suggested_action="prepare_response_and_qualify"
      suggested_agent="sales-pipeline"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 10: PREP — Meeting requests
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] || [ "$classification" = "dispatch" ]; then
    if echo "$subject_lower $body_lower" | grep -qiE "rendez-vous|meeting|réunion|call|appel|disponibilité|availability|calendly|slot|créneau"; then
      if [ "$classification" = "dispatch" ]; then
        classification="prep"
      fi
      confidence=0.80
      reasoning="${reasoning}; Meeting request detected"
      suggested_action="check_calendar_and_propose"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 11: DISPATCH — Subject keyword dispatchers
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    if echo "$subject_lower" | grep -qiE "receipt|reçu|confirmation|password reset|verify|shipping|livraison|tracking|subscription renewed|welcome to"; then
      classification="dispatch"
      confidence=0.88
      priority="low"
      reasoning="Transactional/automated email based on subject"
      suggested_action="log_and_archive"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 12: Business account boost — unknown senders
  # ────────────────────────────────────────────────────
  if [ "$classification" = "prep" ] && [ "$client" = "unknown" ]; then
    if echo "$account" | grep -qi "orchestraintelligence.fr"; then
      priority="high"
      reasoning="${reasoning}; Email to business account — likely prospect/client"
      suggested_action="review_and_respond"
      suggested_agent="sales-pipeline"
    fi
  fi

  # ────────────────────────────────────────────────────
  # RULE 13: Anthropic emails — special handling
  # ────────────────────────────────────────────────────
  if echo "$sender_domain" | grep -qi "anthropic.com"; then
    classification="prep"
    confidence=0.85
    priority="high"
    client="anthropic"
    reasoning="Email from Anthropic — strategic partner"
    suggested_action="review_and_respond"
  fi

  # ── Build output JSON ──
  jq -n \
    --arg id "$msg_id" \
    --arg account "$account" \
    --arg from "$(echo "$email_json" | jq -r '.from // ""')" \
    --arg subject "$subject" \
    --arg date "$(echo "$email_json" | jq -r '.date // ""')" \
    --arg classification "$classification" \
    --argjson confidence "$confidence" \
    --arg priority "$priority" \
    --arg client "$client" \
    --arg reasoning "$reasoning" \
    --arg suggested_action "$suggested_action" \
    --arg suggested_agent "$suggested_agent" \
    --arg classified_at "$TIMESTAMP" \
    '{
      id: $id,
      account: $account,
      from: $from,
      subject: $subject,
      date: $date,
      classification: $classification,
      confidence: $confidence,
      priority: $priority,
      client: $client,
      reasoning: $reasoning,
      suggested_action: $suggested_action,
      suggested_agent: $suggested_agent,
      classified_at: $classified_at
    }'
}

# ══════════════════════════════════════════════════════════════
# SUMMARY GENERATOR
# ══════════════════════════════════════════════════════════════

generate_summary() {
  local classified_json="$1"
  local output_file="$2"

  local dispatch_count prep_count yours_count skip_count total
  dispatch_count=$(echo "$classified_json" | jq '[.classified[] | select(.classification == "dispatch")] | length')
  prep_count=$(echo "$classified_json" | jq '[.classified[] | select(.classification == "prep")] | length')
  yours_count=$(echo "$classified_json" | jq '[.classified[] | select(.classification == "yours")] | length')
  skip_count=$(echo "$classified_json" | jq '[.classified[] | select(.classification == "skip")] | length')
  total=$(echo "$classified_json" | jq '.classified | length')

  cat > "$output_file" << HEREDOC
# 📧 Inbox Zero Report — $(date '+%Y-%m-%d %H:%M')

> **Agent:** inbox-zero v1.0 | **Scanned:** ${total} emails | **Engine:** rules-v1
> **Accounts:** ludovic.goutel@gmail.com, sales@, ludovic@orchestraintelligence.fr

---

## 🔴 YOURS (${yours_count} emails) — Needs your attention
HEREDOC

  echo "$classified_json" | jq -r '.classified[] | select(.classification == "yours") | "- **[\(.from | split("<") | .[0] | gsub("^ +| +$";""))]** \(.subject)\n  → _\(.reasoning)_ | Priority: **\(.priority)** | Agent: \(.suggested_agent)"' >> "$output_file"

  if [ "$yours_count" -eq 0 ]; then
    echo "_None — all clear ✅_" >> "$output_file"
  fi

  cat >> "$output_file" << HEREDOC

## 🟡 PREP (${prep_count} emails) — Ready for review
HEREDOC

  echo "$classified_json" | jq -r '.classified[] | select(.classification == "prep") | "- **[\(.from | split("<") | .[0] | gsub("^ +| +$";""))]** \(.subject)\n  → _\(.reasoning)_ | Action: \(.suggested_action)"' >> "$output_file"

  if [ "$prep_count" -eq 0 ]; then
    echo "_None_" >> "$output_file"
  fi

  cat >> "$output_file" << HEREDOC

## 🟢 DISPATCH (${dispatch_count} emails) — Handled by Alba
HEREDOC

  echo "$classified_json" | jq -r '.classified[] | select(.classification == "dispatch") | "- [\(.from | split("<") | .[0] | gsub("^ +| +$";""))] \(.subject) → \(.suggested_action)"' >> "$output_file"

  if [ "$dispatch_count" -eq 0 ]; then
    echo "_None_" >> "$output_file"
  fi

  cat >> "$output_file" << HEREDOC

## ⚪ SKIP (${skip_count} emails) — Deferred
HEREDOC

  echo "$classified_json" | jq -r '.classified[] | select(.classification == "skip") | "- [\(.from | split("<") | .[0] | gsub("^ +| +$";""))] \(.subject) — _\(.reasoning)_"' >> "$output_file"

  if [ "$skip_count" -eq 0 ]; then
    echo "_None_" >> "$output_file"
  fi

  cat >> "$output_file" << HEREDOC

---

## 📊 Stats
| Category | Count | % |
|----------|-------|---|
| 🔴 YOURS | ${yours_count} | $(( total > 0 ? yours_count * 100 / total : 0 ))% |
| 🟡 PREP | ${prep_count} | $(( total > 0 ? prep_count * 100 / total : 0 ))% |
| 🟢 DISPATCH | ${dispatch_count} | $(( total > 0 ? dispatch_count * 100 / total : 0 ))% |
| ⚪ SKIP | ${skip_count} | $(( total > 0 ? skip_count * 100 / total : 0 ))% |
| **TOTAL** | **${total}** | **100%** |

_Generated by Inbox Zero Agent v1.0 — $(date '+%Y-%m-%d %H:%M:%S %Z')_
HEREDOC

  log "Summary saved to ${output_file}"
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
log "═══ Inbox Zero Classification Started ═══"
log "Input: ${SCAN_FILE}"

EMAILS=$(jq '.emails' "$SCAN_FILE")
TOTAL=$(echo "$EMAILS" | jq 'length')
log "Emails to classify: ${TOTAL}"

CLASSIFIED="[]"
DISPATCH_LOG=""
PREP_LOG=""
YOURS_LOG=""
SKIP_LOG=""

for i in $(seq 0 $((TOTAL - 1))); do
  email=$(echo "$EMAILS" | jq ".[$i]")
  subject=$(echo "$email" | jq -r '.subject // "(no subject)"')
  from=$(echo "$email" | jq -r '.from // "unknown"')

  log "  Classifying [$((i+1))/${TOTAL}]: ${subject:0:60}"

  result=$(classify_email "$email")
  classification=$(echo "$result" | jq -r '.classification')

  CLASSIFIED=$(echo "$CLASSIFIED" | jq --argjson r "$result" '. + [$r]')

  # Append to category-specific JSONL logs
  case "$classification" in
    dispatch) DISPATCH_LOG="${DISPATCH_LOG}${result}\n" ;;
    prep)     PREP_LOG="${PREP_LOG}${result}\n" ;;
    yours)    YOURS_LOG="${YOURS_LOG}${result}\n" ;;
    skip)     SKIP_LOG="${SKIP_LOG}${result}\n" ;;
  esac

  log "    → ${classification} ($(echo "$result" | jq -r '.priority'))"
done

# ── Build classified report ──
CLASSIFIED_REPORT=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --argjson total "$TOTAL" \
  --argjson classified "$CLASSIFIED" \
  '{
    classification_metadata: {
      timestamp: $ts,
      total_classified: $total,
      engine: "rules-v1",
      dispatch: ([$classified[] | select(.classification == "dispatch")] | length),
      prep: ([$classified[] | select(.classification == "prep")] | length),
      yours: ([$classified[] | select(.classification == "yours")] | length),
      skip: ([$classified[] | select(.classification == "skip")] | length)
    },
    classified: $classified
  }')

# ── Save outputs ──
CLASSIFIED_FILE="${OUTPUT_DIR}/${DATE_SLUG}-classified.json"
SUMMARY_FILE="${OUTPUT_DIR}/${DATE_SLUG}-summary.md"

echo "$CLASSIFIED_REPORT" | jq '.' > "$CLASSIFIED_FILE"
log "Classification saved to ${CLASSIFIED_FILE}"

generate_summary "$CLASSIFIED_REPORT" "$SUMMARY_FILE"

# ── Save JSONL logs ──
[ -n "$DISPATCH_LOG" ] && echo -e "$DISPATCH_LOG" >> "${LOGS_DIR}/dispatch-log.jsonl"
[ -n "$PREP_LOG" ] && echo -e "$PREP_LOG" >> "${LOGS_DIR}/prep-log.jsonl"
[ -n "$YOURS_LOG" ] && echo -e "$YOURS_LOG" >> "${LOGS_DIR}/yours-log.jsonl"
[ -n "$SKIP_LOG" ] && echo -e "$SKIP_LOG" >> "${LOGS_DIR}/skip-log.jsonl"

# ── Print summary stats ──
log "═══ Classification Complete ═══"
log "  🔴 YOURS:    $(echo "$CLASSIFIED_REPORT" | jq '.classification_metadata.yours')"
log "  🟡 PREP:     $(echo "$CLASSIFIED_REPORT" | jq '.classification_metadata.prep')"
log "  🟢 DISPATCH: $(echo "$CLASSIFIED_REPORT" | jq '.classification_metadata.dispatch')"
log "  ⚪ SKIP:     $(echo "$CLASSIFIED_REPORT" | jq '.classification_metadata.skip')"

# Output JSON for piping
echo "$CLASSIFIED_REPORT"
