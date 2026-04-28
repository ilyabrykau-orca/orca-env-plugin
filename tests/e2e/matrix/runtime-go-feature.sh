#!/usr/bin/env bash
# E2E matrix test: runtime Go feature — search, trace refs, edit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
REQUIRED_PASS=3

echo "=== runtime-go-feature: Extract process cache TTL to config constant ==="

PROMPT='Do these steps in order:
1. Use mcp__codebase-memory-mcp__search_code to search for "TTL" or "cache" in the orca-runtime-sensor project
2. Use mcp__serena__find_referencing_symbols to find references to the cache TTL value
3. Use mcp__serena__replace_content to extract the TTL into a named constant
4. Run go test to verify'

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
