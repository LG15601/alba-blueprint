---
name: nightly-routine
description: "Run nightly maintenance: update tools, monitor repos, consolidate memory, check competitors, cleanup. Triggered by cron at 23:00 or manually."
user-invocable: true
allowed-tools:
  - Bash
  - WebSearch
  - WebFetch
  - Read
  - Write
  - Edit
  - Agent
  - Glob
  - Grep
---

# Nightly Routine

Run all maintenance tasks. Use sub-agents in parallel for speed.

## Phase 1: Updates (parallel sub-agents)

### Tool Updates
```bash
# Check for updates (don't auto-install major versions)
claude --version 2>/dev/null
npm outdated -g 2>/dev/null | head -20
brew outdated 2>/dev/null | head -20
```

### Repo Monitoring
Watch these repos for new releases via `gh api repos/OWNER/REPO/releases/latest`:
- anthropics/claude-code
- nousresearch/hermes-agent
- openclaw/openclaw
- garrytan/gstack
- gsd-build/gsd-2
- thedotmack/claude-mem
- SawyerHood/middleman
- karpathy/autoresearch

Log new releases to ~/.alba/logs/repo-updates.md

### Competitor Check
WebSearch for: "OpenClaw new features", "Hermes Agent update", "Claude Code update"
Log findings to ~/.alba/logs/competitor-intel.md

## Phase 2: Memory Consolidation

1. Review today's agent-memory entries
2. Merge duplicate or related learnings
3. Check for pattern promotion (3+ occurrences → add to .claude/rules/)
4. Prune stale entries (>30 days old, never referenced)
5. Ensure MEMORY.md index is under 200 lines

## Phase 3: Security & Cleanup

```bash
# Security checks
npm audit 2>/dev/null | tail -5
pip audit 2>/dev/null | tail -5

# Cleanup
npm cache clean --force 2>/dev/null
rm -rf /tmp/playwright* /tmp/*.log 2>/dev/null
find ~/logs -name "*.log" -mtime +7 -delete 2>/dev/null
```

## Phase 4: Report

Generate summary of all findings. Save to ~/.alba/logs/nightly/YYYY-MM-DD.md

If anything critical found (security vuln, breaking update, competitor move):
→ Send alert to Ludovic via Telegram

## Rules
- Don't auto-install major version updates — notify only
- Don't delete anything you're not sure about
- Keep nightly log under 50 lines
- Total execution should be under 10 minutes
