---
name: receipt-collector
description: "Scan 3 inboxes for receipts/invoices/factures. Download attachments, organize in Google Drive monthly folders, generate summary. Use when asked about receipts, invoices, factures, or comptabilite."
user-invocable: true
version: "1.0"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Receipt Collector — Invoice & Receipt Harvester

Automated receipt/invoice collection from 3 email accounts. Downloads attachments, uploads to Google Drive with standardized naming, and generates monthly summaries for Pennylane integration.

## Accounts (read access)

1. **sales@orchestraintelligence.fr** — client invoices, SaaS receipts
2. **ludovic@orchestraintelligence.fr** — professional services, subscriptions
3. **ludovic.goutel@gmail.com** — READ ONLY (managed by Pablo) — personal subscriptions, one-off purchases

## Detection Keywords

Search emails using these keywords (subject + body):
- French: `facture`, `recu`, `reçu`, `commande`, `paiement`, `abonnement`, `prelevement`, `prélèvement`, `avoir`, `note de frais`
- English: `invoice`, `receipt`, `payment`, `subscription`, `order confirmation`, `billing statement`
- Patterns: amounts with EUR/euro sign, PDF attachments named `*facture*`, `*invoice*`, `*receipt*`

## Step-by-step Workflow

### 1. Retrieve secrets

```bash
# Get Google OAuth credentials from 1Password
eval $(op signin)
GOOGLE_CREDS=$(op read "op://Alba-Secrets/Google-OAuth/credential")
```

### 2. Scan inboxes for receipts

For each of the 3 accounts, search for receipt-related emails from the current month:

```bash
# Search each account for receipt emails (last 30 days)
MONTH=$(date +%Y-%m)
KEYWORDS="facture OR invoice OR receipt OR recu OR commande OR paiement OR subscription OR abonnement"

# Account 1: sales@
gog gmail search --account sales@orchestraintelligence.fr \
  --query "${KEYWORDS} newer_than:30d has:attachment" --format json > /tmp/receipts_sales.json

# Account 2: ludovic@
gog gmail search --account ludovic@orchestraintelligence.fr \
  --query "${KEYWORDS} newer_than:30d has:attachment" --format json > /tmp/receipts_ludovic.json

# Account 3: gmail (READ ONLY)
gog gmail search --account ludovic.goutel@gmail.com \
  --query "${KEYWORDS} newer_than:30d has:attachment" --format json > /tmp/receipts_gmail.json
```

### 3. Download attachments

For each matched email, download PDF and image attachments:

```bash
# Download attachments to temp directory
mkdir -p /tmp/receipts/${MONTH}

for msg_id in $(jq -r '.[].id' /tmp/receipts_sales.json); do
  gog gmail download-attachments --account sales@orchestraintelligence.fr \
    --message-id "$msg_id" \
    --filter "*.pdf,*.png,*.jpg,*.jpeg" \
    --output /tmp/receipts/${MONTH}/
done
# Repeat for other accounts
```

### 4. Rename files with convention

Naming convention: `YYYY-MM-DD_vendor_amount.pdf`

Extract from email metadata:
- **Date**: email date or invoice date if parseable
- **Vendor**: sender domain or company name from subject
- **Amount**: extract from subject/body using regex `\d+[.,]\d{2}\s*(?:EUR|€)`

```bash
# Example rename
# Original: invoice_12345.pdf
# Renamed:  2026-04-01_stripe_49.00EUR.pdf
```

### 5. Upload to Google Drive

Target folder structure: `Comptabilite/2026/MM-MonthName/`

French month names: `01-Janvier`, `02-Fevrier`, `03-Mars`, `04-Avril`, `05-Mai`, `06-Juin`, `07-Juillet`, `08-Aout`, `09-Septembre`, `10-Octobre`, `11-Novembre`, `12-Decembre`

```bash
YEAR=$(date +%Y)
MONTH_NUM=$(date +%m)
MONTH_NAME=$(echo "Janvier Fevrier Mars Avril Mai Juin Juillet Aout Septembre Octobre Novembre Decembre" | cut -d' ' -f${MONTH_NUM#0})
FOLDER="Comptabilite/${YEAR}/${MONTH_NUM}-${MONTH_NAME}"

# Create folder if needed
gog drive mkdir --parents "${FOLDER}"

# Upload each receipt
for file in /tmp/receipts/${MONTH}/*.pdf; do
  gog drive upload "$file" --destination "${FOLDER}/"
done
```

### 6. Generate monthly summary

Produce a markdown summary with:

```
## Receipts Collected — YYYY-MM

| Date | Vendor | Amount (EUR) | Source Account | File |
|------|--------|-------------|----------------|------|
| 2026-04-01 | Stripe | 49.00 | sales@ | 2026-04-01_stripe_49.00EUR.pdf |
| ... | ... | ... | ... | ... |

**Total**: XX receipts, €X,XXX.XX
**Unmatched**: X emails with no downloadable attachment (flagged for manual check)
**Drive folder**: Comptabilite/2026/04-Avril/
```

### 7. Cleanup

```bash
rm -rf /tmp/receipts/${MONTH}
```

## Deduplication

Before uploading, check if file already exists in Drive folder by name. Skip duplicates. Log skipped files in summary.

## Error Handling

- If attachment download fails: log email ID and subject, flag for manual review
- If Drive upload fails: retry once, then save locally and flag
- If amount extraction fails: use `unknown` and flag for manual entry

## Output

- Monthly receipt summary (markdown) — stored in `Comptabilite/YYYY/MM-Month/summary.md`
- JSON log of all processed receipts — for expense-tracker matching
- List of flagged items requiring manual attention

## Integration

- **expense-tracker skill**: provides receipt list for transaction matching
- **morning-admin skill**: calls this daily for new receipt detection
- **Pennylane**: monthly summaries formatted for Pennylane import (switched March 2024)

## Rules

- NEVER send emails from ludovic.goutel@gmail.com (Pablo's domain)
- All amounts in EUR
- Store in Drive only, never keep local copies long-term
- French month names for folder structure
