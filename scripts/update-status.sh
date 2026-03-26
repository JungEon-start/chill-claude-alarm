#!/bin/bash
# update-status.sh — Write Claude Code session status to a per-session JSON file.
# Called by Claude Code hooks. Reads session_id and cwd from stdin JSON.
#
# Usage:
#   echo '{"session_id":"abc","cwd":"/path"}' | update-status.sh <status> [message]
#   echo '{"session_id":"abc","cwd":"/path"}' | update-status.sh remove
#   echo '{"session_id":"abc","cwd":"/path"}' | update-status.sh idle_prompt

set -euo pipefail

STATUS="${1:-idle}"
MESSAGE="${2:-}"

# Validate status
case "$STATUS" in
    idle|running|permission_required|completed|error|remove|idle_prompt) ;;
    *) echo "Invalid status: $STATUS" >&2; exit 1 ;;
esac

# Read stdin (hooks pass JSON via stdin) — parse without jq
# Handles both compact and pretty-printed JSON (with optional spaces around colons)
# Use { grep ... || true; } to prevent pipefail from killing the script on no-match
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | { grep -oE '"session_id"\s*:\s*"[^"]*"' || true; } | head -1 | sed 's/.*:.*"\(.*\)"/\1/')
CWD=$(echo "$INPUT" | { grep -oE '"cwd"\s*:\s*"[^"]*"' || true; } | head -1 | sed 's/.*:.*"\(.*\)"/\1/')
SESSION_ID="${SESSION_ID:-unknown}"
CWD="${CWD:-unknown}"

# Sanitize session_id: strip path separators and traversal characters
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
SESSION_ID="${SESSION_ID:-unknown}"

STATUS_DIR="$HOME/.claude-status/sessions"
mkdir -p "$STATUS_DIR"
STATUS_FILE="$STATUS_DIR/${SESSION_ID}.json"

# Notification(idle_prompt): Claude is no longer actively working and is
# waiting for user input. Only collapse active states so we do not overwrite
# an explicit completed/error result written by Stop/StopFailure hooks.
if [ "$STATUS" = "idle_prompt" ]; then
    if [ ! -f "$STATUS_FILE" ]; then
        exit 0
    fi

    CURRENT_STATUS=$( { grep -oE '"status"\s*:\s*"[^"]*"' "$STATUS_FILE" || true; } | head -1 | sed 's/.*:.*"\(.*\)"/\1/')
    case "$CURRENT_STATUS" in
        running|permission_required)
            STATUS="completed"
            MESSAGE="${MESSAGE:-Waiting for input}"
            ;;
        *)
            exit 0
            ;;
    esac
fi

# SessionEnd: remove the session file
if [ "$STATUS" = "remove" ]; then
    rm -f "$STATUS_FILE"
    exit 0
fi

TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S%z")

# Escape special characters for JSON
escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
SAFE_MESSAGE=$(escape_json "$MESSAGE")
SAFE_CWD=$(escape_json "$CWD")

# Atomic write: temp file in SAME directory to guarantee rename(2) atomicity
TMP_FILE=$(mktemp "$STATUS_DIR/.tmp.XXXXXX")
cat > "$TMP_FILE" << EOF
{"session_id":"$SESSION_ID","status":"$STATUS","timestamp":"$TIMESTAMP","message":"$SAFE_MESSAGE","cwd":"$SAFE_CWD"}
EOF
mv "$TMP_FILE" "$STATUS_FILE"
