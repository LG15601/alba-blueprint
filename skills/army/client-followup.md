---
name: client-followup
description: |
  Detect stale client conversations, draft follow-up emails, and manage the
  relance pipeline. Ensures no client falls through the cracks by monitoring
  email recency, project milestones, and engagement signals. Use when asked
  to "check followups", "relances", "client followup", or on daily cron.
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
  - mcp__claude_ai_Gmail__gmail_read_thread
  - mcp__claude_ai_Gmail__gmail_create_draft
---

# Client Follow-up -- Relance Pipeline

Systematic follow-up engine that detects stale conversations and ensures no
client or prospect communication goes cold without a deliberate decision.

## Arguments
- `/client-followup` -- full scan across all clients
- `/client-followup [client]` -- check specific client
- `/client-followup prospects` -- only check prospect pipeline
- `/client-followup draft [client]` -- generate follow-up email for specific client

## Step 1: Load Client Data

```bash
# Load CRM data
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
cat /Users/alba/AZW/alba-blueprint/data/pipeline.json 2>/dev/null
```

Build the follow-up matrix:

| Client        | Tier     | Last Contact | Days Silent | SLA   | Status     |
|---------------|----------|--------------|-------------|-------|------------|
| [name]        | Platinum | [date]       | [N]         | 4h    | [OK/LATE]  |

## Step 2: Detect Stale Conversations

### Email Recency Check
For each client/prospect contact:
```
gmail_search_messages: query="from:[email] OR to:[email]" newer_than:30d
```

### Staleness Thresholds by Tier

| Tier     | Warning Threshold | Critical Threshold | Action              |
|----------|-------------------|--------------------|---------------------|
| Platinum | 3 days            | 5 days             | Immediate alert     |
| Gold     | 5 days            | 10 days            | Same-day follow-up  |
| Silver   | 7 days            | 14 days            | Weekly follow-up    |
| Bronze   | 14 days           | 30 days            | Bi-weekly check     |
| Prospect | 5 days            | 10 days            | Follow-up or close  |

### Staleness Categories
- **ACTIVE**: Communication within threshold. No action needed.
- **WARMING**: Approaching threshold. Monitor.
- **STALE**: Past warning threshold. Draft follow-up.
- **CRITICAL**: Past critical threshold. Alert Ludovic + draft follow-up.
- **DORMANT**: No contact in 60+ days. Review: keep or archive.

## Step 3: Analyze Context Before Follow-up

Before drafting any follow-up, understand WHY it went silent:

### 3a. Read Last Thread
```
gmail_read_thread: [thread_id of last conversation]
```

Determine:
- Who sent the last message? (us or them)
- What was the topic?
- Was there an open question?
- Was there a deliverable promised?
- Was the tone positive, neutral, or tense?

### 3b. Check Project Status
- Any pending deliverables from us? If yes, follow up on THAT first
- Any open issues or bugs they reported?
- Any milestone approaching?

### 3c. Determine Follow-up Type

| Situation                     | Follow-up Type        | Tone           |
|-------------------------------|-----------------------|----------------|
| We owe them something         | Delivery update       | Proactive       |
| They owe us feedback          | Gentle nudge          | Light           |
| Proposal sent, no response    | Value reinforcement   | Confident       |
| Project complete, no feedback | Satisfaction check    | Warm            |
| They went silent mid-project  | Status check          | Concerned       |
| Renewal approaching           | Renewal preparation   | Strategic       |
| Cold prospect                 | Re-engagement         | Fresh angle     |

## Step 4: Draft Follow-up Emails

### Follow-up Email Rules
- Short: max 100 words for a nudge, 200 for a substantive follow-up
- Reference something specific from the last exchange
- Provide value, not just "checking in"
- One clear ask or question per email
- French by default, match the thread language
- Never guilt-trip ("I haven't heard from you")
- Never be pushy ("Just following up for the 3rd time")

### Templates by Type

**Gentle Nudge (they owe us feedback):**
```
Bonjour [Prenom],

J'espere que [specific project/topic] avance bien de votre cote.

[One sentence adding value: insight, tip, or relevant news for their sector]

Dites-moi quand vous souhaitez qu'on fasse le point.

Cordialement,
Ludovic
```

**Value Reinforcement (proposal pending):**
```
Bonjour [Prenom],

[Relevant data point or case study result related to their needs]

Si vous avez des questions sur la proposition, je suis disponible [specific times].

Cordialement,
Ludovic
```

**Delivery Update (we owe them something):**
```
Bonjour [Prenom],

Point d'avancement sur [deliverable]:
- [Status item 1]
- [Status item 2]
- Prochaine etape: [what and when]

[Question if needed, or "Je vous tiens informe de la suite."]

Cordialement,
Ludovic
```

**Re-engagement (dormant prospect):**
```
Bonjour [Prenom],

[Reference to something new since last contact: a result, a market change, a new capability]

[Connect it to their specific situation]

Ca vaut le coup d'en reparler?

Cordialement,
Ludovic
```

## Step 5: Create Drafts and Track

### Create Gmail Drafts
For each follow-up:
```
gmail_create_draft: appropriate account, to, subject (Re: original thread), body
```

### Track in Follow-up Log
```bash
mkdir -p ~/.alba/followups
```

Write to `~/.alba/followups/YYYY-MM-DD.json`:
```json
{
  "date": "2026-04-01",
  "followups": [
    {
      "client": "Smart Renovation",
      "tier": "Gold",
      "contact": "Marie Durand",
      "last_contact": "2026-03-25",
      "days_silent": 7,
      "status": "STALE",
      "followup_type": "gentle_nudge",
      "draft_created": true,
      "account": "ludovic@orchestraintelligence.fr",
      "context": "Waiting for feedback on phase 2 proposal"
    }
  ]
}
```

## Step 6: Report

### Telegram Summary (French)
```
RELANCES -- [DATE]

CLIENTS:
- [N] actifs (contact recent)
- [N] a relancer (brouillons crees)
- [N] critiques (alerte)

DETAILS RELANCES:
- [Client] ([tier]): [days] jours sans contact -> [followup type]
- [Client] ([tier]): [days] jours sans contact -> [followup type]

PROSPECTS:
- [N] actifs
- [N] a relancer
- [N] a archiver (60+ jours)

Brouillons a valider: [N]
```

## Orchestra Rules
- Never send follow-ups automatically. Always create as draft
- Respect client preferences (some prefer less frequent contact)
- If a client explicitly asked for space/time: respect it, note the date they asked
- RGPD: follow-up tracking data stays local
- Never follow up on weekends or French holidays
- Business hours only: 9h-18h Paris time for scheduling
- If a client is in dispute or has unpaid invoices: flag for Ludovic, do NOT follow up normally
- Adapt tone to relationship history (long-term warm client vs new formal contact)
- Track follow-up frequency: never send more than 3 follow-ups without a response
- After 3 unanswered follow-ups: escalate to Ludovic for decision (persist or archive)
