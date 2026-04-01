#!/bin/bash
# Setup X/Twitter MCP Server
# Requires: X Developer account with API keys

set -e

MCP_DIR="$HOME/.alba/mcp-servers"
mkdir -p "$MCP_DIR"

echo "=== Setting up X/Twitter MCP ==="

# Clone and build
cd "$MCP_DIR"
if [ ! -d "x-mcp" ]; then
    git clone https://github.com/Infatoshi/x-mcp.git
    cd x-mcp
    npm install
    npm run build
else
    echo "x-mcp already installed, updating..."
    cd x-mcp
    git pull
    npm install
    npm run build
fi

echo ""
echo "X MCP installed at: $MCP_DIR/x-mcp"
echo ""
echo "Next: Set these env vars in ~/.alba/.env:"
echo "  X_API_KEY=..."
echo "  X_API_SECRET=..."
echo "  X_ACCESS_TOKEN=..."
echo "  X_ACCESS_TOKEN_SECRET=..."
echo "  X_BEARER_TOKEN=..."
echo ""
echo "Get keys from: https://developer.x.com/en/portal/dashboard"
echo "Minimum tier: Basic ($200/mo) for read+write"
