---
name: morning-brief
description: "Generate daily morning briefing from 6 real data sources: emails, calendar, GitHub, client pipeline, system health, Google Drive. Use when Ludovic says 'bonjour', 'briefing', or asks for today's summary."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
  - Glob
  - Grep
---

# Morning Brief Generator

Production daily synthesis pulling from 6 real data sources.

## Data Sources
1. **Emails** — 3 accounts via `gog` CLI (Google CLI)
2. **Calendar** — Today + tomorrow events via `gog calendar`
3. **GitHub** — Org events + notifications via `gh` CLI
4. **Client Pipeline** — MRR, health scores, next actions from clients.json
5. **System Health** — Disk, Docker, Alba agent, Tailscale, LaunchAgents status
6. **Google Drive** — Recent files in shared OI folder

## Usage
```bash
# Generate today's brief
bash ~/.claude/skills/morning-brief/scripts/generate-brief.sh

# Specific date
bash ~/.claude/skills/morning-brief/scripts/generate-brief.sh --date 2026-04-01

# Dry run (don't save)
bash ~/.claude/skills/morning-brief/scripts/generate-brief.sh --dry-run --stdout
```

## Output Format (French)
- Header with date
- Email summary per account (with priority indicators)
- Calendar: today + tomorrow
- Pipeline: client table with MRR
- GitHub: recent events + notifications
- System health: disk, Docker, Alba agent, Tailscale
- Alerts (auto-detected)
- Recommendations (context-aware)
- Variant sections: Monday (weekend recap), Friday (weekly summary), 1st (monthly report)

## Variants
- **Monday** — includes weekend email recap
- **Friday** — includes weekly summary
- **1st of month** — includes monthly MRR report

## Data Files
- `data/config.json` — source configuration
