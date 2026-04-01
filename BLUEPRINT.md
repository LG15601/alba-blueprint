# ALBA — The Ultimate AI Agent Blueprint

> **One agent to run the company. An army of sub-agents to do the work.**
> Built on Claude Code + macOS Computer Use + Multi-Channel + Self-Improvement

---

## Table of Contents

1. [Vision](#1-vision)
2. [Architecture Overview](#2-architecture-overview)
3. [Hardware & Prerequisites](#3-hardware--prerequisites)
4. [Core Agent Setup](#4-core-agent-setup)
5. [Identity & Memory System](#5-identity--memory-system)
6. [Channels — Telegram, Slack, WhatsApp, iMessage, Discord](#6-channels)
7. [Computer Use & Phone Control](#7-computer-use--phone-control)
8. [Voice — Speak & Listen](#8-voice--speak--listen)
9. [Integrations — Gmail, Twitter, YouTube, Calendar, Google Workspace](#9-integrations)
10. [Multi-Agent Architecture](#10-multi-agent-architecture)
11. [Skills System](#11-skills-system)
12. [Self-Improvement Engine](#12-self-improvement-engine)
13. [Scheduling & Automation](#13-scheduling--automation)
14. [Strategic Decision Engine (MiroFish)](#14-strategic-decision-engine)
15. [Company Organization (Paperclip Pattern)](#15-company-organization)
16. [Security & Monitoring](#16-security--monitoring)
17. [Daily & Nightly Routines](#17-daily--nightly-routines)
18. [Tool Registry — Know Thy Arsenal](#18-tool-registry)
19. [Memory Transfer from Zoe](#19-memory-transfer-from-zoe)
20. [Repo Structure](#20-repo-structure)
21. [Installation — Step by Step](#21-installation)
22. [Auto-Update & Self-Evolution](#22-auto-update--self-evolution)
23. [Sources & Credits](#23-sources--credits)

---

## 1. Vision

Alba is not just an AI assistant. Alba is the **operating system of Orchestra Intelligence** — a persistent, autonomous, self-improving AI agent that:

- **Runs 24/7** on a Mac Mini M4, always reachable via Telegram, Slack, WhatsApp, and iMessage
- **Controls the entire Mac** via Computer Use (screen, keyboard, mouse, any app)
- **Controls a phone** via Mobile MCP (Android emulator or real device)
- **Speaks and listens** via ElevenLabs TTS + Whisper STT
- **Reads and sends emails** via Google Workspace CLI + Gmail MCP
- **Posts and monitors Twitter/X** via X MCP
- **Watches YouTube** via yt-dlp + Whisper transcription
- **Manages the calendar** via Google Calendar MCP
- **Delegates to sub-agents** for parallel execution (up to 10+ simultaneous)
- **Self-improves** every session — learns from mistakes, promotes patterns, creates skills
- **Schedules nightly routines** — monitor repos, update tools, check competitors, consolidate memory
- **Simulates public reaction** via MiroFish before strategic decisions
- **Organizes as a company** — CEO agent with departments (engineering, marketing, sales, support)
- **Shares memory** bidirectionally with Zoe (VPS agent) via rsync
- **Knows every tool it has** — maintains a live registry of all CLIs, MCPs, and capabilities
- **Is better than OpenClaw and Hermes Agent** — combines the best patterns from both with Claude Code's native intelligence

### Design Principles

1. **Delegation as default** — Alba delegates, it doesn't do everything itself (Middleman pattern)
2. **Never stop, never ask** — For autonomous tasks, run until done (Karpathy pattern)
3. **Self-improvement loop** — Every 15 tool calls, evaluate performance (Hermes pattern)
4. **Pattern promotion** — 3+ occurrences of a lesson → promote to system prompt (OpenClaw pattern)
5. **Evidence over claims** — All quality assessments need proof (Agency NEXUS pattern)
6. **Military organization** — Deterministic boot sequence, formal handoffs, quality gates
7. **Memory is sacred** — Capture everything, forget nothing, compress intelligently
8. **Minimal viable complexity** — Simple solutions first, complexity only when earned

---

## 2. Architecture Overview

```
                                    ┌─────────────────┐
                                    │   Ludovic's      │
                                    │   Devices        │
                                    │  (Phone/Laptop)  │
                                    └────────┬────────┘
                                             │
                        Telegram / Slack / WhatsApp / iMessage / Remote Control
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
              ┌─────▼─────┐           ┌──────▼──────┐         ┌──────▼──────┐
              │  ALBA      │           │  ZOE (VPS)  │         │  Web UI     │
              │  Mac Mini  │◄─rsync──►│  Hetzner    │         │  claude.ai  │
              │  M4 16GB   │  memory   │  22GB RAM   │         │  /code      │
              └─────┬──────┘           └─────────────┘         └─────────────┘
                    │
        ┌───────────┼───────────┬──────────────┬──────────────┐
        │           │           │              │              │
   ┌────▼────┐ ┌────▼────┐ ┌───▼────┐  ┌──────▼─────┐ ┌─────▼──────┐
   │Computer │ │Sub-Agent│ │Skills  │  │MCP Servers │ │Cron/Loop  │
   │Use      │ │Swarm    │ │Engine  │  │(9 servers) │ │Scheduler  │
   │(Screen) │ │(10+)    │ │(50+)   │  │            │ │           │
   └─────────┘ └─────────┘ └────────┘  └────────────┘ └───────────┘
```

### Key Components

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Brain** | Claude Code (1M context) | Reasoning, planning, delegation |
| **Runtime** | Claude Code CLI v2.1.89+ | Tool execution, hooks, skills, channels |
| **Persistence** | tmux + launchd + watchdog | 24/7 uptime with auto-restart |
| **Memory** | File-based (MEMORY.md) + claude-mem (SQLite+FTS5) | Cross-session knowledge |
| **Channels** | Telegram, Slack, Discord, iMessage plugins | Multi-platform messaging |
| **Computer Use** | computer-use-mcp + macos-automator-mcp | Full Mac control |
| **Phone** | Mobile MCP (mobile-next) | Android/iOS control |
| **Voice** | ElevenLabs MCP + VoiceMode MCP | TTS + STT |
| **Email** | Google Workspace CLI + Gmail MCP | Read/draft/search email |
| **Twitter** | X MCP (Infatoshi/x-mcp) | Post, search, monitor |
| **YouTube** | yt-dlp MCP + Whisper | Watch, transcribe, analyze |
| **Calendar** | Google Calendar MCP | Schedule, check, manage |
| **Search** | Exa + Brave + Context7 | Web search + docs |
| **Simulation** | MiroFish-Offline (MLX) | Strategic decision testing |
| **Org** | Paperclip patterns | Company structure + budgets |
| **Methodology** | GSD 2.52+ | Phase planning + execution |
| **Browser** | gstack browse (Playwright) | QA, scraping, screenshots |

---

## 3. Hardware & Prerequisites

### Mac Mini M4 (Already Available)

- **CPU:** Apple M4 (10-core)
- **RAM:** 16 GB unified memory
- **Storage:** 256GB+ SSD
- **OS:** macOS 26.2 Tahoe
- **User:** `alba`
- **Display:** Samsung C27F390 (1080p) — needed for Computer Use
- **Network:** Tailscale VPN (connected to VPS + Ludovic's devices)

### Required Accounts & API Keys

| Service | Purpose | Cost | Priority |
|---------|---------|------|----------|
| Anthropic (claude.ai) | Main brain — Max plan | $100-200/mo | CRITICAL |
| Google Workspace | Gmail, Calendar, Drive, Sheets | Free (personal) | HIGH |
| X/Twitter Developer | Post, read, monitor | $200/mo (Basic) or pay-per-use | HIGH |
| ElevenLabs | Text-to-speech | $5-22/mo | MEDIUM |
| Exa | Deep web search | Free tier available | MEDIUM |
| Brave Search | Web search API | Free tier (2K/mo) | MEDIUM |
| Supabase | Database for projects | Free tier | EXISTING |
| Vercel | Deployment platform | Free-Pro | EXISTING |
| GitHub | Code hosting + Actions | Free | EXISTING |

### Required Software (Pre-install)

```bash
# Core runtime
brew install node@22 bun python@3.14 go git gh

# Claude Code
npm install -g @anthropic-ai/claude-code

# GSD
npm install -g gsd-pi@latest

# Media tools
brew install yt-dlp ffmpeg

# Search tools
brew install ripgrep fd bat fzf jq yq tree htop

# Dev tools
brew install ast-grep hyperfine watchexec delta

# Browser automation
npx playwright install chromium

# Local AI (for MiroFish)
brew install ollama

# Voice
pip install faster-whisper

# Google Workspace CLI
npm install -g @googleworkspace/cli
```

---

## 4. Core Agent Setup

### 4.1 Directory Structure

```bash
# Create the sacred directory structure
mkdir -p ~/.claude/{agents,commands,skills,rules,hooks/scripts,hooks/sounds,teams,tasks}
mkdir -p ~/.claude/agent-memory/alba
mkdir -p ~/.claude/projects
mkdir -p ~/bin
mkdir -p ~/logs
```

### 4.2 Global CLAUDE.md (~/.claude/CLAUDE.md)

```markdown
# Alba — CEO AI Agent, Orchestra Intelligence

## Identity
- Name: Alba
- Role: CEO AI Agent for Orchestra Intelligence
- Boss: Ludovic Goutel (@LG15601 on Telegram)
- Email: alba@orchestra.studio
- Style: Autonomous, proactive, military precision, never say "I can't"

## Core Behaviors
- ALWAYS delegate complex tasks to sub-agents (never do everything in main context)
- ALWAYS use Plan mode for tasks with 5+ steps
- ALWAYS verify work before marking complete
- ALWAYS update memory after learning something new
- NEVER create project files without explicit instruction from Ludovic
- NEVER stop investigating — always find a solution or workaround
- Every Telegram/Slack message MUST get a response

## Boot Sequence (deterministic)
1. Load MEMORY.md (cross-session knowledge)
2. Load agent-memory (Alba-specific learnings)
3. Check tool registry (~/.alba/tool-registry.json)
4. Check scheduled tasks (cron list)
5. Read today's standing orders (~/.alba/standing-orders.md)
6. Ready for work

## Delegation Rules
- Research tasks → Agent(subagent_type="Explore") or Agent(subagent_type="general-purpose")
- Code changes → Agent with isolation="worktree"
- Quick lookups → Direct tool use (Grep, Glob, Read)
- Multi-file analysis → Agent(subagent_type="Explore", prompt="very thorough")
- Planning → Agent(subagent_type="Plan")
- Parallel independent tasks → Multiple Agent calls in single message

## Communication
- French by default with Ludovic
- English for code, commits, documentation
- Short, direct, no fluff
- Send intermediate updates for long tasks (>2 min)
- Use react emoji on Telegram for acknowledgment

## Self-Improvement Protocol
- After every correction: save feedback memory immediately
- Every 15 tool calls: quick self-assessment (am I on track?)
- End of session: consolidate learnings, update memories
- Pattern detection: if same lesson appears 3+ times, promote to CLAUDE.md rule
```

### 4.3 Settings (~/.claude/settings.json)

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.alba/hooks/session-start.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.alba/hooks/session-stop.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash|Edit|Write|Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.alba/hooks/self-improvement-check.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.alba/hooks/destructive-command-guard.sh",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Read(**)",
      "Glob(**)",
      "Grep(**)",
      "WebSearch(**)",
      "WebFetch(**)",
      "Agent(**)",
      "Bash(git *)",
      "Bash(npm *)",
      "Bash(brew *)",
      "Bash(ls *)",
      "Bash(pwd)",
      "Bash(which *)",
      "Bash(cat *)",
      "Bash(head *)",
      "Bash(tail *)",
      "Bash(wc *)",
      "Bash(date *)",
      "Bash(echo *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Bash(gws *)",
      "Bash(yt-dlp *)",
      "Bash(ollama *)",
      "Bash(claude *)",
      "Bash(gsd *)",
      "Bash(tmux *)",
      "Bash(python3 *)",
      "Bash(node *)",
      "Bash(bun *)",
      "Bash(gh *)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(sudo rm -rf *)",
      "Bash(:(){ :|:& };:)"
    ]
  },
  "enabledPlugins": {
    "telegram@claude-plugins-official": true,
    "discord@claude-plugins-official": true,
    "claude-mem@thedotmack": true,
    "compound-engineering@compound-engineering-plugin": true
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true,
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "80"
  }
}
```

### 4.4 MCP Servers (.mcp.json — project root)

```json
{
  "mcpServers": {
    "computer-use": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic-ai/computer-use-mcp"]
    },
    "macos-automator": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@steipete/macos-automator-mcp"]
    },
    "mobile-mcp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@mobilenext/mobile-mcp@latest"]
    },
    "elevenlabs": {
      "type": "stdio",
      "command": "uvx",
      "args": ["elevenlabs-mcp"],
      "env": {
        "ELEVENLABS_API_KEY": "${ELEVENLABS_API_KEY}"
      }
    },
    "voicemode": {
      "type": "stdio",
      "command": "uvx",
      "args": ["--refresh", "voice-mode"]
    },
    "x-twitter": {
      "type": "stdio",
      "command": "node",
      "args": ["~/.alba/mcp-servers/x-mcp/dist/index.js"],
      "env": {
        "X_API_KEY": "${X_API_KEY}",
        "X_API_SECRET": "${X_API_SECRET}",
        "X_ACCESS_TOKEN": "${X_ACCESS_TOKEN}",
        "X_ACCESS_TOKEN_SECRET": "${X_ACCESS_TOKEN_SECRET}",
        "X_BEARER_TOKEN": "${X_BEARER_TOKEN}"
      }
    },
    "yt-dlp": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@kevinwatt/yt-dlp-mcp@latest"]
    },
    "whatsapp": {
      "type": "stdio",
      "command": "python3",
      "args": ["~/.alba/mcp-servers/whatsapp-mcp/src/server.py"],
      "env": {
        "WHATSAPP_BRIDGE_URL": "http://localhost:8085"
      }
    },
    "google-workspace": {
      "type": "stdio",
      "command": "gws",
      "args": ["mcp", "start"]
    },
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@context7/mcp-server"]
    },
    "brave-search": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-brave-search"],
      "env": {
        "BRAVE_API_KEY": "${BRAVE_API_KEY}"
      }
    }
  }
}
```

### 4.5 Persistent Launcher (start-alba.sh)

```bash
#!/bin/bash
# ==========================================================
# Alba — Claude Code always-on launcher with watchdog
# Adapted from Zoe's VPS launcher for macOS
# ==========================================================

SESSION="alba-agent"
CLAUDE="$(which claude)"
WATCHDOG_INTERVAL=120
LOG_TAG="alba-agent"
MAX_RAM_MB=6000
MAX_CONSECUTIVE_FAILS=3

log() { logger -t "$LOG_TAG" "$1"; echo "[$(date '+%H:%M:%S')] $1"; }

get_claude_pid() {
    pgrep -f "claude.*channels.*telegram.*slack" 2>/dev/null | head -1
}

get_ram_mb() {
    local pid="$1"
    if [ -n "$pid" ]; then
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}'
    else
        echo "0"
    fi
}

kill_orphans() {
    pkill -f "claude.*channels.*telegram" 2>/dev/null
    pkill -f "bun.*telegram" 2>/dev/null
    sleep 1
}

# --- stop ---
if [ "$1" = "stop" ]; then
    tmux kill-session -t "$SESSION" 2>/dev/null
    kill_orphans
    log "Stopped"
    exit 0
fi

# --- status ---
if [ "$1" = "status" ]; then
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        CPID=$(get_claude_pid)
        if [ -n "$CPID" ]; then
            RAM=$(get_ram_mb "$CPID")
            echo "HEALTHY — Claude PID $CPID (${RAM}MB RAM)"
        else
            echo "STARTING — tmux session exists but Claude not found yet"
        fi
    else
        echo "STOPPED — no tmux session"
    fi
    exit 0
fi

# --- start ---
tmux kill-session -t "$SESSION" 2>/dev/null
kill_orphans
sleep 1

launch_claude() {
    log "Launching Alba..."
    tmux kill-session -t "$SESSION" 2>/dev/null
    kill_orphans
    sleep 1

    # Launch with ALL channels
    tmux new-session -d -s "$SESSION" \
        "$CLAUDE --dangerously-skip-permissions \
         --channels 'plugin:telegram@claude-plugins-official' \
         --channels 'plugin:discord@claude-plugins-official'"

    sleep 6
    tmux send-keys -t "$SESSION" Enter
    sleep 15

    CPID=$(get_claude_pid)
    if [ -n "$CPID" ]; then
        log "Alba started (PID $CPID)"
    else
        log "WARNING: Claude process not found after launch"
    fi
}

is_healthy() {
    tmux has-session -t "$SESSION" 2>/dev/null || return 1
    CPID=$(get_claude_pid)
    [ -z "$CPID" ] && return 1
    RAM=$(get_ram_mb "$CPID")
    [ "$RAM" -gt "$MAX_RAM_MB" ] && { log "RAM too high (${RAM}MB)"; return 1; }
    return 0
}

launch_claude

# --- watchdog loop ---
log "Watchdog started (check every ${WATCHDOG_INTERVAL}s)"
FAIL_COUNT=0

while true; do
    sleep "$WATCHDOG_INTERVAL"
    if is_healthy; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        log "Health check failed ($FAIL_COUNT/$MAX_CONSECUTIVE_FAILS)"
        if [ "$FAIL_COUNT" -ge "$MAX_CONSECUTIVE_FAILS" ]; then
            log "Restarting Alba..."
            FAIL_COUNT=0
            launch_claude
        fi
    fi
done
```

### 4.6 launchd Auto-Start (com.alba.agent.plist)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.alba.agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/alba/bin/start-alba.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/alba/logs/alba-agent.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/alba/logs/alba-agent-error.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>/Users/alba</string>
    <key>PATH</key>
    <string>/Users/alba/.nvm/versions/node/v22.22.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>TERM</key>
    <string>xterm-256color</string>
  </dict>
</dict>
</plist>
```

Install: `cp com.alba.agent.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.alba.agent.plist`

---

## 5. Identity & Memory System

### 5.1 Four-Layer Memory Architecture

| Layer | Storage | Auto-Captured | Searchable | Cross-Session |
|-------|---------|:---:|:---:|:---:|
| **CLAUDE.md** | Flat markdown | No (manual) | No (file read) | Yes |
| **Auto-memory** | `~/.claude/projects/*/memory/` | Yes (by Claude) | No | Yes |
| **claude-mem** | SQLite + FTS5 + Chroma | Yes (every tool call) | Yes (full-text + semantic) | Yes |
| **Agent memory** | `~/.claude/agent-memory/alba/` | Yes (by agent) | No | Yes |

### 5.2 Boot Sequence (Deterministic — OpenClaw Pattern)

Every session starts the same way:

```
1. Load CLAUDE.md (identity + rules)
2. Load .claude/rules/*.md (modular rules)
3. Load MEMORY.md (memory index)
4. Load agent-memory/alba/MEMORY.md (personal learnings)
5. Load standing-orders.md (today's priorities)
6. Inject claude-mem context (recent relevant observations)
7. Check tool registry (what tools are available)
8. Check cron/scheduled tasks
9. → READY
```

### 5.3 Memory Files Structure

```
~/.claude/projects/-Users-alba/memory/
  MEMORY.md                          # Index (< 200 lines)
  user_ludovic_profile.md            # Boss preferences
  feedback_workflow_rules.md         # How to work
  feedback_communication.md          # How to communicate
  project_infrastructure.md          # VPS + Mac Mini setup
  project_clients.md                 # All client projects
  project_orchestra_intelligence.md  # Company context
  reference_cli_tools.md             # Installed tools registry
  reference_api_keys.md              # Available APIs
  reference_repos.md                 # Key GitHub repos to watch

~/.claude/agent-memory/alba/
  MEMORY.md                          # Alba-specific learnings (< 200 lines)
  patterns.md                        # Promoted patterns (3+ occurrences)
  failures.md                        # Failure registry (what went wrong + fix)
  skills-created.md                  # Skills auto-created from complex tasks
```

### 5.4 Self-Managed Memory (Hermes Pattern)

Memory has hard limits to force intelligent compression:
- **MEMORY.md index:** Max 200 lines (Claude Code limit)
- **Auto-memory files:** Max 2,200 chars for facts/conventions, 1,375 chars for user preferences
- When full: agent consolidates, merges related items, drops low-value entries
- **Intelligent forgetting:** Retain critical lessons, compress verbose details

### 5.5 Memory Sync with Zoe (VPS)

Bidirectional rsync every 30 minutes (already configured):

```bash
# Cron job on VPS (already active)
*/30 * * * * /home/clawdbot/sync-memory-to-mac.sh

# Script syncs:
# VPS → Mac (authoritative for shared memories)
# Mac → VPS (new files only, --ignore-existing)
```

---

## 6. Channels

### 6.1 Telegram (Primary — already working on VPS)

```bash
claude --dangerously-skip-permissions \
  --channels 'plugin:telegram@claude-plugins-official'
```

- Full filesystem + MCP + git access from Telegram messages
- Reply with text, files, images
- React with emoji for acknowledgment

### 6.2 Slack (New — for team/client communication)

```bash
# Add Slack channel alongside Telegram
claude --dangerously-skip-permissions \
  --channels 'plugin:telegram@claude-plugins-official' \
  --channels 'plugin:slack@claude-plugins-official'
```

- Connect to Orchestra Intelligence Slack workspace
- Monitor client channels
- Auto-respond to mentions
- Post status updates

### 6.3 WhatsApp (Via MCP Bridge)

**Setup using lharries/whatsapp-mcp:**

```bash
# Install the bridge
cd ~/.alba/mcp-servers
git clone https://github.com/lharries/whatsapp-mcp.git
cd whatsapp-mcp
go build -o whatsapp-bridge

# Start bridge (scan QR code ONCE with phone)
./whatsapp-bridge

# Add to .mcp.json (see section 4.4)
```

**WARNING:** Violates WhatsApp TOS. Use a secondary number. Keep message volumes human-like. Add random delays between messages.

### 6.4 iMessage (Native macOS)

```bash
# Available via Claude Code channels
claude --channels 'plugin:imessage@claude-plugins-official'
```

- macOS native — no bridge needed
- Requires Messages.app access permissions

### 6.5 Discord (Already configured)

```bash
claude --channels 'plugin:discord@claude-plugins-official'
```

### 6.6 Multi-Channel Launch Command

```bash
# The full multi-channel command for start-alba.sh
claude --dangerously-skip-permissions \
  --channels 'plugin:telegram@claude-plugins-official' \
  --channels 'plugin:discord@claude-plugins-official'
# Add more channels as they become stable
```

---

## 7. Computer Use & Phone Control

### 7.1 Computer Use (Full Mac Control)

**Prerequisites:**
1. macOS 13.0+ (Ventura or later) — we have Tahoe 26.2
2. System Settings → Privacy & Security → Screen Recording → enable Terminal.app
3. System Settings → Privacy & Security → Accessibility → enable Terminal.app
4. Pro or Max Anthropic plan

**Enable:**
```bash
# In Claude Code session:
/mcp
# → Turn on "computer-use" server
```

**What Alba can do with Computer Use:**
- Open any app (Finder, Safari, Mail, Slack, etc.)
- Click, type, scroll, drag anywhere on screen
- Take screenshots and analyze them
- Fill forms, navigate websites
- Control apps that have no CLI or API
- Design review by looking at actual rendered pages

**MCP Servers for enhanced control:**
- `computer-use-mcp` — Anthropic's official screen control
- `@steipete/macos-automator-mcp` — AppleScript/JXA automation (faster for known actions)

### 7.2 Phone Control

**Option A: Android Emulator on Mac (Recommended)**

```bash
# Install Android emulator
brew install --cask android-studio
# Create AVD (Android Virtual Device)
# Alba controls it via Computer Use (sees the emulator window)

# OR use Mobile MCP for programmatic control
claude mcp add mobile-mcp -- npx -y @mobilenext/mobile-mcp@latest
```

**Option B: Real Android via ADB**

```bash
# Connect Android phone via USB or WiFi ADB
adb connect <phone-ip>:5555

# Alba can then:
# - Tap: adb shell input tap X Y
# - Type: adb shell input text "hello"
# - Screenshot: adb shell screencap /sdcard/screen.png
# - Install apps, navigate, etc.
```

**Option C: iPhone via Simulator**

```bash
# Requires Xcode installed
xcrun simctl boot "iPhone 16"
# Mobile MCP supports iOS Simulator natively
```

---

## 8. Voice — Speak & Listen

### 8.1 Text-to-Speech (ElevenLabs)

```bash
# Install ElevenLabs MCP
claude mcp add elevenlabs -- uvx elevenlabs-mcp
# Set ELEVENLABS_API_KEY in environment

# Alba can now:
# - Speak responses aloud
# - Clone voices
# - Generate audio files
# - Use conversational AI mode
```

**Recommended voice:** Choose a professional French voice for Ludovic interactions.

### 8.2 Speech-to-Text (VoiceMode — Local)

```bash
# Install VoiceMode (supports local Whisper)
curl -LsSf https://astral.sh/uv/install.sh | sh
uvx voice-mode-install

# Install local engines (no cloud dependency)
voicemode whisper install    # Local STT (faster-whisper)
voicemode kokoro install     # Local TTS (backup)
voicemode whisper start && voicemode kokoro start

# Add to Claude Code
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

**Result:** 2-way voice — speak to Alba, Alba speaks back. Fully local, no cloud latency.

### 8.3 Push-to-Talk Mode

```bash
# Alternative: claude-whisper for keyboard-triggered voice
pip install claude-whisper
# Hold ESC → speak → release → transcribed + executed
```

---

## 9. Integrations

### 9.1 Gmail & Google Workspace

**Already available via MCP:** Gmail search, read, draft, labels, profile.

**Enhanced with Google Workspace CLI:**

```bash
npm install -g @googleworkspace/cli
gws auth login  # Opens browser for OAuth

# Alba can now:
gws gmail messages list --query "is:unread"
gws calendar events list --max-results 10
gws drive files list --query "name contains 'rapport'"
gws sheets values get SPREADSHEET_ID 'Sheet1!A1:D10'

# Also works as MCP server:
# gws mcp start (in .mcp.json config)
```

### 9.2 Twitter/X

**Setup X MCP:**

```bash
cd ~/.alba/mcp-servers
git clone https://github.com/Infatoshi/x-mcp.git
cd x-mcp && npm install && npm run build

# Set 5 env vars in .env:
# X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET, X_BEARER_TOKEN
```

**Capabilities:** Post tweets, search, like, retweet, bookmark, read timelines, monitor mentions.

**Cost:** Basic tier $200/mo for read+write, or pay-per-use tier.

### 9.3 YouTube

**Setup yt-dlp MCP:**

```bash
claude mcp add yt-dlp -- npx -y @kevinwatt/yt-dlp-mcp@latest

# Alba can now:
# - Download videos
# - Extract transcripts (auto-generated or manual subtitles)
# - Get metadata (title, description, duration, views)
# - Transcribe audio locally with Whisper
```

**Pipeline for video analysis:**
1. `yt-dlp --write-auto-sub --sub-lang fr,en --skip-download URL` → get subtitles
2. If no subs: `yt-dlp --extract-audio --audio-format wav URL` → `whisper audio.wav`
3. Feed transcript to Claude for analysis

### 9.4 Google Calendar

Already available via Google Calendar MCP. After authentication:
- View upcoming events
- Create/modify events
- Set reminders
- Check availability

### 9.5 Slack Integration

Already available via Slack MCP tools:
- Read channels, threads, user profiles
- Send messages, schedule messages
- Create/read/update canvases
- Search public and private channels

### 9.6 Notion, Canva, Supabase, Vercel

All already connected via MCP servers (see deferred tools list).

---

## 10. Multi-Agent Architecture

### 10.1 Delegation Philosophy (Middleman Pattern)

> "You're not an IC anymore. You're a project manager."

Alba ALWAYS delegates substantive work to sub-agents. Direct execution only for:
- Trivial tasks (< 30 seconds)
- Tasks requiring main context (memory updates, user communication)
- Single-tool operations (read a file, search for a term)

Everything else → sub-agent.

### 10.2 Built-in Agent Types

| Type | Model | Purpose | When to Use |
|------|-------|---------|-------------|
| `general-purpose` | Opus | Complex multi-step tasks | Feature implementation, debugging |
| `Explore` | Haiku | Fast codebase search | "Find where X is defined" |
| `Plan` | Opus | Design implementation plans | Before any 5+ step task |
| `statusline-setup` | Sonnet | Configure status line | One-time setup |
| `claude-code-guide` | Haiku | Answer Claude Code questions | "How do I use hooks?" |

### 10.3 Custom Agent Definitions

Create in `~/.claude/agents/`:

**researcher.md:**
```yaml
---
name: researcher
description: Deep web and codebase researcher. Use PROACTIVELY for any question requiring external knowledge.
model: sonnet
tools:
  - WebSearch
  - WebFetch
  - Read
  - Glob
  - Grep
  - Agent
maxTurns: 30
memory: user
---
Deep research agent. Search extensively, cross-reference sources, verify claims.
Report findings in structured format with sources.
```

**coder.md:**
```yaml
---
name: coder
description: Implementation agent. Use for writing code, fixing bugs, refactoring.
model: sonnet
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
isolation: worktree
maxTurns: 50
memory: project
---
Write clean, tested code. Follow project conventions. Commit atomically.
Run tests before declaring done. Never skip verification.
```

**reviewer.md:**
```yaml
---
name: reviewer
description: Code review agent. Use after any significant code change.
model: opus
tools:
  - Read
  - Glob
  - Grep
  - Bash
maxTurns: 20
---
Review code for: security vulnerabilities, performance issues, anti-patterns,
missing error handling, test coverage gaps. Be brutally honest.
```

**monitor.md:**
```yaml
---
name: monitor
description: Background monitoring agent. Use for watching repos, services, competitors.
model: haiku
tools:
  - WebSearch
  - WebFetch
  - Read
  - Bash
background: true
maxTurns: 15
memory: user
---
Monitor specified targets. Report only significant changes or anomalies.
Be concise. Save findings to memory for trend analysis.
```

### 10.4 Parallel Execution Pattern

```
# Launch multiple agents simultaneously
Agent(description="Research X", prompt="...", run_in_background=true)
Agent(description="Research Y", prompt="...", run_in_background=true)
Agent(description="Research Z", prompt="...", run_in_background=true)

# All run in parallel, results arrive as notifications
# Synthesize results in main context
```

### 10.5 Agent Teams (Experimental)

```bash
# Enable agent teams
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# One lead coordinates, teammates share task list
# Teammates communicate directly (not just through lead)
```

### 10.6 NEXUS-Inspired Quality Gates (Agency Pattern)

Every significant task goes through gates:

1. **Research Gate:** Do we understand the problem? (Explore agent)
2. **Plan Gate:** Is the approach sound? (Plan agent)
3. **Build Gate:** Does the code work? (Coder agent + tests)
4. **Review Gate:** Is it safe and clean? (Reviewer agent)
5. **Verify Gate:** Does it actually solve the original problem? (Verification)

Max 3 retries per gate before escalation to Ludovic.

---

## 11. Skills System

### 11.1 Skill Structure

```
~/.claude/skills/
  skill-name/
    SKILL.md          # Skill definition (YAML frontmatter + instructions)
    references/       # Reference docs for progressive disclosure
    scripts/          # Helper scripts
    examples/         # Example inputs/outputs
```

### 11.2 Essential Skills to Create

**daily-briefing/SKILL.md:**
```yaml
---
name: daily-briefing
description: "Generate morning briefing. Use when Ludovic says 'bonjour', 'good morning', or asks for today's summary."
user-invocable: true
allowed-tools:
  - WebSearch
  - WebFetch
  - Read
  - Bash
  - Agent
---
# Daily Briefing

Generate a comprehensive morning briefing:

1. **Calendar** — Today's events and meetings (Google Calendar MCP)
2. **Email** — Unread important emails (Gmail MCP)
3. **Tasks** — Open tasks and deadlines across projects
4. **Repos** — Overnight commits on watched repos (gh CLI)
5. **Twitter** — Mentions and relevant AI news (X MCP)
6. **Slack** — Unread important messages
7. **Weather** — Local weather (WebSearch)
8. **AI News** — Top 3 AI developments (WebSearch + Exa)

Format: concise, French, bullet points, with priority flags.
```

**nightly-routine/SKILL.md:**
```yaml
---
name: nightly-routine
description: "Run nightly maintenance. Auto-triggered by cron at 23:00."
user-invocable: true
allowed-tools:
  - Bash
  - WebSearch
  - WebFetch
  - Read
  - Write
  - Agent
---
# Nightly Routine

1. **Update tools** — Check for updates to Claude Code, GSD, key npm packages
2. **Monitor repos** — Check starred repos for new releases/features
3. **Consolidate memory** — Merge daily learnings, prune duplicates
4. **Check competitors** — OpenClaw releases, Hermes updates, new agent tools
5. **Security scan** — Check for known vulnerabilities in installed packages
6. **Clean up** — Remove temp files, old logs, npm cache
7. **Report** — Generate summary of changes/findings → save to daily log
```

**apex-workflow/SKILL.md (Inspired by Melvynx):**
```yaml
---
name: apex
description: "10-step autonomous workflow for feature implementation. Use when asked to build a feature end-to-end."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
---
# Apex Workflow

1. **Init** — Create feature branch
2. **Analyze** — Understand requirements and codebase context
3. **Plan** — Design implementation approach
4. **Execute** — Write the code (delegate to coder sub-agent)
5. **Validate** — Run linter + type checker
6. **Review** — Self-review for quality (delegate to reviewer sub-agent)
7. **Fix** — Address review findings
8. **Test** — Run test suite
9. **Verify** — Manual verification against requirements
10. **PR** — Create pull request with full description
```

**strategic-simulation/SKILL.md:**
```yaml
---
name: simulate
description: "Run MiroFish social simulation for strategic decisions. Use when evaluating PR, product launch, policy change impact."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
---
# Strategic Simulation (MiroFish)

1. Prepare the document/announcement to test
2. Start MiroFish-Offline (Docker or native)
3. Upload document to localhost:3000
4. Build knowledge graph
5. Generate 100+ agent personas
6. Run simulation (social media reaction)
7. Generate report
8. Analyze sentiment evolution and key risk areas
9. Present findings with recommendations
```

**self-improve/SKILL.md:**
```yaml
---
name: self-improve
description: "End-of-session self-improvement. Triggered by Stop hook."
disable-model-invocation: true
user-invocable: false
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---
# Self-Improvement Protocol

1. Review this session's actions and outcomes
2. Identify: What worked well? What failed? What was surprising?
3. Check for recurring patterns (3+ occurrences → promote to rule)
4. Update agent memory with new learnings
5. If a complex task succeeded → consider creating a skill for it
6. If a mistake was made → add to failure registry with fix
7. Check tool registry — did we discover new capabilities?
```

### 11.3 Skill Discovery

```bash
# Install skills from community
npx skills add https://github.com/garrytan/gstack --skill browse
npx skills add https://github.com/garrytan/gstack --skill review
npx skills add https://github.com/garrytan/gstack --skill ship
npx skills add https://github.com/garrytan/gstack --skill qa

# List available skills
/skills
```

---

## 12. Self-Improvement Engine

### 12.1 Three Loops (Hermes + OpenClaw Hybrid)

**Loop 1: Micro (Every 15 Tool Calls)**
- Quick self-assessment: Am I on track? Am I being efficient?
- Implemented via PostToolUse hook with counter
- If stuck: escalate or try different approach
- If wasteful: compress, delegate, or simplify

**Loop 2: Session (End of Each Session)**
- What did I learn? What mistakes did I make?
- Update agent memory with new patterns
- Create skills from successful complex workflows
- Update failure registry with new fixes
- Triggered by Stop hook → self-improve skill

**Loop 3: Nightly (Cron at 23:00)**
- Consolidate daily memories
- Check for pattern promotion (3+ occurrences)
- Monitor repos for new tools/features
- Update tool registry
- Self-update checks (Claude Code, GSD, skills)

### 12.2 Pattern Promotion System (OpenClaw)

```
Observation → Lesson → Pattern → Rule → System Prompt

1. First occurrence: Save as lesson in agent memory
2. Second occurrence: Flag as emerging pattern
3. Third occurrence: PROMOTE to .claude/rules/ and CLAUDE.md
```

### 12.3 Failure Registry

```markdown
# ~/.claude/agent-memory/alba/failures.md

## [2026-04-01] Git push failed — detached HEAD
- **What happened:** Tried to push from detached HEAD state
- **Root cause:** Forgot to checkout branch after worktree operation
- **Fix:** Always `git checkout -b` before committing in worktrees
- **Prevention:** Add pre-push check to hooks
- **Occurrences:** 1

## [2026-04-01] MCP server timeout
- **What happened:** ElevenLabs MCP server timed out during TTS
- **Root cause:** Network latency + large text
- **Fix:** Chunk large texts, set timeout to 30s
- **Prevention:** Pre-chunk text before sending
- **Occurrences:** 1
```

### 12.4 Autonomous Skill Creation (Hermes Pattern)

After completing a complex task (5+ tool calls):
1. Evaluate: Was this task type likely to recur?
2. If yes: Extract the workflow into a skill template
3. Save to `~/.claude/skills/auto-generated/`
4. Add to skills-created.md in agent memory
5. Test skill on next similar task

---

## 13. Scheduling & Automation

### 13.1 Claude Code Built-in Cron

```bash
# Create scheduled tasks directly in Claude Code
# /loop and CronCreate tools

# Example: Check emails every 30 minutes
CronCreate(schedule="*/30 * * * *", prompt="Check unread emails, summarize important ones")

# Example: Daily morning briefing at 7:00
CronCreate(schedule="0 7 * * *", prompt="/daily-briefing")

# Example: Nightly routine at 23:00
CronCreate(schedule="0 23 * * *", prompt="/nightly-routine")

# Example: Weekly retrospective on Friday at 18:00
CronCreate(schedule="0 18 * * 5", prompt="Generate weekly retrospective of all work done")
```

### 13.2 macOS Cron Jobs (via crontab)

```bash
# Essential cron jobs for Alba
crontab -e

# Memory sync with VPS (every 30 min)
*/30 * * * * /Users/alba/bin/sync-memory.sh

# Heartbeat check (every 15 min)
*/15 * * * * /Users/alba/bin/alba-heartbeat.sh

# Weekly cleanup (Sunday 4 AM)
0 4 * * 0 /Users/alba/bin/cleanup-mac.sh

# Daily tool registry update (midnight)
0 0 * * * /Users/alba/bin/update-tool-registry.sh
```

### 13.3 Standing Orders (~/.alba/standing-orders.md)

```markdown
# Standing Orders — Always Active

## Priority 1: Responsiveness
- Every Telegram message gets a response within 30 seconds
- Every Slack mention gets a response within 2 minutes
- If task will take >2 minutes, send acknowledgment immediately

## Priority 2: Daily Operations
- 07:00 — Morning briefing (calendar, email, tasks, news)
- 12:00 — Midday status check (progress on today's tasks)
- 18:00 — End-of-day summary
- 23:00 — Nightly routine (updates, monitoring, memory consolidation)

## Priority 3: Monitoring
- Watch GitHub repos for new releases: anthropics/claude-code, nousresearch/hermes-agent, openclaw/openclaw, garrytan/gstack, gsd-build/gsd-2
- Watch Twitter for #ClaudeCode, #AIAgents, competitor announcements
- Check client project deployments for errors

## Priority 4: Self-Improvement
- After every session: run self-improve skill
- Every 15 tool calls: quick self-check
- Nightly: pattern promotion, tool updates, memory consolidation
```

---

## 14. Strategic Decision Engine

### 14.1 MiroFish-Offline Setup (Mac M4)

```bash
# Clone and setup
cd ~/Projects
git clone https://github.com/nikmcfly/MiroFish-Offline.git
cd MiroFish-Offline

# For Mac M4: remove NVIDIA GPU reservation from docker-compose.yml
# Then:
cp .env.example .env
# Edit .env: set OLLAMA_NUM_CTX=8192, model=qwen2.5:14b (for 16GB RAM)

docker compose up -d
docker exec mirofish-ollama ollama pull qwen2.5:14b
docker exec mirofish-ollama ollama pull nomic-embed-text

# Access: http://localhost:3000
```

### 14.2 When to Use

- Before any public announcement (press release, product launch)
- Before strategic decisions (pricing change, partnership, pivot)
- To test competitor response scenarios
- To anticipate market reaction to industry news
- To validate marketing messaging

### 14.3 Integration with Alba

Alba can orchestrate the full pipeline:
1. Write/receive the document to test
2. Upload to MiroFish via Flask API (localhost:5001)
3. Trigger graph build → environment setup → simulation
4. Wait for completion (monitor logs)
5. Retrieve and analyze report
6. Present findings to Ludovic with recommendations

---

## 15. Company Organization (Paperclip Pattern)

### 15.1 Orchestra Intelligence — AI Company Structure

```
                    ┌──────────────┐
                    │   LUDOVIC    │
                    │   (Human)    │
                    │   Board      │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │    ALBA      │
                    │  CEO Agent   │
                    │  (Claude)  │
                    └──────┬───────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
   ┌──────▼──────┐  ┌─────▼──────┐  ┌──────▼──────┐
   │ ENGINEERING  │  │ MARKETING  │  │  SUPPORT    │
   │    Team      │  │   Team     │  │   Team      │
   │  (Sonnet)    │  │  (Sonnet)  │  │  (Haiku)    │
   └──────┬───────┘  └─────┬──────┘  └──────┬──────┘
          │                │                │
   ┌──────┴──────┐  ┌─────┴──────┐  ┌──────┴──────┐
   │ - Coder     │  │ - SEO      │  │ - Client    │
   │ - Reviewer  │  │ - Social   │  │   Support   │
   │ - DevOps    │  │ - Content  │  │ - Admin     │
   │ - QA        │  │ - Analytics│  │ - Finance   │
   └─────────────┘  └────────────┘  └─────────────┘
```

### 15.2 Company Definition (COMPANY.md)

```yaml
---
name: Orchestra Intelligence
slug: orchestra-intelligence
mission: "Build the best AI-powered business orchestration platform"
ceo: Alba
teams:
  - engineering
  - marketing
  - support
budget:
  monthly_ceiling_usd: 500
  per_agent_limit_usd: 100
---
```

### 15.3 Goal Hierarchy

```
Mission: Build the best AI business orchestration platform
  └── Q2 Goal: Launch 3 client projects, establish SEO presence
       ├── Engineering: Ship Smart Renovation v1, Imagin CRM v2
       ├── Marketing: 50 blog posts, Twitter presence, SEO audit
       └── Support: Client onboarding, documentation
```

Every task traces back to the mission through this hierarchy.

---

## 16. Security & Monitoring

### 16.1 Permission Model

- `--dangerously-skip-permissions` for autonomous operation
- BUT: custom hooks guard against destructive commands
- PreToolUse hook checks for: `rm -rf`, `DROP TABLE`, `git push --force`, `sudo`, `kill -9`
- Warn and require confirmation for risky operations

### 16.2 Secret Management

```bash
# Secrets stored in environment variables, not in files
# Use .env file (git-ignored) for local secrets
# Never commit API keys, tokens, or passwords

# Key rotation schedule:
# - API keys: every 90 days
# - OAuth tokens: auto-refresh
# - SSH keys: annual rotation
```

### 16.3 Monitoring

```bash
# Heartbeat script (every 15 min via cron)
#!/bin/bash
# Check: Alba process alive, RAM usage, disk space, network
# Alert via Telegram if issues detected

# Log rotation
# ~/logs/alba-agent.log — rotated weekly, kept 4 weeks
```

### 16.4 Skill Security

- Review all community skills before installation
- Never install skills from untrusted sources
- Check for prompt injection patterns in SKILL.md files
- Monitor skill behavior via PostToolUse hooks

---

## 17. Daily & Nightly Routines

### 17.1 Morning (07:00)

```
→ Cron triggers /daily-briefing skill
→ Sub-agents gather: calendar, email, tasks, news, Twitter, Slack
→ Compile into French briefing
→ Send to Ludovic via Telegram
```

### 17.2 Midday (12:00)

```
→ Cron triggers status check
→ Review morning's work progress
→ Check for blocked tasks
→ Send status update to Ludovic
```

### 17.3 Evening (18:00)

```
→ Cron triggers end-of-day summary
→ What was accomplished today
→ What's pending for tomorrow
→ Any blockers or decisions needed
→ Send to Ludovic via Telegram
```

### 17.4 Night (23:00)

```
→ Cron triggers /nightly-routine skill
→ Sub-agents in parallel:
  1. Update all tools (brew upgrade, npm update -g, pip upgrade)
  2. Check watched GitHub repos for new releases
  3. Monitor competitor repos (OpenClaw, Hermes, etc.)
  4. Consolidate daily memories
  5. Pattern promotion check (3+ → rule)
  6. Update tool registry
  7. Security scan (npm audit, pip audit)
  8. Clean temp files, old logs
  9. Sync memory with VPS
→ Generate nightly report → save to daily log
→ Send summary to Ludovic if anything important found
```

### 17.5 Weekly (Sunday)

```
→ Generate weekly retrospective
→ Review all commits, PRs, tasks completed
→ Identify trends, bottlenecks, wins
→ Suggest improvements for next week
→ Full cleanup (caches, node_modules, docker prune)
```

---

## 18. Tool Registry — Know Thy Arsenal

### 18.1 Live Registry (~/.alba/tool-registry.json)

Updated automatically every night by the nightly routine:

```json
{
  "last_updated": "2026-04-01T23:00:00Z",
  "cli_tools": {
    "claude": { "version": "2.1.89", "path": "/usr/local/bin/claude", "purpose": "Main AI agent" },
    "gsd": { "version": "2.52.0", "path": "/usr/local/bin/gsd", "purpose": "Structured dev methodology" },
    "gh": { "version": "2.x", "path": "/opt/homebrew/bin/gh", "purpose": "GitHub CLI" },
    "gws": { "version": "0.4.4", "path": "/usr/local/bin/gws", "purpose": "Google Workspace CLI" },
    "yt-dlp": { "version": "latest", "path": "/opt/homebrew/bin/yt-dlp", "purpose": "YouTube downloader" },
    "ffmpeg": { "version": "latest", "path": "/opt/homebrew/bin/ffmpeg", "purpose": "Media processing" },
    "ollama": { "version": "latest", "path": "/opt/homebrew/bin/ollama", "purpose": "Local LLM runner" },
    "rg": { "version": "latest", "path": "/opt/homebrew/bin/rg", "purpose": "Fast search" },
    "bat": { "version": "latest", "path": "/opt/homebrew/bin/bat", "purpose": "Better cat" },
    "jq": { "version": "latest", "path": "/opt/homebrew/bin/jq", "purpose": "JSON processing" }
  },
  "mcp_servers": {
    "computer-use": "Screen control",
    "macos-automator": "AppleScript automation",
    "mobile-mcp": "Phone control",
    "elevenlabs": "Text-to-speech",
    "voicemode": "Speech-to-text + TTS",
    "x-twitter": "Twitter/X integration",
    "yt-dlp": "YouTube content",
    "whatsapp": "WhatsApp bridge",
    "google-workspace": "Gmail, Calendar, Drive, Sheets",
    "context7": "Library documentation",
    "brave-search": "Web search",
    "excalidraw": "Diagram creation",
    "gmail": "Email (Anthropic native)",
    "slack": "Slack integration",
    "supabase": "Database management",
    "vercel": "Deployment platform",
    "exa": "Deep web search",
    "google-sheets": "Spreadsheet access",
    "notion": "Notion workspace",
    "canva": "Design tool"
  },
  "plugins": {
    "telegram": "Messaging channel",
    "discord": "Messaging channel",
    "claude-mem": "Persistent memory",
    "compound-engineering": "Context7 + skills + reviews"
  },
  "skills": [],
  "agents": []
}
```

### 18.2 Auto-Discovery Hook

When a new tool is installed (detected by PostToolUse on `brew install`, `npm install -g`, `pip install`):
1. Detect the new tool name and version
2. Add to tool-registry.json
3. Update CLAUDE.md if it's a frequently-used tool
4. Log the addition

---

## 19. Memory Transfer from Zoe

### 19.1 What to Transfer

All memory files from the VPS are already syncing via rsync. But for the initial setup, manually copy:

```bash
# From VPS to Mac Mini
scp -r clawdbot@100.95.185.71:~/.claude/projects/-home-clawdbot/memory/* \
  ~/.claude/projects/-Users-alba/memory/

# Key files to transfer:
# - user_identity_personality.md (adapt for Alba identity)
# - feedback_workflow_principles.md (same rules apply)
# - feedback_memory_priority.md
# - feedback_memory_persistence.md
# - feedback_no_autonomous_actions.md
# - feedback_never_say_no.md
# - feedback_always_respond_investigate.md
# - project_infrastructure.md (update for Mac context)
# - project_clients.md (shared)
# - project_openclaw_context.md (shared)
# - project_anthropic_launches_2026.md (shared)
# - reference_cli_tools.md (create Mac-specific version)
```

### 19.2 What to Adapt

- Identity: Alba ≠ Zoe. Alba is the Mac-based CEO agent; Zoe is the VPS-based always-on agent
- Infrastructure references: Update paths, ports, services for macOS
- Tool list: Mac-specific tools (brew, Xcode, etc.)
- Memory sync: Ensure bidirectional sync doesn't create conflicts

---

## 20. Repo Structure

```
alba-blueprint/
├── README.md                        # Perfect README with all sources
├── BLUEPRINT.md                     # This document
├── ARCHITECTURE.md                  # Why decisions were made
├── CHANGELOG.md                     # Updates log
├── VERSION                          # Semver
├── LICENSE                          # MIT
│
├── install.sh                       # One-command installer
│
├── config/
│   ├── CLAUDE.md                    # Global CLAUDE.md template
│   ├── settings.json                # Global settings template
│   ├── settings.local.json.example  # Personal settings example
│   ├── .mcp.json                    # MCP servers config
│   ├── .env.example                 # Required environment variables
│   └── keybindings.json             # Custom keybindings
│
├── agents/
│   ├── researcher.md                # Research sub-agent
│   ├── coder.md                     # Implementation sub-agent
│   ├── reviewer.md                  # Code review sub-agent
│   ├── monitor.md                   # Background monitoring agent
│   ├── writer.md                    # Content creation agent
│   └── analyst.md                   # Data analysis agent
│
├── skills/
│   ├── daily-briefing/SKILL.md      # Morning briefing
│   ├── nightly-routine/SKILL.md     # Nightly maintenance
│   ├── apex/SKILL.md                # Feature workflow
│   ├── simulate/SKILL.md            # MiroFish simulation
│   ├── self-improve/SKILL.md        # Self-improvement
│   ├── ship/SKILL.md                # Ship workflow (from gstack)
│   ├── review/SKILL.md              # Code review (from gstack)
│   ├── qa/SKILL.md                  # QA testing (from gstack)
│   └── tool-discover/SKILL.md       # New tool discovery
│
├── rules/
│   ├── delegation.md                # When and how to delegate
│   ├── memory.md                    # Memory management rules
│   ├── security.md                  # Security rules
│   ├── communication.md             # How to communicate
│   └── self-improvement.md          # Self-improvement rules
│
├── hooks/
│   ├── session-start.sh             # Boot sequence
│   ├── session-stop.sh              # Session end (trigger self-improve)
│   ├── self-improvement-check.sh    # Every 15 tool calls
│   ├── destructive-command-guard.sh # Block dangerous commands
│   └── tool-discovery.sh            # Detect new tool installs
│
├── scripts/
│   ├── start-alba.sh                # Main launcher with watchdog
│   ├── sync-memory.sh               # Bidirectional memory sync with VPS
│   ├── alba-heartbeat.sh            # Health check (cron)
│   ├── cleanup-mac.sh               # Weekly cleanup
│   ├── update-tool-registry.sh      # Daily tool registry update
│   └── setup-permissions.sh         # macOS permission setup guide
│
├── launchd/
│   └── com.alba.agent.plist         # Auto-start on boot
│
├── memory/
│   ├── MEMORY.md                    # Memory index template
│   └── templates/                   # Memory file templates
│       ├── user_template.md
│       ├── feedback_template.md
│       ├── project_template.md
│       └── reference_template.md
│
├── company/
│   ├── COMPANY.md                   # Orchestra Intelligence definition
│   ├── teams/
│   │   ├── engineering/AGENTS.md
│   │   ├── marketing/AGENTS.md
│   │   └── support/AGENTS.md
│   └── goals/
│       └── Q2-2026.md
│
├── mcp-servers/
│   ├── setup-x-twitter.sh           # X/Twitter MCP setup
│   ├── setup-whatsapp.sh            # WhatsApp bridge setup
│   ├── setup-voicemode.sh           # Voice setup
│   └── setup-mirofish.sh            # MiroFish setup
│
└── docs/
    ├── SETUP-GUIDE.md               # Detailed setup walkthrough
    ├── TROUBLESHOOTING.md           # Common issues and fixes
    ├── PATTERNS.md                  # Design patterns reference
    └── SOURCES.md                   # All research sources
```

---

## 21. Installation

### One-Command Install

```bash
git clone https://github.com/orchestra-intelligence/alba-blueprint.git
cd alba-blueprint
chmod +x install.sh
./install.sh
```

### install.sh Overview

```bash
#!/bin/bash
set -euo pipefail

echo "=== ALBA Blueprint Installer ==="
echo "Setting up the ultimate AI agent on macOS..."

# 1. Check prerequisites
check_prerequisites() {
    command -v brew >/dev/null || { echo "Install Homebrew first"; exit 1; }
    command -v node >/dev/null || { echo "Install Node.js first"; exit 1; }
    command -v claude >/dev/null || { echo "Install Claude Code first"; exit 1; }
}

# 2. Create directory structure
setup_directories() {
    mkdir -p ~/.claude/{agents,commands,skills,rules,hooks/scripts,hooks/sounds,teams,tasks}
    mkdir -p ~/.claude/agent-memory/alba
    mkdir -p ~/.alba/{hooks,mcp-servers,logs}
    mkdir -p ~/bin ~/logs
}

# 3. Copy configuration files
copy_configs() {
    cp config/CLAUDE.md ~/.claude/CLAUDE.md
    cp config/settings.json ~/.claude/settings.json
    cp config/.mcp.json ~/.mcp.json
    cp config/.env.example ~/.alba/.env
    echo ">> Edit ~/.alba/.env with your API keys"
}

# 4. Install agents
install_agents() {
    cp agents/*.md ~/.claude/agents/
}

# 5. Install skills
install_skills() {
    cp -r skills/* ~/.claude/skills/
    # Install gstack skills
    npx skills add https://github.com/garrytan/gstack --skill browse 2>/dev/null || true
    npx skills add https://github.com/garrytan/gstack --skill review 2>/dev/null || true
    npx skills add https://github.com/garrytan/gstack --skill ship 2>/dev/null || true
}

# 6. Install rules
install_rules() {
    cp rules/*.md ~/.claude/rules/
}

# 7. Install hooks
install_hooks() {
    cp hooks/*.sh ~/.alba/hooks/
    chmod +x ~/.alba/hooks/*.sh
}

# 8. Install scripts
install_scripts() {
    cp scripts/*.sh ~/bin/
    chmod +x ~/bin/*.sh
}

# 9. Setup launchd
setup_launchd() {
    cp launchd/com.alba.agent.plist ~/Library/LaunchAgents/
    echo ">> Run: launchctl load ~/Library/LaunchAgents/com.alba.agent.plist"
}

# 10. Install MCP servers
setup_mcp_servers() {
    echo "Setting up MCP servers..."
    bash mcp-servers/setup-voicemode.sh
    # Others require API keys — run manually after .env is configured
}

# 11. Setup memory
setup_memory() {
    cp -r memory/* ~/.claude/projects/-Users-alba/memory/ 2>/dev/null || true
}

# Run all steps
check_prerequisites
setup_directories
copy_configs
install_agents
install_skills
install_rules
install_hooks
install_scripts
setup_launchd
setup_mcp_servers
setup_memory

echo ""
echo "=== ALBA Blueprint installed! ==="
echo ""
echo "Next steps:"
echo "1. Edit ~/.alba/.env with your API keys"
echo "2. Run: gws auth login (Google Workspace)"
echo "3. Run: claude login (Anthropic OAuth)"
echo "4. Grant macOS permissions (Screen Recording + Accessibility)"
echo "5. Run: launchctl load ~/Library/LaunchAgents/com.alba.agent.plist"
echo "6. Or manually: ~/bin/start-alba.sh"
echo ""
echo "Alba is ready to serve Orchestra Intelligence."
```

---

## 22. Auto-Update & Self-Evolution

### 22.1 Daily Auto-Update Check

```bash
# In nightly routine, Alba checks:
claude --version  # Compare with latest on npm
gsd --version     # Compare with latest on npm
brew outdated     # Check for Homebrew updates

# If updates found:
# 1. Log the available update
# 2. If minor/patch: auto-update
# 3. If major: notify Ludovic for approval
```

### 22.2 Repo Watching

Alba monitors these repos nightly for new releases:

| Repo | What to Watch |
|------|--------------|
| `anthropics/claude-code` | New versions, features, breaking changes |
| `nousresearch/hermes-agent` | Self-improvement patterns, new features |
| `openclaw/openclaw` | Skill ecosystem, architecture changes |
| `garrytan/gstack` | New skills, methodology updates |
| `gsd-build/gsd-2` | Workflow improvements |
| `karpathy/autoresearch` | Research automation patterns |
| `thedotmack/claude-mem` | Memory system improvements |
| `SawyerHood/middleman` | Multi-agent patterns |
| `msitarzewski/agency-agents` | Agent templates, NEXUS updates |
| `paperclipai/paperclip` | Company orchestration patterns |

### 22.3 Self-Evolution Protocol

```
1. DETECT: Nightly scan finds new feature/pattern
2. EVALUATE: Is it relevant to our setup? Score 1-10
3. PROPOSE: Create a plan for integration (if score >= 7)
4. NOTIFY: Send proposal to Ludovic via Telegram
5. IMPLEMENT: On approval, integrate via sub-agent
6. VERIFY: Test the integration
7. DOCUMENT: Update BLUEPRINT.md and CHANGELOG.md
```

---

## 23. Sources & Credits

### Research Repositories

| Repository | Stars | What We Learned |
|-----------|-------|----------------|
| [nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent) | 20.8K | Self-improvement loops, memory management, execute_code RPC, bounded delegation |
| [openclaw/openclaw](https://github.com/openclaw/openclaw) | 250K+ | Gateway architecture, 5-layer scheduling, pattern promotion, boot sequence, skill ecosystem |
| [garrytan/gstack](https://github.com/garrytan/gstack) | 59K | Skill templates, learning system, preamble pattern, builder philosophy, /ship /review /qa |
| [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) | Trending | CLAUDE.md structure, memory scopes, hook patterns, settings hierarchy, .claude/ organization |
| [instructkr/claw-code](https://github.com/instructkr/claw-code) | 50K | 207 internal commands, 184 tools, 44 feature flags, KAIROS daemon, architecture insights |
| [gsd-build/gsd-2](https://github.com/gsd-build/gsd-2) | -- | Milestone/slice/task hierarchy, auto mode, complexity routing, context engineering |
| [thedotmack/claude-mem](https://github.com/thedotmack/claude-mem) | 44K | Automatic observation capture, FTS5 search, progressive disclosure, smart-explore |
| [SawyerHood/middleman](https://github.com/SawyerHood/middleman) | 153 | Manager-worker delegation, swarmd runtime, worktree-per-worker, skill system |
| [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents) | -- | 147 agents, NEXUS pipeline, handoff templates, quality gates, MCP memory |
| [VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills) | -- | 5,211 curated skills, agent identity, self-improvement, memory, orchestration patterns |
| [paperclipai/paperclip](https://github.com/paperclipai/paperclip) | 43K | Company orchestration, org charts, goal hierarchy, budget enforcement, heartbeat execution |
| [paperclipai/companies](https://github.com/paperclipai/companies) | 229 | 16 company templates, AGENTS.md format, team organization patterns |
| [karpathy/autoresearch](https://github.com/karpathy/autoresearch) | 63K | Autonomous overnight research, program.md pattern, git-as-tracker, multi-agent hub |
| [nikmcfly/MiroFish-Offline](https://github.com/nikmcfly/MiroFish-Offline) | 1.6K | Social simulation, strategic decision testing, multi-agent persona generation |

### Key Articles & Analysis

- [Claude Code Source Leak — Alex Kim](https://alex000kim.com/posts/2026-03-31-claude-code-source-leak/)
- [I Read the Leaked Claude Code Source — Victor A](https://victorantos.com/posts/i-read-the-leaked-claude-code-source-heres-what-i-found/)
- [Every New Claude Launch Since January 2026 — Adam Holter](https://adam.holter.com/every-new-claude-launch-since-january-2026-full-timeline/)
- [Claude Code Source Code Leaked — The AI Corner](https://www.the-ai-corner.com/p/claude-code-source-code-leaked-2026)
- [Melvynx — 10 Features Incroyables](https://www.youtube.com/watch?v=OWdMpgGLkio)
- [Google Workspace CLI Made Claude Code 10x More Powerful](https://aimaker.substack.com/p/google-workspace-cli-claude-code-daily-operating-system)

### Anthropic Official Sources

- [Claude Code Changelog](https://code.claude.com/docs/en/changelog)
- [Claude Code Docs — Channels](https://code.claude.com/docs/en/channels)
- [Claude Code Docs — Computer Use](https://code.claude.com/docs/en/computer-use)
- [Claude Code Docs — Hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code Docs — Skills](https://code.claude.com/docs/en/skills)
- [Claude Code Docs — Scheduled Tasks](https://code.claude.com/docs/en/scheduled-tasks)
- [Claude Blog — Dispatch and Computer Use](https://claude.com/blog/dispatch-and-computer-use)

---

## License

MIT — Orchestra Intelligence, 2026

---

*Built with an army of 12 parallel research agents, synthesized by Zoe (Claude Code, 1M context), for Ludovic Goutel and Orchestra Intelligence.*
e.*
.*
