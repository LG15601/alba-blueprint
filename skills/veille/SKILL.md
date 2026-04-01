---
name: veille
description: "AI/Tech intelligence gathering from YouTube, Twitter, RSS, and GitHub. Daily automated monitoring of 10 YouTube channels, 14 Twitter accounts, 6 RSS feeds. Use when asked about AI news, competitor updates, or 'veille'."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
  - WebFetch
---

# Veille — Intelligence Gathering

Automated daily intelligence from curated sources.

## Sources (from data/veille-sources.json)

### YouTube (10 channels)
Anthropic, AI Explained, Matthew Berman, Fireship, Two Minute Papers, Wes Roth, David Ondrej, Cole Medin, IndyDevDan, All About AI

### Twitter/X (14 accounts)
@AnthropicAI, @alexalbert__, @AmandaAskell, @daboross, @BarrettZoph, @kaborosBg, @OpenAI, @GoogleAI, @sama, @ylecun + 4 more

### RSS (6 feeds)
Anthropic on HN, OpenAI Blog, Google AI Blog, HN AI, The Verge AI, TechCrunch AI

## Usage
```bash
# Daily automated scan
bash ~/.claude/skills/veille/scripts/daily-veille.sh

# Deep research on specific topic
bash ~/.claude/skills/veille/scripts/deep-research.sh "claude code new features"

# GitHub repo watcher
bash ~/.claude/skills/veille/scripts/github-watcher.sh
```

## Output
Daily digest in `output/YYYY-MM-DD.md` with:
- RSS headlines (prioritized)
- New YouTube videos from tracked channels
- Twitter highlights (when API configured)
- Actionable insights flagged
