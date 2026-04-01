---
name: client-manager
description: "CRM health scoring, relance checker, and report generator for Orchestra Intelligence clients. Use when asked about clients, pipeline, MRR, or client health."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
---

# Client Manager

Production CRM system with health scoring, relance detection, and reporting.

## Health Score Formula
```
Health = (0.30 x Engagement) + (0.25 x Delivery) + (0.20 x Revenue) + (0.15 x Satisfaction) + (0.10 x Growth)
```

Scores checked against live email activity via `gog` CLI.

## Usage
```bash
# Score all clients
bash ~/.claude/skills/client-manager/scripts/health-score.sh

# Score specific client
bash ~/.claude/skills/client-manager/scripts/health-score.sh --client wella

# JSON output
bash ~/.claude/skills/client-manager/scripts/health-score.sh --json

# Check relances needed
bash ~/.claude/skills/client-manager/scripts/check-relances.sh

# Generate client report
bash ~/.claude/skills/client-manager/scripts/generate-report.sh
```

## Client Tiers
- Platinum (MRR >= 10K): 4h SLA, daily health check
- Gold (MRR >= 3K): 8h SLA, daily health check
- Silver (MRR >= 1K): 24h SLA, weekly health check
- Bronze: 48h SLA, bi-weekly
- Prospect: 24h SLA, on-activity

## Data
- `../../data/clients.json` — 10 real clients with contacts, MRR, project details
- `../../data/pipeline.json` — active deals

## Risk Levels
- Score >= 80: LOW risk (green)
- Score >= 50: MEDIUM risk (yellow)
- Score < 50: HIGH risk (red) — alert generated
