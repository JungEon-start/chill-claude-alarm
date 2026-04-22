#!/bin/bash
# install.sh — Build and install ClaudeStatusBar app and scripts.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Chill Claude"
INSTALL_DIR="$HOME/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"
SCRIPTS_INSTALL_DIR="$HOME/.claude-status/scripts"
SYSTEM_APP_PATH="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

echo "=== ClaudeStatusBar Installer ==="
echo ""

# 1. Build the app
echo "[1/4] Building $APP_NAME..."
cd "$PROJECT_DIR"
make build
echo "  -> Build complete."

# 2. Install app
echo "[2/4] Installing app to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Quit running instance if any
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
osascript -e 'tell application id "com.claude.statusbar" to quit' 2>/dev/null || true
pkill -f "ChillClaude" 2>/dev/null || true
sleep 1

for old_app in "$APP_PATH" "$SYSTEM_APP_PATH"; do
    rm -rf "$old_app" 2>/dev/null || true
done
cp -R "build/$APP_NAME.app" "$INSTALL_DIR/"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP_PATH" >/dev/null 2>&1 || true
fi
echo "  -> App installed."

# 3. Install scripts
echo "[3/4] Installing scripts to $SCRIPTS_INSTALL_DIR..."
mkdir -p "$SCRIPTS_INSTALL_DIR"
cp scripts/update-status.sh "$SCRIPTS_INSTALL_DIR/"
cp scripts/claude-wrapper.sh "$SCRIPTS_INSTALL_DIR/"
chmod +x "$SCRIPTS_INSTALL_DIR/update-status.sh"
chmod +x "$SCRIPTS_INSTALL_DIR/claude-wrapper.sh"
echo "  -> Scripts installed."

# 4. Create sessions directory
echo "[4/4] Setting up status directory..."
mkdir -p "$HOME/.claude-status/sessions"
echo "  -> Status directory ready."

echo ""
echo "=== Installation Complete ==="
echo ""
echo "To start the app:"
echo "  open $INSTALL_DIR/$APP_NAME.app"
echo ""
echo "To configure Claude Code hooks, add the following to ~/.claude/settings.json"
echo "(see config/settings.sample.json for the full configuration):"
echo ""
echo '  "hooks": { ... }'
echo ""
echo "Or use the wrapper script instead of hooks:"
echo "  $SCRIPTS_INSTALL_DIR/claude-wrapper.sh [args...]"
