---
name: health-check
description: "System health monitor with 10+ checks: disk, Docker, Middleman, internet, Tailscale, CRON, secrets, memory, CPU, agent services. Use when asked about system status, health, or 'how's the machine'."
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# Health Check — System Monitor

Production-grade 10-point health check with JSON output and Telegram alerting.

## Checks
1. **Disk Space** — free GB, used %, thresholds at 20GB/10GB
2. **Docker** — container count, unhealthy containers
3. **Middleman** — process running check
4. **Internet** — Anthropic API + Google reachability
5. **Tailscale** — connection status, peer count
6. **LaunchAgents** — registered agents, failed agents
7. **CRON Freshness** — stale task detection
8. **Secret Permissions** — chmod 600 verification on sensitive files
9. **Memory/CPU** — memory pressure, load average
10. **Agent World Services** — active agents, log activity

## Usage
```bash
# Human-readable output
bash ~/.claude/skills/health-check/scripts/health-check.sh

# JSON output (for piping/monitoring)
bash ~/.claude/skills/health-check/scripts/health-check.sh --json

# Quiet mode (just status word)
bash ~/.claude/skills/health-check/scripts/health-check.sh --quiet
```

## Alert System
- Critical findings → writes alert JSON to alerts/ directory
- Alert includes chat_id for Telegram forwarding
- Overall status: healthy / warning / critical
