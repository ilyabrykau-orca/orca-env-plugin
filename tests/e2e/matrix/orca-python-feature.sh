#!/usr/bin/env bash
# E2E matrix test: orca Python feature — search, trace refs, edit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
REQUIRED_PASS=3

echo "=== orca-python-feature: Add last_seen_at to User model ==="

PROMPT='Do these steps in order:
1. Use mcp__codebase-memory-mcp__search_code to search for "class User" in the orca project
2. Use mcp__serena__find_referencing_symbols to find references to the User model
3. Use mcp__serena__replace_symbol_body or replace_content to add a last_seen_at field
4. Run pytest to verify'

best=0
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 8 180)
    tools=$(extract_tool_calls "$transcript")
    p=0

    echo "$tools" | grep -q "codebase" && { echo "  [PASS] CBM used"; p=$((p+1)); } || echo "  [FAIL] CBM not used"
    echo "$tools" | grep -q "find_referencing_symbols" && { echo "  [PASS] refs traced"; p=$((p+1)); } || echo "  [FAIL] refs not traced"
    echo "$tools" | grep -q "serena" && { echo "  [PASS] Serena used"; p=$((p+1)); } || echo "  [FAIL] Serena not used"
    assert_no_native_on_code "$transcript" "no native on source" && p=$((p+1)) || true

    [ "$p" -gt "$best" ] && best=$p
    [ "$p" -ge "$REQUIRED_PASS" ] && break
done

echo ""
echo "=== Result: $best/4 assertions passed (required $REQUIRED_PASS) ==="
[ "$best" -ge "$REQUIRED_PASS" ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED"; exit 1; }
