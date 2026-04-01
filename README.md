# ALBA Blueprint

> **The ultimate AI agent setup. One agent to run the company. An army of sub-agents to do the work.**

Alba is a production-grade blueprint for deploying an autonomous, self-improving AI agent on macOS that controls your entire computer, communicates across all channels, and manages your business 24/7.

Built on **Claude Code Opus 4.6** (1M context) with the best patterns stolen from every major open-source agent project in 2026.

---

## What Alba Can Do

### Production (working now)
| Capability | How | Status |
|-----------|-----|--------|
| **Run 24/7** | tmux + launchd + watchdog with auto-restart | Deployed |
| **Classify 3 mailboxes** | DPYS classifier: 13 rules, VIP tiers, sentiment detection | Deployed |
| **Morning briefings** | 6 data sources: email, calendar, GitHub, pipeline, health, Drive | Deployed |
| **Client tracker** | Health scoring (weighted formula), relance checker, reports | Deployed |
| **System monitoring** | 10-point health check: disk, Docker, Tailscale, CRON, secrets | Deployed |
| **AI/Tech intelligence** | 10 YouTube, 14 Twitter, 6 RSS feeds — daily digest | Deployed |
| **Memory security** | 33 threat patterns + invisible Unicode detection | Deployed |
| **Talk via Telegram** | Claude Code Channels plugin | Deployed |
| **Delegate to sub-agents** | 6 agent definitions (researcher, coder, reviewer...) | Deployed |
| **Self-improve every session** | Session-end self-improvement protocol | Deployed |

### Configured (ready to activate)
| Capability | How | Status |
|-----------|-----|--------|
| **Talk via Discord** | Claude Code Channels plugin | Ready |
| **Read/send emails via MCP** | Gmail MCP + Google Workspace CLI | Ready |
| **Control the Mac** | Computer Use MCP | Ready (needs permissions) |
| **Watch YouTube** | yt-dlp MCP | Ready |
| **Web search** | Brave + Context7 MCP | Ready |

### Planned (setup scripts included)
| Capability | How | Status |
|-----------|-----|--------|
| **Talk via WhatsApp** | whatsapp-mcp bridge | Setup script included |
| **Control a phone** | Mobile MCP (Android/iOS) | MCP config only |
| **Speak and listen** | ElevenLabs + VoiceMode (Whisper) | Setup script included |
| **Post on Twitter/X** | X MCP | Setup script included |
| **Simulate decisions** | MiroFish-Offline | Setup script included |

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
    │Use      │ │Swarm    │ │Engine  │  │(9 servers) │ │(Cron)     │
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
├── BLUEPRINT.md              # Complete 23-section technical blueprint
├── TEAM-PROTOCOL.md          # SWE-AF + GSD team coordination spec
├── ARCHITECTURE.md           # Design decisions and rationale
├── config/                   # Settings, CLAUDE.md, MCP config, env template
├── agents/                   # 6 sub-agent definitions (researcher, coder, reviewer...)
├── skills/
│   ├── inbox-zero/           # PRODUCTION: DPYS email classifier (1100+ LOC)
│   ├── morning-brief/        # PRODUCTION: 6-source daily briefing (700 LOC)
│   ├── client-manager/       # PRODUCTION: CRM health scoring + relances
│   ├── veille/               # PRODUCTION: AI/tech intelligence (YouTube, Twitter, RSS)
│   ├── health-check/         # PRODUCTION: 10-point system monitor
│   ├── apex/                 # Feature implementation workflow
│   ├── daily-briefing/       # Claude-native briefing skill
│   ├── nightly-routine/      # Nightly maintenance automation
│   ├── self-improve/         # Self-improvement protocol
│   ├── simulate/             # MiroFish strategic simulation
│   └── tool-discover/        # Auto tool registry updates
├── rules/                    # 5 modular rules (.claude/rules/)
├── hooks/                    # 5 session hooks (self-improvement, security)
├── scripts/                  # Launcher, heartbeat, sync, cleanup
│   └── security/             # memory_guard.py (33 threat patterns)
├── data/                     # Real client data, pipeline, veille sources
├── launchd/                  # macOS auto-start config
├── memory/                   # Memory templates and index
├── company/                  # Org chart, teams, goals (Paperclip pattern)
├── mcp-servers/              # 4 MCP server setup scripts
└── docs/                     # Sources, autoresearch program
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

| Source | Key Contribution |
|--------|-----------------|
| [hermes-agent](https://github.com/nousresearch/hermes-agent) | Self-improvement, memory management, bounded delegation |
| [openclaw](https://github.com/openclaw/openclaw) | Boot sequence, pattern promotion, 5-layer scheduling |
| [gstack](https://github.com/garrytan/gstack) | Skill templates, learning system, builder philosophy |
| [claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) | CLAUDE.md structure, settings, hooks, memory scopes |
| [claw-code](https://github.com/instructkr/claw-code) | 207 commands, 44 feature flags, KAIROS daemon |
| [gsd-2](https://github.com/gsd-build/gsd-2) | Milestone/slice/task methodology, auto mode |
| [claude-mem](https://github.com/thedotmack/claude-mem) | FTS5 search, progressive disclosure, auto-capture |
| [middleman](https://github.com/SawyerHood/middleman) | Manager-worker pattern, swarmd runtime |
| [agency-agents](https://github.com/msitarzewski/agency-agents) | 147 agents, NEXUS pipeline, handoff templates |
| [awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills) | 5,211 skills, identity, orchestration patterns |
| [paperclip](https://github.com/paperclipai/paperclip) | Company orchestration, budgets, heartbeats |
| [companies](https://github.com/paperclipai/companies) | 16 org templates, AGENTS.md format |
| [autoresearch](https://github.com/karpathy/autoresearch) | Autonomous research, program.md, multi-agent hub |
| [MiroFish-Offline](https://github.com/nikmcfly/MiroFish-Offline) | Social simulation for strategic decisions |

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

*Research: 12 parallel agents by Zoe (VPS). Production code: Alba (Mac Mini). Merged into one unified repo.*
 one unified repo.*
