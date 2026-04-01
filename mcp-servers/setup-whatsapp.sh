#!/bin/bash
# Setup WhatsApp MCP Bridge
# WARNING: Violates WhatsApp TOS. Use a secondary number.

set -e

MCP_DIR="$HOME/.alba/mcp-servers"
mkdir -p "$MCP_DIR"

echo "=== Setting up WhatsApp MCP Bridge ==="
echo ""
echo "WARNING: This uses an unofficial WhatsApp API."
echo "Risk of account ban. Use a secondary phone number."
echo ""

# Check Go is installed
if ! command -v go &>/dev/null; then
    echo "Go is required. Install with: brew install go"
    exit 1
fi

# Clone and build
cd "$MCP_DIR"
if [ ! -d "whatsapp-mcp" ]; then
    git clone https://github.com/lharries/whatsapp-mcp.git
    cd whatsapp-mcp
    go build -o whatsapp-bridge
else
    echo "whatsapp-mcp already installed, updating..."
    cd whatsapp-mcp
    git pull
    go build -o whatsapp-bridge
fi

echo ""
echo "WhatsApp bridge built at: $MCP_DIR/whatsapp-mcp/whatsapp-bridge"
echo ""
echo "Next steps:"
echo "1. Run: cd $MCP_DIR/whatsapp-mcp && ./whatsapp-bridge"
echo "2. Scan the QR code with your WhatsApp mobile app"
echo "3. The bridge will remember the session for future starts"
echo "4. MCP server config is already in .mcp.json"
