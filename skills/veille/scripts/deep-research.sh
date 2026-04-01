#!/bin/bash
# Deep Research — Cross-source AI/Tech Intelligence Analysis
# Uses Claude Code to analyze and cross-reference gathered intelligence
# Output: ~/Desktop/Alba/agent-world/veille/output/deep-YYYY-MM-DD.md

set -euo pipefail

VEILLE_DIR="$HOME/Desktop/Alba/agent-world/veille"
OUTPUT_DIR="$VEILLE_DIR/output"
CACHE_DIR="$VEILLE_DIR/cache"
TODAY=$(date +%Y-%m-%d)
DEEP_FILE="$OUTPUT_DIR/deep-$TODAY.md"
LOG_FILE="$VEILLE_DIR/veille.log"

source "$HOME/.secrets/.env" 2>/dev/null || true

log() { echo "[$(date '+%H:%M:%S')] DEEP: $1" | tee -a "$LOG_FILE"; }

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

log "=== Deep Research Started: $TODAY ==="

# ─── Step 1: Gather raw intelligence ────────────────────────
log "Step 1: Gathering sources..."

# Run daily veille if not done today
DAILY_FILE="$OUTPUT_DIR/$TODAY.md"
if [ ! -f "$DAILY_FILE" ]; then
  log "Running daily veille first..."
  bash "$VEILLE_DIR/scripts/daily-veille.sh" 2>/dev/null || true
fi

# Run GitHub watcher if not done today
GITHUB_FILE="$OUTPUT_DIR/github-$TODAY.md"
if [ ! -f "$GITHUB_FILE" ]; then
  log "Running GitHub watcher..."
  bash "$VEILLE_DIR/scripts/github-watcher.sh" 2>/dev/null || true
fi

# ─── Step 2: Collect all raw data ───────────────────────────
log "Step 2: Collecting raw data..."

RAW_CONTEXT="$CACHE_DIR/raw-context-$TODAY.md"
cat > "$RAW_CONTEXT" << EOF
# Raw Intelligence Data — $TODAY

## Daily Veille (RSS + YouTube)
$(cat "$DAILY_FILE" 2>/dev/null || echo "(not available)")

## GitHub Activity
$(cat "$GITHUB_FILE" 2>/dev/null || echo "(not available)")

## Currently Installed Versions
- Claude Code: $(claude --version 2>/dev/null || echo "unknown")
- GSD: $(cat ~/.claude/get-shit-done/VERSION 2>/dev/null || echo "unknown")
- Node: $(node --version 2>/dev/null || echo "unknown")
- yt-dlp: $(yt-dlp --version 2>/dev/null || echo "unknown")

## Current MCP Servers
$(claude mcp list 2>/dev/null || echo "(unknown)")
EOF

# ─── Step 3: Deep analysis via Claude ──────────────────────
log "Step 3: Running deep analysis with Claude..."

ANALYSIS_PROMPT="Tu es l'analyste intelligence d'Alba, l'agent IA personnel de Ludovic Goutel (Orchestra Intelligence).

Analyse ces données brutes de veille et produis un rapport DEEP en français :

$(cat "$RAW_CONTEXT")

---

Produis un rapport structuré avec :

## 🔥 Breaking — À traiter immédiatement
(Nouvelles releases critiques, breaking changes, opportunités time-sensitive)

## 🔧 Outils & Installations à faire
(Nouveaux outils découverts, mises à jour disponibles, installations recommandées)
Pour chaque outil : nom, ce que ça fait, pourquoi c'est utile pour nous, commande d'installation

## 🔄 Updates Frameworks
(Claude Code, Codex, GSD, MCP, Middleman, Paperclip, OpenClaw, etc.)
Versions actuelles vs disponibles, changelog résumé

## 🤖 Multi-Agent & Orchestration
(Avancées en orchestration d'agents, patterns, benchmarks)

## 💡 Techniques & Patterns
(Nouvelles techniques de prompt engineering, coding patterns, workflows)

## 🏢 Business Intel
(Mouvements concurrents, tendances marché, opportunités pour Orchestra Intelligence)

## 📊 Connexions Cross-Sources
(Patterns détectés en croisant les sources, insights non-évidents)

## ✅ Actions Recommandées
Liste ordonnée par priorité des actions concrètes à prendre aujourd'hui

Sois précis, factuel, actionnable. Pas de blabla — des insights."

# Use Claude in print mode for analysis
claude -p "$ANALYSIS_PROMPT" --model sonnet > "$DEEP_FILE" 2>/dev/null

if [ $? -eq 0 ] && [ -s "$DEEP_FILE" ]; then
  log "Deep analysis complete: $DEEP_FILE"
else
  log "ERROR: Claude analysis failed, falling back to raw data"
  cp "$RAW_CONTEXT" "$DEEP_FILE"
fi

# ─── Step 4: Save key findings to Satori memory ────────────
log "Step 4: Saving key findings to memory..."

# Extract action items for Satori
if command -v satori &>/dev/null; then
  satori remember "Veille $TODAY: Deep research completed. Report at $DEEP_FILE" 2>/dev/null || true
fi

log "=== Deep Research Complete: $DEEP_FILE ==="
echo "$DEEP_FILE"
