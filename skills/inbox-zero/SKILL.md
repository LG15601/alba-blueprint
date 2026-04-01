---
name: inbox-zero
description: "DPYS email classifier for 3 mailboxes. Classifies into Dispatch/Prep/Yours/Skip with rule engine (13 rules), VIP handling, and sentiment detection. Use when asked about emails, inbox, or 'check my mail'."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - Glob
---

# Inbox Zero — DPYS Email Classifier

Production email management system. Classifies all emails from 3 accounts into:
- **D**ispatch — automated/newsletter, log and archive
- **P**rep — needs review, prepare response draft
- **Y**ours — needs Ludovic's personal attention (VIP, legal, escalation)
- **S**kip — promotions/spam, archive silently

## Accounts
1. sales@orchestraintelligence.fr (OI Sales)
2. ludovic.goutel@gmail.com (Personnel)
3. ludovic@orchestraintelligence.fr (OI Ludovic)

## Usage

### Full scan + classify
```bash
bash ~/.claude/skills/inbox-zero/scripts/scan-emails.sh
bash ~/.claude/skills/inbox-zero/scripts/classify-emails.sh
```

### Quick check (via Gmail MCP)
Use Gmail MCP tools: `gmail_search_messages` with query `is:unread` per account.
Then apply DPYS classification logic from the rules engine.

## Classification Rules (13 rules)
1. SKIP: Gmail promotions/spam labels
2. SKIP: Known skip domains (leboncoin, amazon, etc.)
3. DISPATCH: Known service domains (GitHub, Vercel, Supabase, etc.)
4. DISPATCH: Newsletters / noreply senders
5. SKIP: Newsletter/marketing subject patterns
6. DISPATCH: SaaS tool updates
7. YOURS: VIP Tier 1 clients (Wella/Henkel) — override to PREP minimum
8. PREP: Tier 2-3 clients (Smart Renovation, Imagin, etc.)
9. YOURS: Negative tone / escalation signals
10. YOURS: Legal / RGPD / contract keywords
11. PREP: New business / prospect signals
12. PREP: Meeting requests (override DISPATCH → PREP)
13. DISPATCH: Transactional subjects (receipts, confirmations)

## Output
- JSON classified report with confidence scores
- Markdown summary with stats table
- JSONL logs per category

## Data Files
- `data/config.json` — account configuration
- `data/dispatch-responses.json` — auto-response templates
