#!/usr/bin/env bash
# Unit test: hook failure modes (unknown dir)
# v2: uses dist/claude-toolkit binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

echo "=== Unit: failure modes ==="
echo ""

# Test: unknown dir produces valid JSON with no activate_project
output=$(cd /tmp && echo '{}' | "$BINARY" session-start 2>/dev/null)

if assert_valid_json "$output" "valid JSON from unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output" "SERENA WORKSPACE DETECTED" "no project-specific activation from unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Test: sandbox orca dir — valid JSON, correct project detected
output2=$(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start 2>/dev/null)

if assert_valid_json "$output2" "valid JSON from sandbox orca dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output2" "activate_project" "activation call present from orca dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
