#!/usr/bin/env bash
# Unit test: hook failure modes (missing SKILL.md, unknown dir)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
SKILL="${PLUGIN_ROOT}/skills/orca-setup/SKILL.md"
trap 'cleanup_sandbox; rm -f "${SKILL}.hidden"; [ -f "${SKILL}.bak" ] && mv "${SKILL}.bak" "$SKILL"' EXIT

HOOK="${PLUGIN_ROOT}/hooks/session-start"
passed=0; failed=0

echo "=== Unit: failure modes ==="
echo ""

# Test: missing SKILL.md — hook should still exit 0 and produce valid JSON
cp "$SKILL" "${SKILL}.bak"
mv "$SKILL" "${SKILL}.hidden"

output=$(cd "$SANDBOX/src/orca" && bash "$HOOK" 2>/dev/null)
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "  [PASS] exit code 0 with missing SKILL.md"
    passed=$((passed+1))
else
    echo "  [FAIL] exit code 0 with missing SKILL.md (got $rc)"
    failed=$((failed+1))
fi

if assert_valid_json "$output" "valid JSON with missing SKILL.md"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Restore SKILL.md from backup
mv "${SKILL}.hidden" "$SKILL"
rm -f "${SKILL}.bak"

# Test: unknown dir produces valid JSON with no activate_project
output2=$(cd /tmp && bash "$HOOK" 2>/dev/null)

if assert_valid_json "$output2" "valid JSON from unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output2" "SERENA WORKSPACE DETECTED" "no project-specific activation from unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
