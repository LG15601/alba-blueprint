---
name: expense-tracker
description: "Connect to Qonto API for monthly transactions. Match with receipts. Flag unmatched expenses. Generate monthly expense report by category. Use when asked about expenses, transactions, Qonto, or comptabilite."
user-invocable: true
version: "1.0"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
---

# Expense Tracker — Qonto Transaction Manager

Connects to Qonto banking API to pull monthly transactions, matches them against collected receipts, flags unmatched expenses, and generates categorized monthly expense reports for comptabilite.

## Banking

- **Bank**: Qonto
- **API**: Qonto REST API v2
- **Currency**: EUR (all amounts)
- **Secrets**: 1Password vault "Alba-Secrets"
- **Comptabilite**: Pennylane (switched March 2024)

## Expense Categories

| Category | Keywords / Patterns |
|----------|-------------------|
| SaaS Subscriptions | stripe, vercel, supabase, github, notion, slack, openai, anthropic, figma, linear, 1password, cloudflare |
| Cloud Infrastructure | aws, gcp, azure, ovh, hetzner, fly.io, render, digitalocean |
| Travel | sncf, airfrance, booking, hotels, uber, bolt, taxi, eurostar |
| Meals | restaurant, deliveroo, ubereats, justeat, brasserie, cafe |
| Equipment | apple, amazon, ldlc, fnac, materiel.net |
| Professional Services | avocat, comptable, consultant, freelance, fiverr, upwork |
| Marketing | google ads, meta ads, linkedin, mailchimp, sendgrid, hubspot |
| Office & Admin | loyer, assurance, edf, free, orange, poste, fournitures |
| Taxes & Charges | urssaf, impots, tva, cotisation, cfe |

## Step-by-step Workflow

### 1. Retrieve Qonto API credentials

```bash
eval $(op signin)
QONTO_LOGIN=$(op read "op://Alba-Secrets/Qonto-API/login")
QONTO_SECRET=$(op read "op://Alba-Secrets/Qonto-API/secret-key")
QONTO_SLUG=$(op read "op://Alba-Secrets/Qonto-API/organization-slug")
QONTO_IBAN=$(op read "op://Alba-Secrets/Qonto-API/iban")
```

### 2. Pull monthly transactions

```bash
YEAR=$(date +%Y)
MONTH=$(date +%m)
START_DATE="${YEAR}-${MONTH}-01"
END_DATE=$(date -v+1m -v1d -v-1d +%Y-%m-%d)  # last day of current month

curl -s -H "Authorization: ${QONTO_LOGIN}:${QONTO_SECRET}" \
  "https://thirdparty.qonto.com/v2/transactions?slug=${QONTO_SLUG}&iban=${QONTO_IBAN}&settled_at_from=${START_DATE}T00:00:00.000Z&settled_at_to=${END_DATE}T23:59:59.000Z&status[]=completed" \
  > /tmp/qonto_transactions.json
```

### 3. Parse and categorize transactions

For each transaction:
1. Extract: date, amount, label, counterparty name, reference
2. Match counterparty against category keywords table
3. Assign category (or "Uncategorized" if no match)

```bash
# Parse transactions into structured format
jq '[.transactions[] | {
  date: .settled_at[:10],
  amount: .amount,
  side: .side,
  label: .label,
  counterparty: .label,
  reference: .reference,
  category: "uncategorized"
}]' /tmp/qonto_transactions.json > /tmp/transactions_parsed.json
```

### 4. Match transactions with receipts

Load the receipt log from receipt-collector:

```bash
# Compare transaction list against receipt list
# Match by: amount (exact) + date (within 3 days) + vendor name (fuzzy)

# For each transaction:
#   - Search receipts for matching amount (EUR, exact to cent)
#   - If amount matches, check date proximity (<=3 days)
#   - If date matches, verify vendor name similarity
#   - Mark as: MATCHED, UNMATCHED, or AMBIGUOUS
```

Matching rules:
- **MATCHED**: Amount exact match + date within 3 days + vendor similarity > 70%
- **AMBIGUOUS**: Amount matches but vendor unclear — flag for review
- **UNMATCHED**: No receipt found — flag as missing

### 5. Flag unmatched expenses

Generate a list of transactions without matching receipts:

```
## Unmatched Expenses — Receipts Missing

| Date | Amount (EUR) | Vendor | Category | Action Needed |
|------|-------------|--------|----------|---------------|
| 2026-04-05 | 129.00 | OVH SAS | Cloud | Find receipt in email |
| 2026-04-12 | 45.50 | Restaurant Le Petit | Meals | Request receipt |
```

For amounts > 50 EUR unmatched: escalate to Ludovic in morning summary.

### 6. Generate monthly expense report

```
## Rapport de Depenses — Avril 2026

### Synthese
- **Total depenses**: €X,XXX.XX
- **Nombre de transactions**: XX
- **Receipts matched**: XX/XX (XX%)

### Par categorie

| Categorie | Montant (EUR) | Nb transactions | % du total |
|-----------|--------------|-----------------|------------|
| SaaS Subscriptions | 1,234.56 | 12 | 25% |
| Cloud Infrastructure | 890.00 | 5 | 18% |
| Travel | 567.89 | 3 | 12% |
| Meals | 234.56 | 8 | 5% |
| Equipment | 0.00 | 0 | 0% |
| Professional Services | 500.00 | 2 | 10% |
| Marketing | 1,500.00 | 4 | 30% |
| Office & Admin | 0.00 | 0 | 0% |
| Taxes & Charges | 0.00 | 0 | 0% |

### Top 5 depenses
1. Google Ads — €800.00 (01/04)
2. Anthropic API — €456.78 (15/04)
3. ...

### Transactions non matchees (receipt manquant)
[list from step 5]

### Evolution vs mois precedent
- Total: +12% vs Mars 2026
- SaaS: stable
- Marketing: +25% (nouvelle campagne)
```

### 7. Upload report to Drive

```bash
MONTH_NAME=$(echo "Janvier Fevrier Mars Avril Mai Juin Juillet Aout Septembre Octobre Novembre Decembre" | cut -d' ' -f${MONTH#0})
FOLDER="Comptabilite/${YEAR}/${MONTH}-${MONTH_NAME}"

gog drive mkdir --parents "${FOLDER}"
gog drive upload /tmp/expense_report_${YEAR}-${MONTH}.md --destination "${FOLDER}/"
```

### 8. Cleanup

```bash
rm -f /tmp/qonto_transactions.json /tmp/transactions_parsed.json /tmp/expense_report_*.md
```

## Recurring Subscription Tracking

Maintain a list of expected monthly subscriptions:

```json
{
  "subscriptions": [
    {"vendor": "Anthropic", "expected_amount": 456.78, "day_of_month": 1},
    {"vendor": "Vercel", "expected_amount": 20.00, "day_of_month": 1},
    {"vendor": "Supabase", "expected_amount": 25.00, "day_of_month": 15},
    {"vendor": "1Password", "expected_amount": 7.99, "day_of_month": 1}
  ]
}
```

Flag if a subscription is missing (not charged when expected) or if amount changed unexpectedly.

## Output

- Monthly expense report (markdown, French)
- Unmatched expense alerts
- Subscription anomaly alerts
- JSON transaction log for Pennylane import

## Integration

- **receipt-collector skill**: provides receipt data for matching
- **morning-admin skill**: calls this for daily transaction check
- **drive-organizer skill**: ensures reports are filed correctly
- **Pennylane**: monthly data export formatted for import

## Rules

- All amounts in EUR, formatted with comma as decimal separator in French reports
- Never expose Qonto API keys in logs or output
- Flag any transaction > 500 EUR individually in morning summary
- Keep 12-month rolling history for trend analysis
