#!/usr/bin/env zsh
# GitHub Repo Watcher — Monitor key repos for updates
# Output: ~/Desktop/Alba/agent-world/veille/output/github-YYYY-MM-DD.md

set -euo pipefail

VEILLE_DIR="$HOME/Desktop/Alba/agent-world/veille"
OUTPUT_DIR="$VEILLE_DIR/output"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%dT00:00:00Z)
OUTPUT_FILE="$OUTPUT_DIR/github-$TODAY.md"

mkdir -p "$OUTPUT_DIR"

echo "# 🔍 GitHub Watch — $TODAY\n" > "$OUTPUT_FILE"

check_repo() {
  local repo="$1"
  local category="$2"
  
  echo "### [$repo](https://github.com/$repo)" >> "$OUTPUT_FILE"
  
  # Latest release
  local release=$(gh api "repos/$repo/releases/latest" --jq '.tag_name + " (" + .published_at[:10] + ")"' 2>/dev/null || echo "")
  [ -n "$release" ] && echo "**Latest release:** $release" >> "$OUTPUT_FILE"
  
  # Recent commits (last 24h)
  local commits=$(gh api "repos/$repo/commits?since=$YESTERDAY&per_page=5" --jq '.[].commit.message | split("\n")[0]' 2>/dev/null || echo "")
  if [ -n "$commits" ]; then
    echo "**Recent commits:**" >> "$OUTPUT_FILE"
    echo "$commits" | while read -r msg; do
      [ -n "$msg" ] && echo "- $msg" >> "$OUTPUT_FILE"
    done
  else
    echo "_No changes in last 24h_" >> "$OUTPUT_FILE"
  fi
  echo "" >> "$OUTPUT_FILE"
}

echo "## 🤖 Agent Frameworks\n" >> "$OUTPUT_FILE"
check_repo "SawyerHood/middleman" "agents"
check_repo "PaperclipAI/paperclip" "agents"
check_repo "anthropics/anthropic-cookbook" "agents"
check_repo "all-hands-ai/openhands" "agents"

echo "## 🔧 GSD\n" >> "$OUTPUT_FILE"
check_repo "glittercowboy/get-shit-done" "gsd"

echo "## 🔌 MCP Ecosystem\n" >> "$OUTPUT_FILE"
check_repo "modelcontextprotocol/servers" "mcp"
check_repo "modelcontextprotocol/modelcontextprotocol.io" "mcp"

echo "## 🛠 AI Tools\n" >> "$OUTPUT_FILE"
check_repo "Codium-ai/pr-agent" "tools"
check_repo "continuedev/continue" "tools"

echo "## 🧠 Open-Source AI\n" >> "$OUTPUT_FILE"
check_repo "ollama/ollama" "oss"
check_repo "open-webui/open-webui" "oss"

echo "## 📚 Anthropic\n" >> "$OUTPUT_FILE"
check_repo "anthropics/courses" "anthropic"

echo "---\n*Generated: $(date '+%Y-%m-%d %H:%M')*" >> "$OUTPUT_FILE"
echo "$OUTPUT_FILE"
