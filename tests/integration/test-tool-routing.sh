#!/usr/bin/env bash
# Integration test: Claude uses Codanna/Serena for code operations, not native tools
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Integration: tool routing ==="
echo ""

if ! command -v claude &>/dev/null; then
    echo "[SKIP] claude CLI not found"
    exit 0
fi

# ── Test 1: Python class search → Codanna, no native Grep/Read ───────────────
echo "Test 1: Python class search → Codanna used, no native Grep/Read on code"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/01-python-search.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca")

if assert_contains "$output" "mcp__codanna__" "Codanna tool called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# If Read was called on a .py file, the block message must appear (hook fired)
py_read=$(echo "$output" | /usr/bin/grep -c '"name":"Read"' || true)
if [ "$py_read" -gt 0 ]; then
    if assert_contains "$output" "BLOCKED" "Read attempted but was blocked by hook"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi
else
    echo "  [PASS] native Read not attempted (skill routing guidance worked)"
    passed=$((passed+1))
fi

echo ""

# ── Test 2: Find callers → find_callers with function_name param ──────────────
echo "Test 2: find callers → mcp__codanna__find_callers or semantic search"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/search-callers.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca")

if assert_contains "$output" "mcp__codanna__find_callers\|mcp__codanna__semantic_search" "Codanna callers/search called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output" '"name":"Grep"' "native Grep not used"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── Test 3: YAML config read → native Read allowed (not blocked) ──────────────
echo "Test 3: YAML config read → native Read allowed (not blocked)"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/03-config-read.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src")

if assert_not_contains "$output" "BLOCKED" "no BLOCKED message for yaml file"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" '"name":"Read"\|content\|values\|configuration' "Read executed successfully"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
