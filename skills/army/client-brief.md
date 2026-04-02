---
name: client-brief
description: |
  Prepare comprehensive meeting briefs pulling from CRM, emails, project status,
  and previous interactions. Generates a 1-page French briefing document before
  any client meeting. Use when asked to "prepare meeting", "brief client",
  "prep for [client]", or auto-triggered 2h before calendar meetings.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - Glob
  - Grep
  - WebSearch
  - mcp__claude_ai_Gmail__gmail_search_messages
  - mcp__claude_ai_Gmail__gmail_read_thread
  - mcp__claude_ai_Google_Calendar__authenticate
---

# Client Brief -- Meeting Preparation

Generates a comprehensive 1-page briefing document before any client meeting.
Pulls data from CRM, email history, project status, and web intelligence.

## Arguments
- `/client-brief [client name]` -- prep for specific client
- `/client-brief next` -- prep for next upcoming meeting
- `/client-brief today` -- prep all meetings for today

## Step 1: Identify the Meeting

### If client name given:
```bash
# Find client in CRM
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null | grep -i "[client]"
```

### If "next" or "today":
Check calendar for upcoming meetings with external attendees.
Filter out internal meetings, standup, personal events.

### Extract Meeting Context
- **Who**: All attendees with names and roles
- **When**: Date, time, duration
- **Where**: Location or video link
- **Topic**: From calendar event title/description
- **Type**: New business, project review, upsell, support, renewal

## Step 2: Gather Intelligence

### 2a. CRM Data
```bash
# Client record from clients.json
# Extract: MRR, health score, tier, contact details, active projects
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
```

Key data points:
- Current MRR and payment history
- Health score and trend (improving/declining/stable)
- Active projects and their status
- Next milestones or deliverables
- Open issues or complaints
- Upsell opportunities identified

### 2b. Email History (last 30 days)
```
gmail_search_messages: query="from:[client domain] OR to:[client domain]" newer_than:30d
```

Extract:
- Last 5 email exchanges (topic summaries)
- Any unresolved questions
- Tone of recent communication (positive/neutral/tense)
- Promises made by either side
- Attachments exchanged (proposals, deliverables)

### 2c. Project Status
```bash
# Check GitHub repos for client-related activity
gh issue list --repo orchestraintelligence/[client-repo] --state open 2>/dev/null
gh pr list --repo orchestraintelligence/[client-repo] --state all --limit 5 2>/dev/null
```

### 2d. Web Intelligence
- Recent news about the client company (last 30 days)
- LinkedIn activity of the meeting attendees
- Industry news relevant to their sector
- Competitor moves in their space

### 2e. Previous Meeting Notes
```bash
# Check for previous brief or meeting notes
find ~/.alba/briefs/client -name "*[client]*" -type f | sort -r | head -3
```

## Step 3: Generate Brief

### Brief Format (1 page, French)

```markdown
BRIEF CLIENT -- [Company Name]
Date: [meeting date and time]
Participants: [names and roles]
Type: [meeting type]

---

CONTEXTE
[2-3 sentences: who they are, what we do for them, current state of the relationship]

CHIFFRES CLES
- MRR: [amount] EUR ([trend])
- Score sante: [score]/100 ([trend])
- Projets actifs: [count]
- Prochain jalon: [milestone and date]

HISTORIQUE RECENT (30 jours)
- [date]: [key email/event summary]
- [date]: [key email/event summary]
- [date]: [key email/event summary]

POINTS EN SUSPENS
- [open issue 1 with context]
- [open issue 2 with context]

OBJECTIFS DE LA REUNION
1. [Primary objective based on meeting type]
2. [Secondary objective]
3. [Tertiary objective]

POINTS DE VIGILANCE
- [Risk or sensitive topic to be aware of]
- [Client pain point to address proactively]

OPPORTUNITES
- [Upsell or expansion opportunity with context]
- [New need detected from signals]

PREPARATION
- [ ] [Document to prepare before meeting]
- [ ] [Data point to verify]
- [ ] [Question to research]

ACTUALITES CLIENT
- [Recent news about their company]
- [Sector development relevant to them]
```

## Step 4: Risk Assessment

Evaluate meeting risk level:
- **GREEN**: Routine meeting, client happy, no open issues
- **YELLOW**: Some open issues, client neutral, renewal approaching
- **RED**: Client unhappy, overdue deliverables, churn risk

If RED: Add a "PLAN DE RETENTION" section with specific recovery steps.

## Step 5: Output

### Save Brief
```bash
mkdir -p ~/.alba/briefs/client
# Save brief document
echo "[brief content]" > ~/.alba/briefs/client/YYYY-MM-DD-[client-slug].md
```

### Notify via Telegram (French)
```
Brief pret: [Client Name] -- [meeting time]
Type: [meeting type]
MRR: [amount] EUR | Sante: [score]/100
Points cles: [1-2 bullet points]
[1 risk/opportunity highlight]

Brief complet: [file path]
```

### Calendar Note
If possible, add brief summary to calendar event description.

## Step 6: Post-Meeting Update

After the meeting (when Ludovic provides notes):
- Update CRM with meeting outcomes
- Create follow-up tasks in dispatch queue
- Send meeting summary email if requested
- Update health score if new information

## Orchestra Rules
- Briefs always in French
- Never share briefs outside Orchestra (internal document)
- Include client's preferred communication style if known
- If new attendee from client side: research them before meeting
- Always include MRR in brief (revenue awareness)
- If brief reveals churn risk: alert Ludovic immediately, do not wait for meeting
- Previous commitments made to client: highlight prominently
- Never fabricate data. If information unavailable, say "Non disponible" not estimates
- Respect confidentiality: never include data from other clients in a brief
