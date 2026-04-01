#!/bin/bash
# Daily Veille — AI/Tech Intelligence Gathering
# Triggered via CRON or manually
# Uses: yt-dlp (YouTube), Claude WebFetch (web), RSS feeds
# Output: ~/Desktop/Alba/agent-world/veille/output/YYYY-MM-DD.md

set -euo pipefail

VEILLE_DIR="$HOME/Desktop/Alba/agent-world/veille"
OUTPUT_DIR="$VEILLE_DIR/output"
CACHE_DIR="$VEILLE_DIR/cache"
SOURCES="$VEILLE_DIR/sources.json"
TODAY=$(date +%Y-%m-%d)
OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"
LOG_FILE="$VEILLE_DIR/veille.log"

source "$HOME/.secrets/.env" 2>/dev/null || true

log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

log "=== Daily Veille Started: $TODAY ==="

# ─── 1. RSS FEEDS ───────────────────────────────────────────
fetch_rss() {
  log "Fetching RSS feeds..."
  local rss_output="$CACHE_DIR/rss-$TODAY.txt"
  
  # Extract RSS URLs from sources.json
  local feeds=$(python3 -c "
import json
with open('$SOURCES') as f:
    data = json.load(f)
for feed in data.get('rss', {}).get('feeds', []):
    print(f\"{feed['name']}|{feed['url']}|{feed.get('priority', 'medium')}\")
")
  
  echo "" > "$rss_output"
  while IFS='|' read -r name url priority; do
    log "  RSS: $name ($priority)"
    # Fetch and parse RSS (basic extraction)
    local content=$(curl -sL --max-time 15 "$url" 2>/dev/null | \
      python3 -c "
import sys, re, html
from xml.etree import ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    ns = {'atom': 'http://www.w3.org/2005/Atom'}
    items = root.findall('.//item') or root.findall('.//atom:entry', ns)
    count = 0
    for item in items[:5]:
        title = item.findtext('title') or item.findtext('atom:title', namespaces=ns) or 'No title'
        link = item.findtext('link') or ''
        if not link:
            link_el = item.find('atom:link', ns)
            link = link_el.get('href', '') if link_el is not None else ''
        pub = item.findtext('pubDate') or item.findtext('atom:published', namespaces=ns) or ''
        print(f'- [{html.unescape(title.strip())}]({link.strip()}) ({pub[:16]})')
        count += 1
    if count == 0:
        print('  (no items)')
except Exception as e:
    print(f'  (parse error: {e})')
" 2>/dev/null)
    echo -e "\n### $name ($priority)\n$content" >> "$rss_output"
  done <<< "$feeds"
  
  echo "$rss_output"
}

# ─── 2. YOUTUBE (via yt-dlp) ────────────────────────────────
fetch_youtube() {
  log "Fetching YouTube updates..."
  local yt_output="$CACHE_DIR/youtube-$TODAY.txt"
  echo "" > "$yt_output"
  
  local channels=$(python3 -c "
import json
with open('$SOURCES') as f:
    data = json.load(f)
for ch in data.get('youtube', {}).get('channels', []):
    print(f\"{ch['name']}|{ch['url']}|{ch.get('priority', 'medium')}\")
")
  
  while IFS='|' read -r name url priority; do
    log "  YouTube: $name"
    # Get latest videos from channel (last 24h)
    local videos=$(yt-dlp --flat-playlist --playlist-end 3 \
      --print "%(title)s|||%(url)s|||%(upload_date)s" \
      "$url/videos" 2>/dev/null | head -3)
    
    if [ -n "$videos" ]; then
      echo -e "\n### $name ($priority)" >> "$yt_output"
      while IFS='|||' read -r title vurl date; do
        [ -n "$title" ] && echo "- [$title]($vurl) ($date)" >> "$yt_output"
      done <<< "$videos"
    fi
  done <<< "$channels"
  
  echo "$yt_output"
}

# ─── 3. COMPILE DIGEST ─────────────────────────────────────
compile_digest() {
  local rss_file="$1"
  local yt_file="$2"
  
  cat > "$OUTPUT_FILE" << HEADER
# 📡 Veille Quotidienne — $TODAY

> Generée automatiquement par Alba Agent World
> Sources: $(python3 -c "import json; d=json.load(open('$SOURCES')); print(f\"{len(d.get('rss',{}).get('feeds',[]))} RSS + {len(d.get('youtube',{}).get('channels',[]))} YouTube + {len(d.get('twitter',{}).get('accounts',[]))} Twitter\")")

---

## 📰 RSS & Blogs
$(cat "$rss_file" 2>/dev/null || echo "(no data)")

---

## 🎥 YouTube — Nouvelles Vidéos
$(cat "$yt_file" 2>/dev/null || echo "(no data)")

---

## 🐦 X/Twitter
> ⚠️ Requires Twitter API credentials in ~/.secrets/.env
> Add: TWITTER_API_KEY, TWITTER_API_SECRET, TWITTER_ACCESS_TOKEN, TWITTER_ACCESS_TOKEN_SECRET, TWITTER_BEARER_TOKEN

---

*Prochaine veille: $(date -v+1d +%Y-%m-%d) 06:00*
HEADER

  log "Digest written to $OUTPUT_FILE"
}

# ─── MAIN ───────────────────────────────────────────────────
rss_file=$(fetch_rss)
yt_file=$(fetch_youtube)
compile_digest "$rss_file" "$yt_file"

log "=== Daily Veille Complete ==="
echo "$OUTPUT_FILE"
