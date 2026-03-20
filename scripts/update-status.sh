#!/bin/bash
# update-status.sh — Write Claude Code session status to a per-session JSON file.
# Called by Claude Code hooks. Reads session_id and cwd from stdin JSON.
#
# Usage:
#   echo '{"session_id":"abc","cwd":"/path"}' | update-status.sh <status> [message]
#   echo '{"session_id":"abc","cwd":"/path"}' | update-status.sh remove

set -euo pipefail

STATUS="${1:-idle}"
MESSAGE="${2:-}"

# Read stdin (hooks pass JSON via stdin) — parse without jq
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
CWD=$(echo "$INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4)
SESSION_ID="${SESSION_ID:-unknown}"
CWD="${CWD:-unknown}"

STATUS_DIR="$HOME/.claude-status/sessions"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/${SESSION_ID}.json"

# SessionEnd: remove the session file
if [ "$STATUS" = "remove" ]; then
    rm -f "$STATUS_FILE"
    exit 0
fi

TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z")

# Atomic write: write to temp file then move
TMP_FILE=$(mktemp)
cat > "$TMP_FILE" << EOF
{"session_id":"$SESSION_ID","status":"$STATUS","timestamp":"$TIMESTAMP","message":"$MESSAGE","cwd":"$CWD"}
EOF
mv "$TMP_FILE" "$STATUS_FILE"
