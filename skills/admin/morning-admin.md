---
name: morning-admin
description: "Combined morning admin routine: check 3 inboxes for urgent items, collect receipts, review calendar, check Qonto transactions, generate summary with action items. Use when asked for 'admin check', 'morning admin', or 'admin summary'."
user-invocable: true
version: "1.0"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Morning Admin — Daily Administrative Routine

Combined morning routine that orchestrates all admin tasks into a single execution. Runs daily at 07:30 or on-demand. Produces a consolidated admin summary with action items for Ludovic.

## Accounts

1. **sales@orchestraintelligence.fr** — primary business account, calendar
2. **ludovic@orchestraintelligence.fr** — professional account
3. **ludovic.goutel@gmail.com** — READ ONLY (managed by Pablo)

## Tools

- `gog` CLI — Gmail, Calendar, Drive, Sheets
- `op` CLI — 1Password secrets
- Qonto API — banking transactions

## Step-by-step Workflow

### Phase 1: Urgent Email Scan (2 minutes)

Check all 3 inboxes for items requiring immediate attention:

```bash
# Search each account for unread emails from last 12 hours
SINCE=$(date -v-12H +%Y/%m/%d)

for account in sales@orchestraintelligence.fr ludovic@orchestraintelligence.fr ludovic.goutel@gmail.com; do
  gog gmail search --account "$account" \
    --query "is:unread after:${SINCE}" \
    --format json > /tmp/urgent_${account%%@*}.json
done
```

Triage new emails:
- **URGENT**: Emails from VIP clients (Wella, Henkel), legal/contract keywords, negative sentiment
- **ACTION**: Emails requiring a response today (meeting requests, client questions)
- **INFO**: Newsletters, notifications, automated (log only)

### Phase 2: Receipt Collection (1 minute)

Quick scan for new receipts since last run:

```bash
# Search for receipt emails from last 24 hours
YESTERDAY=$(date -v-1d +%Y/%m/%d)
KEYWORDS="facture OR invoice OR receipt OR recu OR paiement"

for account in sales@orchestraintelligence.fr ludovic@orchestraintelligence.fr ludovic.goutel@gmail.com; do
  gog gmail search --account "$account" \
    --query "${KEYWORDS} after:${YESTERDAY} has:attachment" \
    --format json
done
```

If new receipts found:
1. Download attachments
2. Rename with convention `YYYY-MM-DD_vendor_amount.pdf`
3. Upload to `Comptabilite/YYYY/MM-Month/` on Drive
4. Log in summary

(Delegates to receipt-collector skill for heavy processing)

### Phase 3: Calendar Review (1 minute)

Run calendar-manager workflow:

```bash
TODAY=$(date +%Y-%m-%d)

gog calendar list --account sales@orchestraintelligence.fr \
  --start "${TODAY}T00:00:00" --end "${TODAY}T23:59:59" \
  --format json > /tmp/today_calendar.json
```

Extract:
- Number of meetings today
- First meeting time
- Client meetings (flag for prep)
- Conflicts detected
- Free time blocks

### Phase 4: Transaction Check (1 minute)

Check Qonto for new transactions since yesterday:

```bash
eval $(op signin)
QONTO_LOGIN=$(op read "op://Alba-Secrets/Qonto-API/login")
QONTO_SECRET=$(op read "op://Alba-Secrets/Qonto-API/secret-key")
QONTO_SLUG=$(op read "op://Alba-Secrets/Qonto-API/organization-slug")
QONTO_IBAN=$(op read "op://Alba-Secrets/Qonto-API/iban")

YESTERDAY=$(date -v-1d +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

curl -s -H "Authorization: ${QONTO_LOGIN}:${QONTO_SECRET}" \
  "https://thirdparty.qonto.com/v2/transactions?slug=${QONTO_SLUG}&iban=${QONTO_IBAN}&settled_at_from=${YESTERDAY}T00:00:00.000Z&settled_at_to=${TODAY}T23:59:59.000Z&status[]=completed" \
  > /tmp/new_transactions.json
```

Flag:
- Any transaction > 500 EUR
- Unexpected charges (not in subscription list)
- Failed transactions

### Phase 5: Drive Quick-scan (30 seconds)

Check for files dumped in root or wrong locations:

```bash
gog drive list --path "/" --files-only --format json > /tmp/root_files.json
```

Flag any new misplaced files.

### Phase 6: Generate Morning Admin Summary

Consolidate all findings into a single summary:

```
## Admin Summary — Mercredi 1er Avril 2026

### Emails (3 comptes)
- **Nouveaux non lus**: 12 total (3 sales@, 5 ludovic@, 4 gmail)
- **Urgents**: 1 — Email de Wella re: delai livraison
- **Actions requises**: 3
  1. Repondre a Smart Renovation — question facturation
  2. Confirmer meeting jeudi avec prospect Imagin
  3. Signer contrat freelance (ludovic@ — PDF joint)

### Calendrier
- **Meetings aujourd'hui**: 4
- **Premier meeting**: 10:30 (Standup)
- **Meetings clients**: 1 (Wella 14:00 — PREP NEEDED)
- **Conflits**: Aucun
- **Temps libre**: 12:00-14:00, 16:00-18:00

### Finances
- **Nouvelles transactions**: 3 (total: €234.56)
  - Stripe: €49.00 (SaaS)
  - OVH: €129.00 (Cloud)
  - Deliveroo: €56.56 (Meals)
- **Alertes**: Aucune
- **Solde actuel**: €XX,XXX.XX

### Receipts
- **Nouvelles factures detectees**: 2
  - OVH — €129.00 (PDF telecharge, uploade dans Drive)
  - Stripe — €49.00 (PDF telecharge, uploade dans Drive)
- **Receipts manquants**: 1 (Deliveroo — pas de PDF)

### Drive
- **Fichiers mal places**: 0
- **Actions Drive**: Aucune

---

### Actions pour Ludovic
1. [ ] Repondre a Wella re: delai livraison (URGENT)
2. [ ] Signer contrat freelance (piece jointe dans ludovic@)
3. [ ] Confirmer meeting Imagin jeudi
4. [ ] Fournir receipt Deliveroo €56.56

### Actions pour Alba
1. [x] Upload 2 receipts dans Drive
2. [ ] Preparer brief client Wella pour meeting 14:00
3. [ ] Envoyer reponse Smart Renovation (draft ready)
```

### Phase 7: Deliver Summary

1. Save summary to `/tmp/morning_admin_$(date +%Y-%m-%d).md`
2. If triggered from Telegram: send via reply tool
3. If triggered from cron: save and notify via Pushover

## Schedule

- **Automatic**: Cron at 07:30 Paris time (weekdays)
- **Manual**: On demand via `/morning-admin` or "admin check"
- **Weekend**: Reduced version (email + transactions only, no calendar)

## Output

- Consolidated morning admin summary (markdown, French)
- Action items split: Ludovic vs. Alba
- Urgent flags highlighted at top

## Integration

- **receipt-collector skill**: delegates receipt download/upload
- **calendar-manager skill**: delegates calendar analysis
- **expense-tracker skill**: delegates transaction categorization
- **drive-organizer skill**: delegates file organization
- **inbox-zero skill**: uses DPYS classification for email triage
- **daily-briefing skill**: morning-admin feeds into the full daily briefing
- **personal-assistant agent**: receives action items

## Rules

- NEVER send emails from ludovic.goutel@gmail.com
- All amounts in EUR
- Summary in French
- Keep execution under 5 minutes total
- If any phase fails, continue with others and report the failure
- Urgent items always surfaced first, regardless of phase order
