---
name: daily-briefing
description: "Generate morning briefing with calendar, email, tasks, news, Twitter, Slack. Use when user says 'bonjour', 'good morning', or asks for today's summary."
user-invocable: true
allowed-tools:
  - WebSearch
  - WebFetch
  - Read
  - Bash
  - Agent
  - Grep
  - Glob
---

# Daily Briefing

Generate a comprehensive morning briefing for Ludovic. Run sub-agents in parallel for speed.

## Data Sources (parallel)

1. **Calendar** — Today's events and meetings via Google Calendar MCP
2. **Email** — Unread important emails via Gmail MCP (search: `is:unread is:important`)
3. **Tasks** — Open tasks across active projects (check .gsd/ or .planning/ directories)
4. **GitHub** — Overnight commits on key repos: `gh api notifications --jq '.[] | .subject.title'`
5. **Twitter** — AI news + mentions: search X MCP for #ClaudeCode, #AIAgents, @orchestra
6. **Slack** — Unread messages in key channels
7. **AI News** — Top 3 developments via WebSearch ("AI news today")

## Output Format (French)

```
Bonjour Ludovic ! Voici ton briefing du [date] :

AGENDA
- [heure] [event] — [details]

EMAILS IMPORTANTS
- [from]: [subject] — [1-line summary]

TACHES EN COURS
- [project]: [task] — [status]

GITHUB
- [repo]: [commit/PR summary]

ACTUS IA
- [headline] — [1-line takeaway]

PRIORITE DU JOUR
[What should Ludovic focus on based on above]
```

## Rules
- Be concise — this is a briefing, not a report
- Prioritize: urgent items first
- If a data source is unavailable, skip it (don't error)
- Total response under 40 lines
