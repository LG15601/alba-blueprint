# Architecture Decisions

This document explains the **why** behind key design choices.

## Why Claude Code CLI (not Claude Desktop or API directly)?

Claude Code CLI is the only option that supports:
- Channels (Telegram, Slack, Discord, iMessage)
- Computer Use MCP
- Skills system
- Hooks system
- Scheduled tasks / Cron
- Sub-agent orchestration
- Git worktree isolation
- `--dangerously-skip-permissions` for full autonomy

Claude Desktop lacks CLI scriptability. Raw API lacks the tool harness.

## Why tmux + launchd (not Docker)?

- Computer Use requires native macOS screen access — impossible inside Docker
- Mobile MCP needs USB/ADB access — complex in containers
- Voice mode needs audio devices — not available in containers
- launchd is macOS-native and survives reboots
- tmux provides interactive access when needed (attach to debug)

## Why File-Based Memory (not a database)?

- Claude Code's built-in memory system uses flat markdown files
- MEMORY.md index is loaded automatically every session
- No external dependencies to manage
- Human-readable and git-trackable
- claude-mem (SQLite+FTS5) supplements for search — not replaces

## Why Delegation-First (not single-agent)?

Learned from every major agent project:
- **Middleman**: Manager delegates, workers execute in worktrees
- **Hermes**: Bounded delegation with iteration budgets prevents runaway
- **Agency NEXUS**: Quality gates between phases catch errors early
- **Karpathy**: Single-file constraint per agent prevents scope creep
- A single agent running everything hits context limits and loses coherence

## Why Self-Improvement Loops?

- **Hermes** showed eval every 15 calls catches drift early
- **OpenClaw** showed pattern promotion (3+ → rule) compounds knowledge
- Without loops, agents make the same mistakes across sessions
- The nightly consolidation prevents memory bloat while preserving lessons

## Why Multi-Channel (not Telegram-only)?

- Telegram for Ludovic (personal, fast, mobile)
- Slack for team/client communication
- WhatsApp for clients who use it (French market)
- iMessage for Apple-native contacts
- Discord for community management
- Each channel has different audiences and response norms

## Why MiroFish for Decisions?

- Simulates 100+ personas reacting to announcements
- Catches PR crises before they happen
- Tests messaging before spending on campaigns
- Runs fully offline on Mac M4 (no cloud, no data leak)
- $0 operational cost after setup

## Why Paperclip-Style Org (not flat agents)?

- Goal hierarchy ensures every task traces to company mission
- Budget enforcement prevents runaway costs
- Org chart enables clear delegation chains
- Heartbeat model ensures agents don't go silent
- Company templates enable rapid setup for new clients
