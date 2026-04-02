---
name: invoice-prep
description: |
  Prepare invoicing data from project activity, time tracking, and deliverables.
  Gathers billing-relevant data across repos, emails, and project status to
  generate invoice drafts. Use when asked to "prepare invoices", "facturation",
  "billing", or on monthly cron (1st of month).
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - Glob
  - Grep
  - mcp__claude_ai_Gmail__gmail_search_messages
---

# Invoice Prep -- Billing Data Preparation

Gathers all billing-relevant data from project activity, deliverables, and
agreements to prepare invoice drafts for each active client.

## Arguments
- `/invoice-prep` -- prepare all invoices for current billing period
- `/invoice-prep [client]` -- prepare invoice for specific client
- `/invoice-prep check` -- verify billing data without generating drafts
- `/invoice-prep recurring` -- process only recurring/subscription invoices

## Step 1: Load Billing Context

### 1a. Client Contracts
```bash
# Load client data with billing info
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
# Load active contracts/agreements
cat ~/.alba/billing/contracts.json 2>/dev/null || echo "No contract database -- using CRM data"
```

### 1b. Billing Configuration
```bash
cat ~/.alba/billing/config.json 2>/dev/null || echo "Using defaults"
```

Default config:
```json
{
  "company": {
    "name": "Orchestra Intelligence",
    "siret": "XXX XXX XXX XXXXX",
    "address": "...",
    "vat_number": "FRXXXXXXXXXX",
    "iban": "...",
    "payment_terms_days": 30
  },
  "invoice_prefix": "OI",
  "next_number": 2026041,
  "vat_rate": 0.20,
  "currency": "EUR"
}
```

## Step 2: Identify Billable Items Per Client

### 2a. Recurring Revenue (subscriptions/retainers)
For each client with a recurring agreement:
- Monthly retainer amount
- Start date of current period
- Any adjustments or credits
- Billing cycle (monthly, quarterly)

### 2b. Project-Based Work
For each client with active projects:
```bash
# Commits and PRs for client projects
SINCE=$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)
gh pr list --repo "orchestraintelligence/[client-repo]" --state merged --search "merged:>=$SINCE" --json title,mergedAt 2>/dev/null
```

Deliverables completed:
- Features shipped (from PR titles and descriptions)
- Documents delivered (from email attachments)
- Milestones reached (from project plan)

### 2c. Time-Based Billing
If applicable, gather time data:
```bash
# Check for time tracking data
cat ~/.alba/billing/timesheet-$(date +%Y-%m).json 2>/dev/null || echo "No timesheet data"
```

### 2d. Additional Services
Check for one-off services:
- Consulting sessions (calendar events)
- Training delivered
- Urgent support outside SLA
- Additional development requested via email

## Step 3: Calculate Invoice Amounts

### For Each Client:
```
Base amount (retainer or project fee):     [amount] EUR HT
+ Additional deliverables:                 [amount] EUR HT
+ Time overages (if applicable):           [hours] x [rate] = [amount] EUR HT
- Credits or adjustments:                  -[amount] EUR HT
= Total HT:                               [amount] EUR HT
+ TVA (20%):                               [amount] EUR
= Total TTC:                               [amount] EUR
```

### Validation Rules
- Invoice amount must match contract terms (warn if deviation > 10%)
- No invoice for 0 EUR
- Retainer invoices: flag if client hasn't used their allocation
- Project invoices: verify deliverables against what was agreed
- Check for duplicate billing (same deliverable in previous invoice)

## Step 4: Generate Invoice Draft

### Invoice Data Structure
```json
{
  "invoice_number": "OI-2026041",
  "date": "2026-04-01",
  "due_date": "2026-05-01",
  "client": {
    "name": "Smart Renovation SAS",
    "siret": "...",
    "address": "...",
    "contact": "Marie Durand"
  },
  "items": [
    {
      "description": "Forfait mensuel -- Agent IA support client",
      "quantity": 1,
      "unit": "mois",
      "unit_price": 3000.00,
      "total_ht": 3000.00
    },
    {
      "description": "Developpement supplementaire -- Integration CRM",
      "quantity": 12,
      "unit": "heures",
      "unit_price": 150.00,
      "total_ht": 1800.00
    }
  ],
  "subtotal_ht": 4800.00,
  "vat_rate": 0.20,
  "vat_amount": 960.00,
  "total_ttc": 5760.00,
  "payment_terms": "30 jours",
  "payment_method": "Virement bancaire",
  "notes": ""
}
```

### Description Rules for Line Items
- Descriptions in French
- Reference the contract or agreement number
- Be specific about what was delivered
- For time-based: include date range
- For project milestones: reference the milestone name
- Never use vague descriptions ("Services divers")

## Step 5: Cross-Check

Before finalizing:
- [ ] Client billing details match contract
- [ ] Invoice number is sequential (no gaps, no duplicates)
- [ ] All amounts calculated correctly (verify arithmetic)
- [ ] TVA correctly applied (check for exempt situations)
- [ ] Payment terms match agreement
- [ ] Deliverables on invoice match what was actually delivered
- [ ] No duplicate billing from previous period
- [ ] Client not in dispute or payment hold

```bash
# Check previous invoices for this client
find ~/.alba/billing/invoices -name "*[client-slug]*" -type f | sort -r | head -3
```

## Step 6: Output

### Save Invoice Drafts
```bash
mkdir -p ~/.alba/billing/invoices/$(date +%Y-%m)
echo '[invoice json]' > ~/.alba/billing/invoices/$(date +%Y-%m)/[invoice-number].json
```

### Summary Report
```bash
mkdir -p ~/.alba/billing/reports
echo '[summary]' > ~/.alba/billing/reports/$(date +%Y-%m)-prep.md
```

### Telegram Notification (French)
```
FACTURATION -- [MONTH YEAR]

[N] factures preparees:

| Client              | Montant HT  | Montant TTC | Type        |
|---------------------|-------------|-------------|-------------|
| [Client 1]          | [X] EUR     | [Y] EUR     | Forfait     |
| [Client 2]          | [X] EUR     | [Y] EUR     | Projet      |
| ...                 | ...         | ...         | ...         |

TOTAL: [sum] EUR HT / [sum] EUR TTC

Points d'attention:
- [Any anomalies or items needing review]
- [Clients with payment issues]

Brouillons prets pour validation.
```

## Step 7: Track Payments (post-invoice)

After invoices are sent, track payment status:
```json
{
  "invoice_number": "OI-2026041",
  "sent_date": "2026-04-01",
  "due_date": "2026-05-01",
  "status": "SENT",
  "reminders": [],
  "paid_date": null,
  "paid_amount": null
}
```

Payment reminders:
- 7 days before due: friendly reminder
- Due date: payment reminder
- 7 days overdue: firm reminder
- 30 days overdue: escalate to Ludovic

## Orchestra Rules
- Invoices are legal documents: accuracy is non-negotiable
- Never send invoices without Ludovic's explicit validation
- All amounts in EUR
- TVA at 20% unless specific exemption documented
- Payment terms per contract (default 30 days)
- RGPD: invoice data contains personal data, treat accordingly
- Keep invoices for 10 years (legal requirement France)
- Never modify a sent invoice: issue a credit note (avoir) instead
- Invoice numbering must be strictly sequential with no gaps
- Billing disputes: flag immediately, do not re-invoice without resolution
- French fiscal regulations: all mandatory mentions must be present
  (SIRET, TVA number, company name, date, sequential number)
