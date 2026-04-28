#!/usr/bin/env bash
# Unit test: session-start-compact hook output shape
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

passed=0; failed=0

COMPACT_HOOK="${PLUGIN_ROOT}/hooks/session-start-compact"

echo "=== Unit: session-start-compact output shape ==="
echo ""

echo "--- From sandbox orca dir ---"
output=$(run_hook_from "$SANDBOX/src/orca" "$COMPACT_HOOK")

if assert_valid_json "$output" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.additionalContext' "hookSpecificOutput.additionalContext present (dual-shape)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.additional_context' "additional_context present (Cursor compat)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "tool_routing" "contains tool_routing block"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# CBM tools
if assert_contains "$output" "search_code" "contains CBM search_code"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "get_code_snippet" "contains CBM get_code_snippet"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "get_architecture" "contains CBM get_architecture"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Serena tools
if assert_contains "$output" "replace_symbol_body" "contains Serena replace_symbol_body"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "find_referencing_symbols" "contains Serena find_referencing_symbols"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "safe_delete_symbol" "contains Serena safe_delete_symbol"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Key params
if assert_contains "$output" '\$!1' "contains backrefs reminder (\$!1)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "qualified_name" "contains qualified_name param"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# No codanna
if assert_not_contains "$output" "mcp__codanna__" "no codanna references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Slim: < 50 lines in additionalContext
ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null || echo "")
line_count=$(echo "$ctx" | wc -l | tr -d ' ')
if [ "$line_count" -lt 50 ]; then
    echo "  [PASS] additionalContext is slim (${line_count} lines < 50)"
    passed=$((passed+1))
else
    echo "  [FAIL] additionalContext too large (${line_count} lines, expected < 50)"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
