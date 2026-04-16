#!/usr/bin/env bash
# Integration test: PreToolUse hook blocks native Read on code files,
# Claude sees BLOCKED message and recovers using MCP tools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Integration: enforcement block + recovery ==="
echo ""

if ! command -v claude &>/dev/null; then
    echo "[SKIP] claude CLI not found"
    exit 0
fi

# ── Test 1: Direct Read on .py → blocked, recovers with MCP ──────────────────
echo "Test 1: Read on .py file — hook must block, Claude must recover with MCP"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/read-python-direct.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca")

# Hook fired and blocked
if assert_contains "$output" "BLOCKED" "hook fired — BLOCKED message present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# Claude recovered using MCP tools
if assert_contains "$output" "mcp__serena__\|mcp__codanna__" "Claude recovered with MCP tool"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# Native Read was attempted (that's what triggered the block)
if assert_contains "$output" '"name".*"Read"\|Read.*tool_use' "native Read was attempted (then blocked)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── Test 2: Grep prompt → hook blocks on code files, Codanna used ─────────────
echo "Test 2: grep prompt — hook blocks Grep on .py, Codanna used instead"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/09-native-block.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca")

# Either blocked OR (better) Claude didn't even try native Grep (skill guidance)
# At minimum, Codanna must be used
if assert_contains "$output" "mcp__codanna__\|mcp__serena__search_for_pattern" "MCP search tool used"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
