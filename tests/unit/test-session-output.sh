#!/usr/bin/env bash
# Unit test: session-start binary JSON output shape (v2)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

echo "=== Unit: session-start output shape ==="
echo ""

# Test from orca dir (using sandbox)
# run_hook_from uses the binary via session-start event
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
if assert_contains "$output" "mcp__serena__activate_project" "contains Serena activation call"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: references codebase-memory-mcp instead of codanna
if assert_contains "$output" "codebase-memory-mcp" "contains codebase-memory-mcp tool references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "replace_symbol_body" "contains replace_symbol_body in routing"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: no Params Cheat Sheet, no HARD-BLOCKED section
if assert_not_contains "$output" "mcp__codanna__" "no mcp__codanna__ references (renamed to codebase-memory-mcp)"; then
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
# v2: routing table still present even without project
if assert_contains "$output2" "codebase-memory-mcp" "routing table present (no project)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
