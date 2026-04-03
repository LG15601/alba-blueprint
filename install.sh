#!/bin/bash
set -euo pipefail

echo "============================================"
echo "  ALBA Blueprint — Ultimate AI Agent Setup"
echo "  Orchestra Intelligence"
echo "============================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

# 1. Check prerequisites
echo "--- Step 1: Prerequisites ---"
command -v brew >/dev/null && ok "Homebrew" || { fail "Homebrew not found. Install: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""; exit 1; }
command -v node >/dev/null && ok "Node.js $(node --version)" || { fail "Node.js not found. Install: brew install node@22"; exit 1; }
command -v claude >/dev/null && ok "Claude Code $(claude --version 2>/dev/null | head -1)" || { fail "Claude Code not found. Install: npm install -g @anthropic-ai/claude-code"; exit 1; }
command -v git >/dev/null && ok "Git" || { fail "Git not found"; exit 1; }
command -v gh >/dev/null && ok "GitHub CLI" || warn "GitHub CLI not found. Install: brew install gh"
command -v tmux >/dev/null && ok "tmux" || { warn "tmux not found. Install: brew install tmux"; }
command -v ollama >/dev/null && ok "Ollama $(ollama --version 2>/dev/null | head -1)" || warn "Ollama not installed. Install: brew install ollama && ollama pull gemma4"
echo ""

# 2. Create directory structure
echo "--- Step 2: Directory Structure ---"
mkdir -p ~/.claude/{agents,commands,skills,rules,hooks/scripts,hooks/sounds,teams,tasks}
mkdir -p ~/.claude/agent-memory/alba
mkdir -p ~/.alba/{hooks,mcp-servers,logs,logs/nightly}
mkdir -p ~/bin ~/logs
ok "Directories created"
echo ""

# 3. Copy configuration
echo "--- Step 3: Configuration ---"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$SCRIPT_DIR/config/CLAUDE.md" ~/.claude/CLAUDE.md
ok "CLAUDE.md → ~/.claude/CLAUDE.md"

cp "$SCRIPT_DIR/config/settings.json" ~/.claude/settings.json
ok "settings.json → ~/.claude/settings.json"

if [ ! -f ~/.mcp.json ]; then
    cp "$SCRIPT_DIR/config/.mcp.json" ~/.mcp.json
    ok ".mcp.json → ~/.mcp.json"
else
    warn ".mcp.json already exists — not overwriting. Compare with config/.mcp.json"
fi

if [ ! -f ~/.alba/.env ]; then
    cp "$SCRIPT_DIR/config/.env.example" ~/.alba/.env
    ok ".env template → ~/.alba/.env (EDIT WITH YOUR API KEYS)"
else
    warn ".alba/.env already exists — not overwriting"
fi
echo ""

# 4. Install agents
echo "--- Step 4: Agents ---"
cp "$SCRIPT_DIR"/agents/*.md ~/.claude/agents/
ok "$(ls "$SCRIPT_DIR"/agents/*.md | wc -l | tr -d ' ') agents installed"
echo ""

# 5. Install skills
echo "--- Step 5: Skills ---"
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    # Copy ENTIRE skill directory (SKILL.md + scripts/ + data/)
    cp -r "$skill_dir" ~/.claude/skills/"$skill_name"
    # Make scripts executable
    chmod +x ~/.claude/skills/"$skill_name"/scripts/*.sh 2>/dev/null || true
done
ok "$(ls -d "$SCRIPT_DIR"/skills/*/ | wc -l | tr -d ' ') skills installed (with scripts + data)"

# Install gstack skills (optional — only if claude skills CLI available)
if command -v claude >/dev/null && claude skills list >/dev/null 2>&1; then
    echo "  Checking for community skills..."
    warn "Community skill installation requires manual setup — see docs/SETUP-GUIDE.md"
fi
echo ""

# 5b. Install commands (slash commands)
echo "--- Step 5b: Commands ---"
for cmd_dir in "$SCRIPT_DIR"/commands/*/; do
    [ -d "$cmd_dir" ] || continue
    cmd_name=$(basename "$cmd_dir")
    cp -r "$cmd_dir" ~/.claude/commands/"$cmd_name"
done
ok "$(ls -d "$SCRIPT_DIR"/commands/*/ 2>/dev/null | wc -l | tr -d ' ') command namespaces installed"
echo ""

# 6. Install rules
echo "--- Step 6: Rules ---"
mkdir -p ~/.claude/rules
cp "$SCRIPT_DIR"/rules/*.md ~/.claude/rules/
ok "$(ls "$SCRIPT_DIR"/rules/*.md | wc -l | tr -d ' ') rules installed"
echo ""

# 7. Install hooks
echo "--- Step 7: Hooks ---"
cp "$SCRIPT_DIR"/hooks/*.sh ~/.alba/hooks/
chmod +x ~/.alba/hooks/*.sh
ok "$(ls "$SCRIPT_DIR"/hooks/*.sh | wc -l | tr -d ' ') hooks installed"
echo ""

# 8. Install scripts
echo "--- Step 8: Scripts ---"
cp "$SCRIPT_DIR"/scripts/*.sh ~/bin/
chmod +x ~/bin/*.sh
ok "$(ls "$SCRIPT_DIR"/scripts/*.sh | wc -l | tr -d ' ') scripts installed to ~/bin/"
echo ""

# 9. Setup launchd
echo "--- Step 9: launchd ---"
cp "$SCRIPT_DIR"/launchd/com.alba.agent.plist ~/Library/LaunchAgents/ 2>/dev/null || warn "Could not copy plist (may need sudo)"
ok "launchd plist copied"
echo ""

# 10. Setup memory
echo "--- Step 10: Memory ---"
MEMORY_DIR="$HOME/.claude/projects/-Users-$(whoami)/memory"
mkdir -p "$MEMORY_DIR"
if [ ! -f "$MEMORY_DIR/MEMORY.md" ]; then
    cp "$SCRIPT_DIR"/memory/MEMORY.md "$MEMORY_DIR/"
    ok "Memory index initialized"
else
    warn "MEMORY.md already exists — not overwriting"
fi
echo ""

# 11. Install recommended tools
echo "--- Step 11: Recommended Tools ---"
TOOLS="ripgrep fd bat fzf jq yq tree htop yt-dlp ffmpeg"
for tool in $TOOLS; do
    if command -v "$tool" >/dev/null 2>&1 || brew list "$tool" >/dev/null 2>&1; then
        ok "$tool"
    else
        warn "$tool not installed. Run: brew install $tool"
    fi
done
echo ""

# 12. Setup VoiceMode
echo "--- Step 12: Voice (optional) ---"
if command -v uvx >/dev/null 2>&1; then
    bash "$SCRIPT_DIR/mcp-servers/setup-voicemode.sh" 2>/dev/null && ok "VoiceMode" || warn "VoiceMode setup needs manual completion"
else
    warn "uv not installed — skipping VoiceMode. Run: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
echo ""

# Summary
echo "============================================"
echo "  ALBA Blueprint Installed!"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "  1. Run onboarding:  bash ~/bin/onboard-alba.sh"
echo "     (configures permissions, auth, and API keys interactively)"
echo ""
echo "  2. Start Alba:      ~/bin/start-alba.sh"
echo "  3. Auto-start:      launchctl load ~/Library/LaunchAgents/com.alba.agent.plist"
echo ""
echo "Optional:"
echo "  - Twitter:   bash mcp-servers/setup-x-twitter.sh"
echo "  - WhatsApp:  bash mcp-servers/setup-whatsapp.sh"
echo "  - MiroFish:  bash mcp-servers/setup-mirofish.sh"
echo ""
echo "Alba is ready to serve Orchestra Intelligence."
