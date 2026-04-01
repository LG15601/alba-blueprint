# ALBA Blueprint

> **The ultimate AI agent setup. One agent to run the company. An army of sub-agents to do the work.**

Alba is a production-grade blueprint for deploying an autonomous, self-improving AI agent on macOS that controls your entire computer, communicates across all channels, and manages your business 24/7.

Built on **Claude Code Opus 4.6** (1M context) with the best patterns stolen from every major open-source agent project in 2026.

---

## What Alba Can Do

| Capability | How |
|-----------|-----|
| **Run 24/7** | tmux + launchd + watchdog with auto-restart |
| **Talk via Telegram, Slack, Discord, iMessage** | Claude Code Channels |
| **Talk via WhatsApp** | whatsapp-mcp bridge |
| **Control the entire Mac** | Computer Use MCP (screen, keyboard, mouse) |
| **Control a phone** | Mobile MCP (Android ADB / iOS Simulator) |
| **Speak and listen** | ElevenLabs TTS + VoiceMode (Whisper STT) |
| **Read and send emails** | Google Workspace CLI + Gmail MCP |
| **Post and monitor Twitter** | X MCP |
| **Watch YouTube videos** | yt-dlp MCP + Whisper transcription |
| **Manage calendar** | Google Calendar MCP |
| **Delegate to sub-agents** | Parallel Agent tool (10+ simultaneous) |
| **Self-improve every session** | Hermes-style eval loops + OpenClaw pattern promotion |
| **Run nightly maintenance** | Cron jobs: update tools, monitor repos, consolidate memory |
| **Simulate decisions** | MiroFish-Offline (100+ AI personas react to your announcement) |
| **Organize as a company** | Paperclip-style org chart with departments |
| **Share memory with other agents** | Bidirectional rsync with VPS |
| **Know every tool it has** | Auto-updated tool registry |
| **Create skills on the fly** | Auto-generates skills from successful complex tasks |

---

## Architecture

```
                                    ┌─────────────────┐
                                    │   You (Phone/    │
                                    │   Laptop/Web)    │
                                    └────────┬────────┘
                                             │
                     Telegram / Slack / WhatsApp / iMessage / Remote Control
                                             │
                    ┌────────────────────────┼──────────────────────┐
                    │                        │                      │
              ┌─────▼──────┐          ┌──────▼──────┐       ┌──────▼──────┐
              │   ALBA      │          │  Backup VPS │       │  Web UI     │
              │  Mac Mini   │◄─sync──►│  (optional)  │       │  claude.ai  │
              │  M4 16GB    │          │             │       │  /code      │
              └──────┬──────┘          └─────────────┘       └─────────────┘
                     │
         ┌───────────┼───────────┬──────────────┬──────────────┐
         │           │           │              │              │
    ┌────▼────┐ ┌────▼────┐ ┌───▼────┐  ┌──────▼─────┐ ┌─────▼──────┐
    │Computer │ │Sub-Agent│ │Skills  │  │MCP Servers │ │Scheduler  │
    │Use      │ │Swarm    │ │Engine  │  │(20+ tools) │ │(Cron)     │
    └─────────┘ └─────────┘ └────────┘  └────────────┘ └───────────┘
```

---

## Quick Start

```bash
# Clone
git clone https://github.com/orchestra-intelligence/alba-blueprint.git
cd alba-blueprint

# Install
chmod +x install.sh && ./install.sh

# Configure
cp config/.env.example ~/.alba/.env
# Edit ~/.alba/.env with your API keys

# Authenticate
claude login
gws auth login

# Grant macOS permissions
# System Settings → Privacy & Security → Screen Recording + Accessibility

# Launch
~/bin/start-alba.sh
```

---

## What's Inside

```
alba-blueprint/
├── BLUEPRINT.md          # Complete 23-section technical blueprint
├── config/               # Settings, CLAUDE.md, MCP config, env template
├── agents/               # Sub-agent definitions (researcher, coder, reviewer...)
├── skills/               # Custom skills (daily briefing, nightly routine, apex...)
├── rules/                # Modular rules (.claude/rules/)
├── hooks/                # Session hooks (self-improvement, security guards)
├── scripts/              # Launcher, heartbeat, sync, cleanup
├── launchd/              # macOS auto-start config
├── memory/               # Memory templates and index
├── company/              # Org chart, teams, goals (Paperclip pattern)
├── mcp-servers/          # MCP server setup scripts
└── docs/                 # Setup guide, troubleshooting, patterns
```

---

## Design Principles

1. **Delegation as default** — Alba delegates, sub-agents execute (Middleman pattern)
2. **Never stop, never ask** — Autonomous tasks run until done (Karpathy pattern)
3. **Self-improvement loop** — Evaluate every 15 tool calls (Hermes pattern)
4. **Pattern promotion** — 3+ lesson occurrences auto-promote to rules (OpenClaw pattern)
5. **Evidence over claims** — All quality gates require proof (Agency NEXUS pattern)
6. **Military organization** — Deterministic boot, formal handoffs, quality gates
7. **Memory is sacred** — Capture everything, compress intelligently, forget nothing
8. **Minimal viable complexity** — Simple first, complexity only when earned

---

## Research Sources

This blueprint was built by analyzing 14 repositories, 6+ articles, 2 videos, and the Claude Code source leak with 12 parallel research agents:

| Source | Stars | Key Contribution |
|--------|-------|-----------------|
| [hermes-agent](https://github.com/nousresearch/hermes-agent) | 20.8K | Self-improvement, memory management, bounded delegation |
| [openclaw](https://github.com/openclaw/openclaw) | 250K+ | Boot sequence, pattern promotion, 5-layer scheduling |
| [gstack](https://github.com/garrytan/gstack) | 59K | Skill templates, learning system, builder philosophy |
| [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) | Trending | CLAUDE.md structure, settings, hooks, memory scopes |
| [claw-code](https://github.com/instructkr/claw-code) | 50K | 207 commands, 44 feature flags, KAIROS daemon |
| [gsd-2](https://github.com/gsd-build/gsd-2) | -- | Milestone/slice/task methodology, auto mode |
| [claude-mem](https://github.com/thedotmack/claude-mem) | 44K | FTS5 search, progressive disclosure, auto-capture |
| [middleman](https://github.com/SawyerHood/middleman) | 153 | Manager-worker pattern, swarmd runtime |
| [agency-agents](https://github.com/msitarzewski/agency-agents) | -- | 147 agents, NEXUS pipeline, handoff templates |
| [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills) | -- | 5,211 skills, identity, orchestration patterns |
| [paperclip](https://github.com/paperclipai/paperclip) | 43K | Company orchestration, budgets, heartbeats |
| [companies](https://github.com/paperclipai/companies) | 229 | 16 org templates, AGENTS.md format |
| [autoresearch](https://github.com/karpathy/autoresearch) | 63K | Autonomous research, program.md, multi-agent hub |
| [MiroFish-Offline](https://github.com/nikmcfly/MiroFish-Offline) | 1.6K | Social simulation for strategic decisions |

---

## Requirements

- **Hardware:** Mac with Apple Silicon (M1+), 16GB+ RAM
- **OS:** macOS 13.0+ (Ventura or later)
- **Account:** Anthropic Pro ($20/mo) or Max ($100-200/mo)
- **Tools:** Node.js 22+, Homebrew, Claude Code CLI

---

## License

MIT -- Orchestra Intelligence, 2026

---

*Built with 12 parallel research agents by Zoe (Claude Opus 4.6, 1M context) for Orchestra Intelligence.*
