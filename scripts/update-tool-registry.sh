#!/bin/bash
# Alba — Daily tool registry update (midnight via cron)

REGISTRY="$HOME/.alba/tool-registry.json"
mkdir -p "$HOME/.alba"

# Helper: get version or "not installed"
get_version() {
    "$1" --version 2>/dev/null | head -1 || echo "not installed"
}

# Build registry
cat > "$REGISTRY" <<EOF
{
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "cli_tools": {
    "claude": {"version": "$(get_version claude)", "path": "$(which claude 2>/dev/null)"},
    "gsd": {"version": "$(get_version gsd)", "path": "$(which gsd 2>/dev/null)"},
    "node": {"version": "$(get_version node)", "path": "$(which node 2>/dev/null)"},
    "bun": {"version": "$(get_version bun)", "path": "$(which bun 2>/dev/null)"},
    "python3": {"version": "$(get_version python3)", "path": "$(which python3 2>/dev/null)"},
    "gh": {"version": "$(gh --version 2>/dev/null | head -1)", "path": "$(which gh 2>/dev/null)"},
    "gws": {"version": "$(get_version gws)", "path": "$(which gws 2>/dev/null)"},
    "git": {"version": "$(get_version git)", "path": "$(which git 2>/dev/null)"},
    "docker": {"version": "$(get_version docker)", "path": "$(which docker 2>/dev/null)"},
    "ollama": {"version": "$(get_version ollama)", "path": "$(which ollama 2>/dev/null)"},
    "yt-dlp": {"version": "$(get_version yt-dlp)", "path": "$(which yt-dlp 2>/dev/null)"},
    "ffmpeg": {"version": "$(ffmpeg -version 2>/dev/null | head -1)", "path": "$(which ffmpeg 2>/dev/null)"},
    "rg": {"version": "$(get_version rg)", "path": "$(which rg 2>/dev/null)"},
    "jq": {"version": "$(get_version jq)", "path": "$(which jq 2>/dev/null)"},
    "bat": {"version": "$(get_version bat)", "path": "$(which bat 2>/dev/null)"},
    "fd": {"version": "$(get_version fd)", "path": "$(which fd 2>/dev/null)"}
  }
}
EOF

echo "[$(date)] Tool registry updated: $REGISTRY"
