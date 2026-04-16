#!/usr/bin/env bash
# Unit test: session-start hook JSON output shape
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

passed=0; failed=0

echo "=== Unit: session-start output shape ==="
echo ""

# Test from orca dir (using sandbox)
output=$(run_hook_from "$SANDBOX/src/orca")

if assert_valid_json "$output" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.additionalContext' "hookSpecificOutput.additionalContext present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.hookEventName' "hookSpecificOutput.hookEventName present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.additional_context' "additional_context present (Cursor compat)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "EXTREMELY_IMPORTANT" "contains EXTREMELY_IMPORTANT wrapper"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "mcp__serena__activate_project" "contains Serena activation call"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "mcp__codanna__" "contains Codanna tool references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "find_referencing_symbols" "contains find_referencing_symbols mandate"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Test from unknown dir -- should still produce valid JSON without activation
echo ""
echo "--- From /tmp (no project) ---"
output2=$(run_hook_from /tmp)

if assert_valid_json "$output2" "output valid JSON (no project)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output2" "SERENA WORKSPACE DETECTED" "no project-specific activation for unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
