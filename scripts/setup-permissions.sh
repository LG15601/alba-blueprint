#!/bin/bash
# Alba — macOS Permission Setup Guide
# Run this to check and guide through required permissions

echo "=== Alba — macOS Permission Setup ==="
echo ""
echo "The following permissions are required for full functionality:"
echo ""
echo "1. SCREEN RECORDING (required for Computer Use)"
echo "   System Settings → Privacy & Security → Screen Recording"
echo "   → Enable: Terminal.app (or your terminal)"
echo ""
echo "2. ACCESSIBILITY (required for Computer Use)"
echo "   System Settings → Privacy & Security → Accessibility"
echo "   → Enable: Terminal.app (or your terminal)"
echo ""
echo "3. FULL DISK ACCESS (recommended for file operations)"
echo "   System Settings → Privacy & Security → Full Disk Access"
echo "   → Enable: Terminal.app"
echo ""
echo "4. AUTOMATION (for AppleScript/macos-automator MCP)"
echo "   Will prompt automatically on first use"
echo ""
echo "After granting permissions, restart Terminal.app."
echo ""

# Check if we can take a screenshot (tests Screen Recording)
if screencapture -x /tmp/alba-test-screenshot.png 2>/dev/null; then
    rm -f /tmp/alba-test-screenshot.png
    echo "✓ Screen Recording: GRANTED"
else
    echo "✗ Screen Recording: NOT GRANTED — Computer Use won't work"
fi

echo ""
echo "=== Done ==="
