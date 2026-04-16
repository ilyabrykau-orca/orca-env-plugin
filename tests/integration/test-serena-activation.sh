#!/usr/bin/env bash
# Integration test: verify Claude calls mcp__serena__activate_project
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Integration: Serena activation ==="
echo ""

if ! command -v claude &>/dev/null; then
    echo "[SKIP] claude CLI not found"
    exit 0
fi

# Test 1: from orca dir, Claude should call activate_project with "orca"
echo "Test 1: activate_project called from orca/"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/what-project.txt")" \
    120 \
    "$PLUGIN_ROOT" \
    "/Users/ilyabrykau/src/orca")

if assert_contains "$output" "mcp__serena__activate_project" "activate_project tool called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" '"project".*"orca"|"orca".*"project"' "project=orca argument"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# Test 2: from orca-sensor dir
echo "Test 2: activate_project called from orca-sensor/"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/what-project.txt")" \
    120 \
    "$PLUGIN_ROOT" \
    "/Users/ilyabrykau/src/orca-sensor")

if assert_contains "$output" "mcp__serena__activate_project" "activate_project tool called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "orca-sensor" "correct project name"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
