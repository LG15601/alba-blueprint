---
name: army-report
description: |
  Compile overnight agent results into a French morning report for Telegram.
  Summarizes what agents accomplished while Ludovic slept: tasks completed,
  errors encountered, metrics, and recommendations. Use when asked for
  "rapport", "overnight results", or triggered at 07:30 daily.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - mcp__plugin_telegram_telegram__reply
  - mcp__plugin_telegram_telegram__react
---

# Army Report -- Overnight Operations Summary

Compiles everything that happened while Ludovic was offline into a single,
actionable French briefing sent via Telegram.

## Trigger Conditions
- Cron at 07:30 daily
- Ludovic sends "rapport" or "qu'est-ce qui s'est passe"
- Manual `/army-report` invocation

## Step 1: Collect Overnight Data

### 1a. Dispatch Results
```bash
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d)
# Yesterday's dispatch completion status
cat ~/.alba/dispatches/${YESTERDAY}.json 2>/dev/null
# Today's early dispatch if exists
cat ~/.alba/dispatches/${TODAY}.json 2>/dev/null
```

### 1b. Agent Execution Logs
```bash
# All agent runs since last report (last 12h)
find ~/.alba/logs -name "*.log" -newer ~/.alba/last-report-ts 2>/dev/null | head -20
find ~/.alba/logs -name "*.json" -newer ~/.alba/last-report-ts 2>/dev/null | head -20
```

### 1c. Nightly Routine Results
```bash
cat ~/.alba/nightly/$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d)-results.json 2>/dev/null || echo "No nightly results"
```

### 1d. System Alerts
```bash
# Any alerts generated overnight
find ~/.alba/alerts -name "*.json" -newer ~/.alba/last-report-ts 2>/dev/null
```

### 1e. GitHub Activity
```bash
# PRs merged/opened overnight
gh pr list --state all --limit 10 --json title,state,updatedAt,url 2>/dev/null || echo "No GH access"
# CI failures
gh run list --limit 5 --json status,name,conclusion,updatedAt 2>/dev/null || echo "No GH runs"
```

### 1f. Email Activity
```bash
# Count new emails per account since midnight
# Uses Gmail MCP if available, falls back to gog CLI
echo "Check email counts via Gmail MCP tools"
```

## Step 2: Compute Metrics

Calculate overnight KPIs:
- **Tasks completed**: count of DONE tasks from dispatch
- **Tasks failed**: count of FAILED + BLOCKED
- **Completion rate**: done / (done + failed + blocked)
- **Agent uptime**: based on health check logs
- **Errors encountered**: unique error count from logs
- **Emails processed**: count classified by inbox-zero
- **PRs activity**: opened, merged, failed CI
- **Alerts triggered**: count and severity

## Step 3: Generate French Report

Format the report for Telegram. Keep it scannable. Use line breaks, not markdown
(Telegram renders markdown poorly in long messages).

### Report Template

```
RAPPORT ALBA -- [DATE] 07:30

RESUME
[1-2 phrases: ce qui s'est passe cette nuit]

TACHES ([X] terminees / [Y] total)
[list of completed tasks with brief result]

ALERTES ([N])
[any critical alerts, or "Aucune alerte"]

EMAILS
- sales@oi: [N] nouveaux ([M] classes)
- ludovic@oi: [N] nouveaux ([M] classes)
- gmail: [N] nouveaux ([M] classes)

CODE
- PRs: [merged/opened/failed]
- CI: [status]
- Derniers commits: [summary]

SYSTEME
- Disque: [XX]% utilise
- Docker: [N] conteneurs OK
- Tailscale: [connected/disconnected]

ERREURS ([N])
[list of errors with brief context, or "Aucune erreur"]

A FAIRE AUJOURD'HUI
[top 3 priority items for today]

RECOMMANDATIONS
[1-3 actionable suggestions based on overnight data]
```

## Step 4: Classify Report Urgency

Based on overnight results, set report tone:
- **NOMINAL**: Everything green, standard report
- **ATTENTION**: Minor issues, some failed tasks, non-critical alerts
- **ALERTE**: Critical failures, system issues, client-facing problems

Prepend urgency indicator:
- NOMINAL: no prefix needed
- ATTENTION: "-- ATTENTION --" at top
- ALERTE: "-- ALERTE CRITIQUE --" at top, send twice (notification + detail)

## Step 5: Send and Archive

1. Send report via Telegram to Ludovic
2. Archive report:
```bash
mkdir -p ~/.alba/reports
# Archive for future reference
echo "[report content]" > ~/.alba/reports/${TODAY}-army-report.md
# Update last report timestamp
touch ~/.alba/last-report-ts
```

## Step 6: Prepare Today's Context

After sending the report:
1. Carry over incomplete tasks to today's dispatch
2. Flag any tasks that need Ludovic's decision
3. Pre-stage the daily-dispatch with known tasks
4. If there are critical items, prompt for immediate attention

## Orchestra Rules
- Report always in French
- Never include raw JSON or technical logs in the Telegram message
- Client names allowed in Telegram (private channel with Ludovic)
- If system is down: send minimal alert via backup channel (Pushover)
- Timestamps in Paris timezone (Europe/Paris)
- Round numbers: "environ 2h" not "1h47m23s"
- No emojis unless Ludovic uses them first
