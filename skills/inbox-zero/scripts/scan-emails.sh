#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# scan-emails.sh — Inbox Zero Email Scanner
# Orchestra Intelligence — Agent World
# ═══════════════════════════════════════════════════════════════
# Scans all 3 Gmail accounts via GOG CLI
# Outputs structured JSON with full email metadata
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOGS_DIR="${SCRIPT_DIR}/logs"
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S%z)
DATE_SLUG=$(date +%Y-%m-%d)

# ── Load GOG keyring password ──
if [ -f "$HOME/.secrets/.env" ]; then
  export GOG_KEYRING_PASSWORD=$(grep GOG_KEYRING_PASSWORD "$HOME/.secrets/.env" | head -1 | cut -d'=' -f2- | tr -d '"' | tr -d "'")
fi

if [ -z "${GOG_KEYRING_PASSWORD:-}" ]; then
  echo "ERROR: GOG_KEYRING_PASSWORD not found" >&2
  exit 1
fi

ACCOUNTS=(
  "ludovic.goutel@gmail.com"
  "sales@orchestraintelligence.fr"
  "ludovic@orchestraintelligence.fr"
)

QUERY="${1:-is:unread}"
MAX_RESULTS="${2:-50}"

mkdir -p "$OUTPUT_DIR" "$LOGS_DIR"

log() {
  local msg="[$(date +%H:%M:%S)] $1"
  echo "$msg" >> "${LOGS_DIR}/scan-${DATE_SLUG}.log"
  echo "$msg" >&2
}

# ── Scan one account using messages search (returns message IDs directly) ──
scan_account() {
  local account="$1"
  local query="$2"
  local max="$3"

  log "Scanning ${account} — query: '${query}' (max: ${max})"

  # Use messages search for direct message IDs (not thread IDs)
  local msgs_json
  msgs_json=$(gog gmail messages search -a "$account" "$query" --max="$max" -j --results-only --no-input 2>/dev/null || echo "[]")

  # Validate JSON
  if ! echo "$msgs_json" | jq empty 2>/dev/null; then
    log "  ⚠ Invalid JSON from messages search for ${account}"
    echo "[]"
    return
  fi

  local msg_count
  msg_count=$(echo "$msgs_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
  log "  → Found ${msg_count} messages in ${account}"

  if [ "$msg_count" -eq 0 ]; then
    echo "[]"
    return
  fi

  # Build result array from message list metadata (no individual fetches for speed)
  # messages search already returns: id, from, subject, date, labels, threadId
  local results="[]"

  # Process each message from the list
  for i in $(seq 0 $((msg_count - 1))); do
    local msg_id from subject date labels

    msg_id=$(echo "$msgs_json" | jq -r ".[$i].id // \"\"")
    from=$(echo "$msgs_json" | jq -r ".[$i].from // \"unknown\"")
    subject=$(echo "$msgs_json" | jq -r ".[$i].subject // \"(no subject)\"")
    date=$(echo "$msgs_json" | jq -r ".[$i].date // \"\"")
    labels=$(echo "$msgs_json" | jq ".[$i].labels // []")

    [ -z "$msg_id" ] && continue

    # Fetch full body for classification (only first 2000 chars)
    local body=""
    local full_msg
    full_msg=$(gog gmail get -a "$account" "$msg_id" -j --results-only --no-input 2>/dev/null || echo "{}")

    if echo "$full_msg" | jq empty 2>/dev/null; then
      body=$(echo "$full_msg" | jq -r '.body // ""' 2>/dev/null | head -c 2000)
      # Get more accurate headers from full fetch
      local full_from full_to full_cc full_date
      full_from=$(echo "$full_msg" | jq -r '.headers.from // ""' 2>/dev/null)
      full_to=$(echo "$full_msg" | jq -r '.headers.to // ""' 2>/dev/null)
      full_cc=$(echo "$full_msg" | jq -r '.headers.cc // ""' 2>/dev/null)
      full_date=$(echo "$full_msg" | jq -r '.headers.date // ""' 2>/dev/null)

      [ -n "$full_from" ] && from="$full_from"
      [ -n "$full_date" ] && date="$full_date"
    else
      log "  ⚠ Could not fetch body for ${msg_id}, using metadata only"
      body=""
      full_to=""
      full_cc=""
    fi

    # Build clean message object
    local clean_msg
    clean_msg=$(jq -n \
      --arg id "$msg_id" \
      --arg account "$account" \
      --arg from "$from" \
      --arg to "${full_to:-$account}" \
      --arg cc "${full_cc:-}" \
      --arg subject "$subject" \
      --arg date "$date" \
      --arg body "$body" \
      --argjson labels "$labels" \
      --arg scan_ts "$TIMESTAMP" \
      '{
        id: $id,
        account: $account,
        from: $from,
        to: $to,
        cc: $cc,
        subject: $subject,
        date: $date,
        body: ($body | if length > 2000 then .[0:2000] + "..." else . end),
        labels: $labels,
        scan_timestamp: $scan_ts
      }')

    results=$(echo "$results" | jq --argjson msg "$clean_msg" '. + [$msg]')
  done

  echo "$results"
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
log "═══ Inbox Zero Scan Started ═══"
log "Query: ${QUERY} | Max: ${MAX_RESULTS}"

ALL_EMAILS="[]"
ACCOUNT_SUMMARIES="[]"

for account in "${ACCOUNTS[@]}"; do
  account_emails=$(scan_account "$account" "$QUERY" "$MAX_RESULTS")
  count=$(echo "$account_emails" | jq 'length' 2>/dev/null || echo "0")

  ALL_EMAILS=$(echo "$ALL_EMAILS" "$account_emails" | jq -s '.[0] + .[1]')

  ACCOUNT_SUMMARIES=$(echo "$ACCOUNT_SUMMARIES" | jq \
    --arg acc "$account" \
    --argjson count "$count" \
    '. + [{"account": $acc, "count": $count}]')

  log "  ✓ ${account}: ${count} emails"
done

TOTAL=$(echo "$ALL_EMAILS" | jq 'length')
log "Total emails scanned: ${TOTAL}"

# ── Build scan report ──
SCAN_REPORT=$(jq -n \
  --arg ts "$TIMESTAMP" \
  --arg query "$QUERY" \
  --argjson total "$TOTAL" \
  --argjson accounts "$ACCOUNT_SUMMARIES" \
  --argjson emails "$ALL_EMAILS" \
  '{
    scan_metadata: {
      timestamp: $ts,
      query: $query,
      total_emails: $total,
      accounts: $accounts
    },
    emails: $emails
  }')

SCAN_FILE="${OUTPUT_DIR}/${DATE_SLUG}-scan.json"
echo "$SCAN_REPORT" | jq '.' > "$SCAN_FILE"
log "Scan saved to ${SCAN_FILE}"

echo "$SCAN_REPORT"
log "═══ Inbox Zero Scan Complete ═══"
