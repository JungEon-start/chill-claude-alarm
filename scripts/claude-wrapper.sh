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
STDIN_JSON="{\"session_id\":\"$SESSION_ID\",\"cwd\":\"$CWD\"}"

# Mark as running
echo "$STDIN_JSON" | "$UPDATE_SCRIPT" running "Claude started"

# Run Claude Code, forwarding all arguments
claude "$@"
EXIT_CODE=$?

# Mark as completed or error based on exit code
if [ $EXIT_CODE -eq 0 ]; then
    echo "$STDIN_JSON" | "$UPDATE_SCRIPT" completed "Task finished"
else
    echo "$STDIN_JSON" | "$UPDATE_SCRIPT" error "Exited with code $EXIT_CODE"
fi

# Clean up after a short delay so the user can see the final status
(sleep 5 && echo "$STDIN_JSON" | "$UPDATE_SCRIPT" remove) &

exit $EXIT_CODE
