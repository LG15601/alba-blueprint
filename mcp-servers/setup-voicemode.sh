#!/bin/bash
# Setup VoiceMode (2-way voice: STT + TTS)
# Supports fully local mode (no cloud dependency)

set -e

echo "=== Setting up VoiceMode ==="

# Install uv if not present
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# Install VoiceMode
uvx voice-mode-install

# Install local engines (optional but recommended)
echo "Installing local Whisper (STT)..."
voicemode whisper install 2>/dev/null || echo "Whisper install requires manual setup"

echo "Installing local Kokoro (TTS backup)..."
voicemode kokoro install 2>/dev/null || echo "Kokoro install requires manual setup"

# Add to Claude Code MCP
claude mcp add --scope user voicemode -- uvx --refresh voice-mode 2>/dev/null || true

echo ""
echo "VoiceMode installed."
echo ""
echo "To start local engines:"
echo "  voicemode whisper start"
echo "  voicemode kokoro start"
echo ""
echo "For ElevenLabs TTS (premium quality):"
echo "  Set ELEVENLABS_API_KEY in ~/.alba/.env"
echo "  MCP config already in .mcp.json"
