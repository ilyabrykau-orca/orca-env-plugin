#!/usr/bin/env bash
# E2E matrix test: orca Python feature — search, trace refs, edit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
passed=0
failed=0

echo "=== orca-python-feature: Add last_seen_at to User model ==="

PROMPT='Do these steps in order:
1. Use mcp__codebase-memory-mcp__search_code to search for "class User" in the orca project
2. Use mcp__serena__find_referencing_symbols to find references to the User model
3. Use mcp__serena__replace_symbol_body or replace_content to add a last_seen_at field
4. Run pytest to verify'

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 8 180)
    tools=$(extract_tool_calls "$transcript")

    all_pass=true

    if echo "$tools" | grep -q "codebase"; then
        echo "  [PASS] CBM used for search"
    else
        echo "  [FAIL] CBM not used — tools: $(echo "$tools" | tr '\n' ' ')"
        all_pass=false
    fi

    if echo "$tools" | grep -q "find_referencing_symbols"; then
        echo "  [PASS] find_referencing_symbols called"
    else
        echo "  [FAIL] find_referencing_symbols not called"
        all_pass=false
    fi

    if echo "$tools" | grep -q "serena"; then
        echo "  [PASS] Serena used"
    else
        echo "  [FAIL] Serena not used"
        all_pass=false
    fi

    assert_no_native_on_code "$transcript" "no native tools on source" || all_pass=false

    if $all_pass; then
        passed=4
        break
    fi
done

if [ "$passed" -ge 3 ]; then
    echo "=== STATUS: PASSED ($passed/4 assertions) ==="
    exit 0
else
    echo "=== STATUS: FAILED ($passed/4 assertions) ==="
    exit 1
fi
