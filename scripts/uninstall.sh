#!/bin/bash
# uninstall.sh — Remove ClaudeStatusBar app and related files.
set -euo pipefail

APP_NAME="ClaudeStatusBar"
INSTALL_DIR="$HOME/Applications"

echo "=== ClaudeStatusBar Uninstaller ==="
echo ""

# Quit the app
echo "[1/3] Stopping $APP_NAME..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
echo "  -> Done."

# Remove app
echo "[2/3] Removing app..."
rm -rf "$INSTALL_DIR/$APP_NAME.app"
echo "  -> App removed."

# Remove status directory and scripts
echo "[3/3] Removing status files..."
rm -rf "$HOME/.claude-status"
echo "  -> Status files removed."

echo ""
echo "=== Uninstall Complete ==="
echo ""
echo "Note: Claude Code hooks in ~/.claude/settings.json were NOT removed."
echo "Remove the 'hooks' section manually if no longer needed."
