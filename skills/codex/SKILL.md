---
name: codex
description: "Codex CLI integration for PR code review and autonomous fix execution. Two modes: /codex:review runs AI-powered code review on diffs, /codex:rescue executes autonomous fixes in full-auto mode."
user-invocable: true
allowed-tools:
  - Bash
  - Read
---

# Codex — AI Code Review & Rescue

Integrates OpenAI Codex CLI for two workflows:

1. **Review** — AI-powered code review on uncommitted changes, branches, or commits
2. **Rescue** — Autonomous fix execution in full-auto mode

## Prerequisites

- `codex` CLI installed and on PATH (`npm install -g @openai/codex`)
- Valid OpenAI API key configured for codex

## Usage

### Code Review

```bash
# Review uncommitted changes (default)
bash ~/.claude/skills/codex/scripts/codex-review.sh

# Review uncommitted changes (explicit)
bash ~/.claude/skills/codex/scripts/codex-review.sh --uncommitted

# Review against a base branch
bash ~/.claude/skills/codex/scripts/codex-review.sh --base main

# Review a specific commit
bash ~/.claude/skills/codex/scripts/codex-review.sh --commit abc123

# Free-form review prompt
bash ~/.claude/skills/codex/scripts/codex-review.sh "Review for security issues"
```

### Autonomous Rescue

```bash
# Fix a failing test
bash ~/.claude/skills/codex/scripts/codex-rescue.sh "fix the failing unit test in auth.test.ts"

# Fix in a specific directory
bash ~/.claude/skills/codex/scripts/codex-rescue.sh --dir ./packages/api "fix the broken import"
```

## Slash Commands

- `/codex:review` — Run code review via Codex
- `/codex:rescue` — Run autonomous fix via Codex
