#!/bin/bash
# claude-wrapper.sh — Wrapper for Claude Code that updates status without hooks.
# Use this if you prefer not to configure Claude Code hooks.
#
# Usage: claude-wrapper.sh [claude args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="$HOME/.claude-status/scripts/update-status.sh"

# Fall back to local script if not installed
if [ ! -x "$UPDATE_SCRIPT" ]; then
    UPDATE_SCRIPT="$SCRIPT_DIR/update-status.sh"
fi

# Generate a simple session ID
SESSION_ID="wrapper-$$"
CWD="$(pwd)"
# Escape special characters for JSON safety
SAFE_CWD=$(printf '%s' "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')
STDIN_JSON="{\"session_id\":\"$SESSION_ID\",\"cwd\":\"$SAFE_CWD\"}"

# Mark as running
echo "$STDIN_JSON" | "$UPDATE_SCRIPT" running "Claude started"

# Run Claude Code, forwarding all arguments.
# Use an if-statement so non-zero exits do not terminate the wrapper before
# we can record the final error state.
if claude "$@"; then
    EXIT_CODE=0
    echo "$STDIN_JSON" | "$UPDATE_SCRIPT" completed "Task finished"
else
    EXIT_CODE=$?
    echo "$STDIN_JSON" | "$UPDATE_SCRIPT" error "Exited with code $EXIT_CODE"
fi

# Clean up after a short delay so the user can see the final status
(sleep 5 && echo "$STDIN_JSON" | "$UPDATE_SCRIPT" remove) &

exit $EXIT_CODE
