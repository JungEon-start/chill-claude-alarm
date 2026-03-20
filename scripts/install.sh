#!/bin/bash
# install.sh — Build and install ClaudeStatusBar app and scripts.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ClaudeStatusBar"
INSTALL_DIR="$HOME/Applications"
SCRIPTS_INSTALL_DIR="$HOME/.claude-status/scripts"

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
sleep 1

rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "build/$APP_NAME.app" "$INSTALL_DIR/"
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
