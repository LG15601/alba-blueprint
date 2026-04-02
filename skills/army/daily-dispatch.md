---
name: daily-dispatch
description: |
  Parse todo list from Telegram/notes, create prioritized task queue, assign to sub-agents.
  Central task orchestrator for Alba's daily operations. Use when asked to "dispatch",
  "plan today", "assign tasks", "queue work", or at start of each workday.
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
  - WebSearch
  - mcp__plugin_telegram_telegram__reply
  - mcp__plugin_telegram_telegram__react
---

# Daily Dispatch -- Task Orchestrator

Central nervous system for Alba's daily operations. Parses incoming tasks from all
sources, prioritizes them, creates a task queue, and assigns work to sub-agents.

## Trigger Conditions
- Ludovic sends a task list via Telegram
- Morning brief generates action items
- Cron trigger at 08:00
- Manual `/daily-dispatch` invocation

## Step 1: Collect Tasks from All Sources

### 1a. Telegram Messages
Check recent Telegram messages for task instructions from Ludovic.
Tasks come in many forms:
- Explicit lists: "Fais X, Y, Z"
- Inline requests: "Il faudrait que..."
- Forwarded messages with implicit tasks
- Voice-to-text transcriptions (look for "transcription:" prefix)

### 1b. Standing Orders
```bash
cat ~/.alba/standing-orders.md 2>/dev/null || echo "No standing orders found"
```

### 1c. Previous Day Carryover
```bash
# Check yesterday's dispatch for incomplete tasks
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d)
cat ~/.alba/dispatches/${YESTERDAY}.json 2>/dev/null || echo "No carryover"
```

### 1d. Morning Brief Action Items
```bash
TODAY=$(date +%Y-%m-%d)
cat ~/.alba/briefs/${TODAY}-actions.json 2>/dev/null || echo "No brief actions yet"
```

## Step 2: Parse and Classify Each Task

For each task found, extract:
- **what**: Clear description in imperative form
- **category**: One of: CLIENT, CODE, CONTENT, SALES, ADMIN, INFRA, RESEARCH
- **urgency**: CRITICAL (do now), HIGH (today), MEDIUM (this week), LOW (when possible)
- **estimated_minutes**: Rough estimate (15, 30, 60, 120, 240)
- **assigned_skill**: Which skill/agent handles this (or "manual" if Ludovic must do it)
- **dependencies**: Other tasks that must complete first

### Priority Matrix
| Urgency   | Client-facing | Revenue-impact | Internal |
|-----------|---------------|----------------|----------|
| CRITICAL  | P0            | P0             | P1       |
| HIGH      | P1            | P1             | P2       |
| MEDIUM    | P2            | P2             | P3       |
| LOW       | P3            | P3             | P4       |

### Auto-Assignment Rules
| Category  | Default Skill         | Agent Type     |
|-----------|-----------------------|----------------|
| CLIENT    | /client-followup      | Explore        |
| CODE      | /code-patrol          | Worktree       |
| CONTENT   | /seo-writer or /linkedin-post | General  |
| SALES     | /prospect-hunt or /lead-qualify | Explore  |
| ADMIN     | /email-ops or /invoice-prep | General    |
| INFRA     | /health-check         | General        |
| RESEARCH  | /competitor-watch or /veille | Explore    |

## Step 3: Build Task Queue

Write the dispatch to:
```bash
mkdir -p ~/.alba/dispatches
```

Output file: `~/.alba/dispatches/YYYY-MM-DD.json`

Schema:
```json
{
  "date": "2026-04-01",
  "generated_at": "2026-04-01T08:00:00Z",
  "total_tasks": 12,
  "estimated_total_minutes": 480,
  "tasks": [
    {
      "id": "D-20260401-001",
      "what": "Relancer Smart Renovation sur la proposition commerciale",
      "category": "CLIENT",
      "urgency": "HIGH",
      "priority": "P1",
      "estimated_minutes": 15,
      "assigned_skill": "client-followup",
      "dependencies": [],
      "status": "QUEUED",
      "source": "telegram"
    }
  ],
  "manual_tasks": [
    {
      "what": "Appel Wella 14h -- negociation budget Q2",
      "reason": "Requires Ludovic's direct involvement"
    }
  ]
}
```

## Step 4: Execute Autonomous Tasks

For each task with `status: QUEUED` and no unmet dependencies:
1. Launch the assigned skill via Agent (sub-agent)
2. Update task status to `RUNNING`
3. On completion, update to `DONE` with result summary
4. On failure, update to `FAILED` with error and retry count

### Parallelism Rules
- Max 3 concurrent sub-agents
- Client-facing tasks: sequential (avoid conflicting communications)
- Code tasks: can run in parallel if different repos
- Content tasks: sequential (voice consistency)
- Never run more than 1 email-ops at a time

### Retry Policy
- Transient failures (network, rate limit): retry once after 60s
- Permanent failures (missing data, auth error): mark BLOCKED, alert Ludovic
- 3 consecutive failures on same task: escalate

## Step 5: Report to Ludovic

Send dispatch summary via Telegram in French:

```
Dispatch du jour -- [DATE]

[N] taches planifiees ([M] min estimees)
[X] deja lancees, [Y] en attente de toi

PRIORITE HAUTE:
- [task description] -> [skill] [status]
- [task description] -> [skill] [status]

A FAIRE TOI-MEME:
- [manual task + reason]

Je lance le reste. Updates au fil de l'eau.
```

## Step 6: Track Progress

Throughout the day, maintain the dispatch file:
- Update task statuses as they complete
- Log start/end times per task
- Track actual vs estimated time
- Flag tasks that exceed 2x their estimate

End-of-day summary (triggered at 19:00 or on request):
```
Bilan du jour:
- [X]/[N] taches terminees
- [Y] en cours
- [Z] reportees a demain
- Temps estime: [M]min / Temps reel: [R]min
```

## Orchestra Rules
- All Telegram messages in French
- Never mention client names in external channels
- RGPD: no personal data in task descriptions outside encrypted storage
- If a task involves client data: process locally, never send to external APIs
- Revenue-impacting tasks always get P0-P1 priority
