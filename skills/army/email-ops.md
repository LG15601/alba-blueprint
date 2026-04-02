---
name: email-ops
description: |
  Full DPYS email classification and draft response system across 3 accounts.
  Extends inbox-zero with actual response drafting, send scheduling, and follow-up
  tracking. Use when asked to "handle emails", "draft responses", "email ops",
  or as part of morning routine.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Agent
  - Glob
  - Grep
  - mcp__claude_ai_Gmail__gmail_search_messages
  - mcp__claude_ai_Gmail__gmail_read_message
  - mcp__claude_ai_Gmail__gmail_read_thread
  - mcp__claude_ai_Gmail__gmail_create_draft
  - mcp__claude_ai_Gmail__gmail_list_labels
  - mcp__claude_ai_Gmail__gmail_get_profile
---

# Email Ops -- Full Email Management

Production email management extending the DPYS classification system with actual
response drafting, smart scheduling, and follow-up tracking across 3 accounts.

## Accounts
1. **sales@orchestraintelligence.fr** -- Sales inquiries, prospects, partnerships
2. **ludovic@orchestraintelligence.fr** -- Client communication, business operations
3. **ludovic.goutel@gmail.com** -- Personal, some business overflow

## Step 1: Scan All Accounts

For each account, fetch unread emails:
```
gmail_search_messages: query="is:unread" (per account)
```

Log scan timestamp:
```bash
mkdir -p ~/.alba/email-ops
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > ~/.alba/email-ops/last-scan
```

## Step 2: DPYS Classification

Apply the 13-rule classification engine from inbox-zero:

### DISPATCH (D) -- Auto-handle
- GitHub notifications, CI alerts, SaaS updates
- Newsletters from known senders
- Transactional emails (receipts, confirmations)
- Action: Archive, log in JSONL

### PREP (P) -- Draft response needed
- Client emails (Tier 2-3)
- Meeting requests
- Prospect inquiries
- New business signals
- Action: Draft response, queue for review

### YOURS (Y) -- Ludovic must handle
- VIP clients (Wella, Henkel, Tier 1)
- Legal, contracts, RGPD
- Negative sentiment / escalations
- Personal correspondence
- Action: Flag priority, summarize, alert via Telegram

### SKIP (S) -- Archive silently
- Spam, promotions
- Known skip domains
- Marketing newsletters not on subscribe list
- Action: Archive, no log needed

## Step 3: Draft Responses (for PREP emails)

For each PREP email, generate a draft response:

### Response Rules
- Match the language of the incoming email (French default)
- Professional but warm tone, not corporate
- Address the specific question or request
- If client: reference their project status from CRM
- If prospect: qualify without hard-selling
- Keep responses under 200 words (unless complex topic)
- Always include a clear next step or question

### Response Templates by Type

**Client Update Request:**
```
Bonjour [Prenom],

[Direct answer to their question in 1-2 sentences.]

[Additional context if needed, 2-3 sentences max.]

[Next step: "Je vous envoie le document d'ici demain" or similar concrete commitment.]

Cordialement,
Ludovic
```

**Prospect Inquiry:**
```
Bonjour [Prenom],

Merci pour votre message. [Acknowledge their specific situation in 1 sentence.]

[Brief relevant capability mention, connected to their pain point.]

[Concrete next step: "Seriez-vous disponible pour un appel de 20 minutes cette semaine?"]

Cordialement,
Ludovic Goutel
Orchestra Intelligence
```

**Meeting Request:**
```
Bonjour [Prenom],

[Confirm or propose alternative time.]

[If confirming: "Je vous envoie une invitation calendrier."]
[If proposing: "Voici mes disponibilites: [slots]"]

Cordialement,
Ludovic
```

### Draft Quality Rules
- No draft should be sent without Ludovic's review (mark as draft in Gmail)
- Include "[DRAFT - A VALIDER]" in internal tracking
- For VIP clients: always flag for manual review even if response seems simple
- Never promise deadlines without checking project status
- Never share pricing without checking current rate card

## Step 4: Create Gmail Drafts

For each response, create a draft in the appropriate account:
```
gmail_create_draft: to, subject, body, in_reply_to
```

## Step 5: Follow-up Tracking

### Detect Stale Threads
Identify emails that:
- Were sent by Ludovic 3+ days ago with no reply
- Are client emails awaiting response for 24+ hours
- Have "urgent" or "ASAP" in subject with no response in 4h

### Follow-up Queue
```bash
mkdir -p ~/.alba/email-ops/followups
```

Write to `~/.alba/email-ops/followups/YYYY-MM-DD.json`:
```json
{
  "stale_threads": [
    {
      "account": "ludovic@orchestraintelligence.fr",
      "thread_id": "...",
      "subject": "Proposition commerciale Smart Renovation",
      "last_sent": "2026-03-28",
      "days_waiting": 4,
      "contact": "Marie Durand",
      "suggested_followup": "Relance douce -- demander si elle a eu le temps de consulter"
    }
  ]
}
```

## Step 6: Report

### Email Summary (for morning brief or standalone)
```
EMAILS -- [DATE] [TIME]

TRAITES: [N] emails sur 3 comptes
- sales@oi: [X] ([D]D [P]P [Y]Y [S]S)
- ludovic@oi: [X] ([D]D [P]P [Y]Y [S]S)
- gmail: [X] ([D]D [P]P [Y]Y [S]S)

BROUILLONS CREES: [N]
[list of subjects with account]

A TRAITER TOI-MEME: [N]
[list of YOURS emails with 1-line summary]

RELANCES SUGGEREES: [N]
[list of stale threads with suggested action]
```

## Step 7: Archive and Log

```bash
mkdir -p ~/.alba/email-ops/logs
# Daily log with full classification data
echo '[classification data]' > ~/.alba/email-ops/logs/YYYY-MM-DD.jsonl
```

## Orchestra Rules
- Never auto-send emails. Always create as draft for Ludovic's review
- RGPD: email content stays local, never logged to external services
- Client emails get priority over all others
- If an email contains contract/legal terms: ALWAYS classify as YOURS
- Never cc/bcc anyone without explicit instruction
- Response time SLAs: VIP 4h, Client 24h, Prospect 48h, Other 72h
- If multiple emails from same sender: read all before responding (avoid contradictions)
- French spelling must be perfect (use proper accents)
- Never include "Envoye depuis mon iPhone" or similar auto-signatures
