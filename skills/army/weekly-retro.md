---
name: weekly-retro
description: |
  Weekly engineering retrospective with metrics, trends, and improvement actions.
  Analyzes commit history, PR activity, CI health, agent performance, and business
  metrics across all Orchestra repos and operations. Use when asked for "retro",
  "weekly review", "bilan semaine", or triggered Friday 17:00.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
  - Grep
  - Agent
---

# Weekly Retro -- Engineering & Operations Retrospective

Comprehensive weekly retrospective analyzing code, operations, and business
metrics. Tracks trends over time and generates actionable improvements.

## Arguments
- `/weekly-retro` -- default: last 7 days
- `/weekly-retro 14d` -- last 14 days
- `/weekly-retro compare` -- this week vs last week
- `/weekly-retro month` -- monthly summary (last 30 days)

## Step 1: Collect Engineering Metrics

### 1a. Commit History
```bash
# Commits across all repos in the last 7 days
SINCE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)
for REPO in alba-blueprint orchestra-website orchestra-app orchestra-api; do
  echo "=== $REPO ==="
  cd /Users/alba/AZW/$REPO 2>/dev/null && \
    git log --since="${SINCE}T00:00:00" --oneline --no-merges 2>/dev/null | wc -l
  cd /Users/alba/AZW/$REPO 2>/dev/null && \
    git log --since="${SINCE}T00:00:00" --format="%h %s" --no-merges 2>/dev/null | head -20
done
```

### 1b. PR Activity
```bash
# For each repo
for REPO in orchestraintelligence/alba-blueprint; do
  echo "=== $REPO ==="
  gh pr list --repo "$REPO" --state all --search "updated:>=$SINCE" --json number,title,state,mergedAt,createdAt 2>/dev/null
done
```

### 1c. CI Health
```bash
for REPO in orchestraintelligence/alba-blueprint; do
  gh run list --repo "$REPO" --limit 20 --json status,conclusion,createdAt 2>/dev/null
done
```

### 1d. Code Quality
```bash
# Lines changed this week
for REPO_DIR in /Users/alba/AZW/alba-blueprint; do
  cd "$REPO_DIR" 2>/dev/null && \
    git diff --stat "HEAD@{7 days ago}" HEAD 2>/dev/null | tail -1
done
```

## Step 2: Collect Operations Metrics

### 2a. Agent Performance
```bash
# Dispatch completion rates
find ~/.alba/dispatches -name "*.json" -newer /tmp/retro-since 2>/dev/null | while read f; do
  echo "$f: $(cat "$f" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"{sum(1 for t in d.get('tasks',[]) if t.get('status')=='DONE')}/{len(d.get('tasks',[]))}\")" 2>/dev/null)"
done
```

### 2b. Email Operations
```bash
# Emails processed this week
find ~/.alba/email-ops/logs -name "*.jsonl" -newer /tmp/retro-since 2>/dev/null | wc -l
```

### 2c. Content Output
```bash
# Articles and posts created
find ~/.alba/content -name "*.md" -newer /tmp/retro-since 2>/dev/null | wc -l
```

### 2d. System Health Trends
```bash
# Health check results over the week
find ~/.alba/health -name "*.json" -newer /tmp/retro-since 2>/dev/null | while read f; do
  echo "$(basename $f): $(cat "$f" | python3 -c "import json,sys; print(json.load(sys.stdin).get('overall_status','unknown'))" 2>/dev/null)"
done
```

## Step 3: Collect Business Metrics

### 3a. Client Pipeline
```bash
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
cat /Users/alba/AZW/alba-blueprint/data/pipeline.json 2>/dev/null
```

Compute:
- Total MRR this week vs last week
- Client health score average
- New prospects added
- Deals moved forward
- Churn risk count

### 3b. Follow-up Metrics
```bash
# Follow-up compliance
find ~/.alba/followups -name "*.json" -newer /tmp/retro-since 2>/dev/null
```

## Step 4: Trend Analysis

### Compare to Previous Period
Load previous retro data:
```bash
cat ~/.alba/retros/$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)-retro.json 2>/dev/null || echo "No previous retro"
```

### Key Metrics Table
| Metric                    | This Week | Last Week | Trend    |
|---------------------------|-----------|-----------|----------|
| Commits (all repos)       | [N]       | [N]       | [up/down/flat] |
| PRs merged                | [N]       | [N]       | ...      |
| CI pass rate              | [%]       | [%]       | ...      |
| Tasks dispatched          | [N]       | [N]       | ...      |
| Tasks completed           | [N]       | [N]       | ...      |
| Completion rate           | [%]       | [%]       | ...      |
| Emails processed          | [N]       | [N]       | ...      |
| Content pieces created    | [N]       | [N]       | ...      |
| MRR                       | [EUR]     | [EUR]     | ...      |
| Client health (avg)       | [/100]    | [/100]    | ...      |
| System uptime             | [%]       | [%]       | ...      |
| Agent errors              | [N]       | [N]       | ...      |

## Step 5: Generate Retrospective

### What Went Well
Identify top 3-5 wins:
- Features shipped
- Clients satisfied
- Processes that worked smoothly
- Metrics that improved

### What Could Be Better
Identify top 3-5 areas:
- Failed tasks and root causes
- Bottlenecks in workflows
- Metrics that declined
- Recurring problems

### Action Items
For each "could be better" item, propose a concrete improvement:
- Who: Alba (automated) or Ludovic (manual)
- What: Specific action with measurable outcome
- When: This week or scheduled future date
- How: Implementation approach

### Observations
Non-actionable but noteworthy trends:
- Emerging patterns in client behavior
- Technology shifts affecting our work
- Resource utilization insights

## Step 6: Output

### Save Retro Data
```bash
mkdir -p ~/.alba/retros
echo '[retro json]' > ~/.alba/retros/YYYY-MM-DD-retro.json
echo '[retro report]' > ~/.alba/retros/YYYY-MM-DD-retro.md
```

### Telegram Report (French)
```
RETRO HEBDOMADAIRE -- Semaine du [DATE]

BILAN CHIFFRE:
- [N] commits, [N] PRs merges
- CI: [%] de reussite
- Taches: [done]/[total] ([%])
- MRR: [amount] EUR ([trend])

CE QUI A BIEN MARCHE:
1. [win with context]
2. [win with context]
3. [win with context]

A AMELIORER:
1. [issue] -> Action: [improvement]
2. [issue] -> Action: [improvement]
3. [issue] -> Action: [improvement]

FOCUS SEMAINE PROCHAINE:
- [priority 1]
- [priority 2]
- [priority 3]
```

### Persistence for Trends
Each retro saves metrics in structured JSON so future retros can compute
multi-week trends. After 12 weeks, compress weekly data to monthly summaries.

## Orchestra Rules
- Retro always in French for Telegram, data files in English
- Honest assessment: never sugarcoat metrics
- If MRR declined: flag prominently with root cause
- If agent error rate increased: diagnose before next week
- Action items must be SMART: specific, measurable, achievable, relevant, time-bound
- Never compare Orchestra to competitors in retros (internal focus)
- Include Ludovic's time investment where trackable
- Friday 17:00 default, but available on demand
