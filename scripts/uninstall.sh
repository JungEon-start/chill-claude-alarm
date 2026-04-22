#!/bin/bash
# uninstall.sh — Remove Chill Claude app and related files.
set -euo pipefail

APP_NAME="Chill Claude"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
SYSTEM_APP_PATH="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "=== Chill Claude Uninstaller ==="
echo ""

# Quit the app
echo "[1/3] Stopping $APP_NAME..."
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
osascript -e 'tell application id "com.claude.statusbar" to quit' 2>/dev/null || true
pkill -f "ChillClaude" 2>/dev/null || true
sleep 1
echo "  -> Done."

# Remove app
echo "[2/3] Removing app..."
for app_path in "$APP_PATH" "$SYSTEM_APP_PATH"; do
    if [ -d "$app_path" ]; then
        rm -rf "$app_path" 2>/dev/null || true
    fi
done
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP_PATH" >/dev/null 2>&1 || true
    "$LSREGISTER" -u "$SYSTEM_APP_PATH" >/dev/null 2>&1 || true
fi
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
