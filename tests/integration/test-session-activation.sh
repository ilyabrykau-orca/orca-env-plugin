#!/usr/bin/env bash
# Integration test: session-start injects correct project and Claude activates Serena
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Integration: session activation ==="
echo ""

if ! command -v claude &>/dev/null; then
    echo "[SKIP] claude CLI not found"
    exit 0
fi

# ── Test 1: orca/ → activates "orca" ─────────────────────────────────────────
echo "Test 1: from orca/ — should activate project=orca"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/activate-workspace.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca")

if assert_contains "$output" "mcp__serena__activate_project" "activate_project called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" '"project".*"orca"\|"orca".*activate_project\|project.*orca' "project=orca used"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output" '"project".*"orca-sensor"\|"project".*"orca-runtime"' "no wrong project"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── Test 2: orca-sensor/ → activates "orca-sensor" ───────────────────────────
echo "Test 2: from orca-sensor/ — should activate project=orca-sensor"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/activate-workspace.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src/orca-sensor")

if assert_contains "$output" "mcp__serena__activate_project" "activate_project called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "orca-sensor" "orca-sensor project name present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── Test 3: /src → activates "orca-unified" ──────────────────────────────────
echo "Test 3: from /src — should activate project=orca-unified"
output=$(run_claude \
    "$(cat "${SCRIPT_DIR}/prompts/activate-workspace.txt")" \
    120 "$PLUGIN_ROOT" "/Users/ilyabrykau/src")

if assert_contains "$output" "mcp__serena__activate_project" "activate_project called"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "orca-unified" "orca-unified project name present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
