#!/bin/bash
# Integration tests for update-status.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/../scripts/update-status.sh"
WRAPPER_SCRIPT="$SCRIPT_DIR/../scripts/claude-wrapper.sh"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

# Override HOME so tests write to temp dir
export HOME="$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

describe() {
    echo ""
    echo "=== $1 ==="
}

it() {
    CURRENT_TEST="$1"
}

expect_pass() {
    if [ "$1" = "$2" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ $CURRENT_TEST"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ $CURRENT_TEST (expected: '$2', got: '$1')"
    fi
}

expect_file_exists() {
    if [ -f "$1" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ $CURRENT_TEST"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ $CURRENT_TEST (file not found: $1)"
    fi
}

expect_file_not_exists() {
    if [ ! -f "$1" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ $CURRENT_TEST"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ $CURRENT_TEST (file should not exist: $1)"
    fi
}

expect_json_field() {
    local file="$1" field="$2" expected="$3"
    local actual
    actual=$(grep -oE "\"$field\":\"[^\"]*\"" "$file" | head -1 | sed "s/\"$field\":\"//;s/\"//")
    if [ "$actual" = "$expected" ]; then
        PASS=$((PASS + 1))
        echo "  ✅ $CURRENT_TEST"
    else
        FAIL=$((FAIL + 1))
        echo "  ❌ $CURRENT_TEST (field '$field': expected '$expected', got '$actual')"
    fi
}

SESSION_DIR="$TEST_DIR/.claude-status/sessions"
TEST_BIN_DIR="$TEST_DIR/bin"
mkdir -p "$TEST_BIN_DIR"
ORIGINAL_PATH="$PATH"

# ============================================================
describe "Basic Status Write"
# ============================================================

it "creates session file for 'running' status"
echo '{"session_id":"test-001","cwd":"/tmp/project"}' | "$UPDATE_SCRIPT" running "Processing..."
expect_file_exists "$SESSION_DIR/test-001.json"

it "session file has correct session_id"
expect_json_field "$SESSION_DIR/test-001.json" "session_id" "test-001"

it "session file has correct status"
expect_json_field "$SESSION_DIR/test-001.json" "status" "running"

it "session file has correct message"
expect_json_field "$SESSION_DIR/test-001.json" "message" "Processing..."

it "session file has correct cwd"
expect_json_field "$SESSION_DIR/test-001.json" "cwd" "/tmp/project"

it "session file has timestamp"
TIMESTAMP=$(grep -oE '"timestamp":"[^"]*"' "$SESSION_DIR/test-001.json" | head -1)
if [ -n "$TIMESTAMP" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $CURRENT_TEST"
else
    FAIL=$((FAIL + 1))
    echo "  ❌ $CURRENT_TEST"
fi

# ============================================================
describe "Status Transitions"
# ============================================================

it "updates existing session to 'completed'"
echo '{"session_id":"test-001","cwd":"/tmp/project"}' | "$UPDATE_SCRIPT" completed "Task finished"
expect_json_field "$SESSION_DIR/test-001.json" "status" "completed"

it "updates existing session to 'error'"
echo '{"session_id":"test-001","cwd":"/tmp/project"}' | "$UPDATE_SCRIPT" error "An error occurred"
expect_json_field "$SESSION_DIR/test-001.json" "status" "error"

it "updates existing session to 'permission_required'"
echo '{"session_id":"test-001","cwd":"/tmp/project"}' | "$UPDATE_SCRIPT" permission_required "Approval needed"
expect_json_field "$SESSION_DIR/test-001.json" "status" "permission_required"

# ============================================================
describe "Session Removal"
# ============================================================

it "'remove' deletes session file"
echo '{"session_id":"test-001","cwd":"/tmp/project"}' | "$UPDATE_SCRIPT" remove
expect_file_not_exists "$SESSION_DIR/test-001.json"

it "'remove' succeeds even if file doesn't exist"
echo '{"session_id":"nonexistent","cwd":"/tmp"}' | "$UPDATE_SCRIPT" remove
expect_file_not_exists "$SESSION_DIR/nonexistent.json"

# ============================================================
describe "Multiple Sessions"
# ============================================================

it "supports multiple concurrent sessions"
echo '{"session_id":"sess-a","cwd":"/proj/a"}' | "$UPDATE_SCRIPT" running "A"
echo '{"session_id":"sess-b","cwd":"/proj/b"}' | "$UPDATE_SCRIPT" completed "B"
echo '{"session_id":"sess-c","cwd":"/proj/c"}' | "$UPDATE_SCRIPT" error "C"
expect_file_exists "$SESSION_DIR/sess-a.json"
it "session B exists"
expect_file_exists "$SESSION_DIR/sess-b.json"
it "session C exists"
expect_file_exists "$SESSION_DIR/sess-c.json"

it "each session has correct status"
expect_json_field "$SESSION_DIR/sess-a.json" "status" "running"

it "session B has completed status"
expect_json_field "$SESSION_DIR/sess-b.json" "status" "completed"

it "session C has error status"
expect_json_field "$SESSION_DIR/sess-c.json" "status" "error"

# ============================================================
describe "FIX #1: Missing fields no longer crash (grep + pipefail)"
# ============================================================

it "missing session_id defaults to 'unknown' (was: crash)"
echo '{"cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "test"
expect_file_exists "$SESSION_DIR/unknown.json"
expect_json_field "$SESSION_DIR/unknown.json" "session_id" "unknown"
rm -f "$SESSION_DIR/unknown.json"

it "missing cwd defaults to 'unknown' (was: crash)"
echo '{"session_id":"nocwd"}' | "$UPDATE_SCRIPT" running "test"
expect_json_field "$SESSION_DIR/nocwd.json" "cwd" "unknown"
rm -f "$SESSION_DIR/nocwd.json"

it "completely empty JSON defaults both to 'unknown'"
echo '{}' | "$UPDATE_SCRIPT" running "test"
expect_file_exists "$SESSION_DIR/unknown.json"
rm -f "$SESSION_DIR/unknown.json"

# ============================================================
describe "FIX #3: Path traversal in session_id is sanitized"
# ============================================================

it "session_id with ../ is sanitized (slashes stripped)"
echo '{"session_id":"../escape","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "test"
# "../escape" should become "escape" after sanitization (dots and slashes stripped)
expect_file_not_exists "$TEST_DIR/.claude-status/escape.json"
# Should be written as sanitized name in sessions dir
expect_file_exists "$SESSION_DIR/escape.json"
rm -f "$SESSION_DIR/escape.json"

it "session_id with only special chars defaults to 'unknown'"
echo '{"session_id":"../../../","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "test"
expect_file_exists "$SESSION_DIR/unknown.json"
rm -f "$SESSION_DIR/unknown.json"

it "normal session_id with dashes and underscores works"
echo '{"session_id":"my-session_01","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "test"
expect_file_exists "$SESSION_DIR/my-session_01.json"
rm -f "$SESSION_DIR/my-session_01.json"

# ============================================================
describe "FIX #10: Invalid status is rejected"
# ============================================================

it "rejects invalid status 'completd' (typo)"
if echo '{"session_id":"bad","cwd":"/tmp"}' | "$UPDATE_SCRIPT" completd "test" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  ❌ $CURRENT_TEST (should have rejected)"
else
    PASS=$((PASS + 1))
    echo "  ✅ $CURRENT_TEST"
fi

it "rejects arbitrary status 'hacked'"
if echo '{"session_id":"bad","cwd":"/tmp"}' | "$UPDATE_SCRIPT" hacked "test" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    echo "  ❌ $CURRENT_TEST (should have rejected)"
else
    PASS=$((PASS + 1))
    echo "  ✅ $CURRENT_TEST"
fi

it "accepts all valid statuses"
ALL_VALID=true
for s in idle running permission_required completed error remove; do
    if ! echo '{"session_id":"valid-test","cwd":"/tmp"}' | "$UPDATE_SCRIPT" "$s" "test" 2>/dev/null; then
        ALL_VALID=false
    fi
done
if $ALL_VALID; then
    PASS=$((PASS + 1))
    echo "  ✅ $CURRENT_TEST"
else
    FAIL=$((FAIL + 1))
    echo "  ❌ $CURRENT_TEST"
fi
rm -f "$SESSION_DIR/valid-test.json"

# ============================================================
describe "FIX #2: idle_prompt settles active states safely"
# ============================================================

it "idle_prompt converts running to completed"
echo '{"session_id":"idle-running","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "Working"
echo '{"session_id":"idle-running","cwd":"/tmp"}' | "$UPDATE_SCRIPT" idle_prompt "Waiting for input"
expect_json_field "$SESSION_DIR/idle-running.json" "status" "completed"
rm -f "$SESSION_DIR/idle-running.json"

it "idle_prompt converts permission_required to completed"
echo '{"session_id":"idle-perm","cwd":"/tmp"}' | "$UPDATE_SCRIPT" permission_required "Approval needed"
echo '{"session_id":"idle-perm","cwd":"/tmp"}' | "$UPDATE_SCRIPT" idle_prompt "Waiting for input"
expect_json_field "$SESSION_DIR/idle-perm.json" "status" "completed"
rm -f "$SESSION_DIR/idle-perm.json"

it "idle_prompt does not overwrite error"
echo '{"session_id":"idle-error","cwd":"/tmp"}' | "$UPDATE_SCRIPT" error "Boom"
echo '{"session_id":"idle-error","cwd":"/tmp"}' | "$UPDATE_SCRIPT" idle_prompt "Waiting for input"
expect_json_field "$SESSION_DIR/idle-error.json" "status" "error"
rm -f "$SESSION_DIR/idle-error.json"

it "idle_prompt is a no-op when no session file exists"
echo '{"session_id":"idle-missing","cwd":"/tmp"}' | "$UPDATE_SCRIPT" idle_prompt "Waiting for input"
expect_file_not_exists "$SESSION_DIR/idle-missing.json"

# ============================================================
describe "Edge Cases — Input"
# ============================================================

it "handles empty message"
echo '{"session_id":"empty-msg","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running ""
expect_json_field "$SESSION_DIR/empty-msg.json" "message" ""
rm -f "$SESSION_DIR/empty-msg.json"

it "handles default status (no args → idle)"
echo '{"session_id":"no-status","cwd":"/tmp"}' | "$UPDATE_SCRIPT"
expect_json_field "$SESSION_DIR/no-status.json" "status" "idle"
rm -f "$SESSION_DIR/no-status.json"

# ============================================================
describe "Edge Cases — Special Characters"
# ============================================================

it "handles cwd with spaces"
echo '{"session_id":"spaces","cwd":"/Users/test/my project"}' | "$UPDATE_SCRIPT" running "test"
expect_json_field "$SESSION_DIR/spaces.json" "cwd" "/Users/test/my project"
rm -f "$SESSION_DIR/spaces.json"

it "handles message with single quotes"
echo '{"session_id":"quotes","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "it's done"
expect_file_exists "$SESSION_DIR/quotes.json"
rm -f "$SESSION_DIR/quotes.json"

# ============================================================
describe "FIX #3: claude-wrapper records non-zero exits"
# ============================================================

it "wrapper returns the original non-zero exit code"
cat > "$TEST_BIN_DIR/claude" << 'EOF'
#!/bin/bash
exit 42
EOF
chmod +x "$TEST_BIN_DIR/claude"
export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
rm -f "$SESSION_DIR"/wrapper-*.json
set +e
"$WRAPPER_SCRIPT" >/dev/null 2>&1
WRAPPER_EXIT=$?
set -e
expect_pass "$WRAPPER_EXIT" "42"

it "wrapper writes error status after non-zero exit"
WRAPPER_FILES=("$SESSION_DIR"/wrapper-*.json)
if [ -e "${WRAPPER_FILES[0]}" ]; then
    expect_json_field "${WRAPPER_FILES[0]}" "status" "error"
else
    FAIL=$((FAIL + 1))
    echo "  ❌ $CURRENT_TEST (wrapper status file not found)"
fi
rm -f "$SESSION_DIR"/wrapper-*.json

# ============================================================
describe "Atomic Write Safety"
# ============================================================

it "no .tmp files left after write"
echo '{"session_id":"atomic-test","cwd":"/tmp"}' | "$UPDATE_SCRIPT" running "test"
TMP_COUNT=$(find "$SESSION_DIR" -name ".tmp.*" 2>/dev/null | wc -l | tr -d ' ')
expect_pass "$TMP_COUNT" "0"
rm -f "$SESSION_DIR/atomic-test.json"

# ============================================================
# Cleanup and Summary
# ============================================================

rm -f "$SESSION_DIR"/sess-*.json

echo ""
echo "=================================================="
echo "Results: $PASS passed, $FAIL failed, $((PASS + FAIL)) total"
if [ "$FAIL" -gt 0 ]; then
    echo "⚠️  Some tests failed!"
    exit 1
else
    echo "✅ All tests passed!"
fi
