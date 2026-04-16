#!/usr/bin/env bash
# Unit test: plugin structure validation
# Verifies that the plugin layout follows the superpowers pattern:
#   - plugin.json exists and is valid
#   - hooks.json exists with SessionStart
#   - hook scripts exist and are executable
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: plugin structure validation ==="
echo ""

# --- 1. plugin.json ---
echo "--- .claude-plugin/plugin.json ---"

PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

if [ -f "$PLUGIN_JSON" ]; then
    echo "  [PASS] plugin.json exists"
    passed=$((passed+1))
else
    echo "  [FAIL] plugin.json missing at $PLUGIN_JSON"
    failed=$((failed+1))
fi

if [ -f "$PLUGIN_JSON" ]; then
    plugin_content=$(cat "$PLUGIN_JSON")

    if assert_valid_json "$plugin_content" "plugin.json is valid JSON"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi
    if assert_json_field "$plugin_content" '.name' "plugin.json has 'name' field"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi
fi

# --- 2. hooks.json ---
echo ""
echo "--- hooks/hooks.json ---"

HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"

if [ -f "$HOOKS_JSON" ]; then
    echo "  [PASS] hooks.json exists"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json missing at $HOOKS_JSON"
    failed=$((failed+1))
fi

if [ -f "$HOOKS_JSON" ]; then
    hooks_content=$(cat "$HOOKS_JSON")

    if assert_valid_json "$hooks_content" "hooks.json is valid JSON"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi

    # Check for SessionStart key (nested under .hooks)
    has_session_start=$(echo "$hooks_content" | jq -r '.hooks | has("SessionStart")' 2>/dev/null || echo "false")
    if [ "$has_session_start" = "true" ]; then
        echo "  [PASS] hooks.json has SessionStart key"
        passed=$((passed+1))
    else
        echo "  [FAIL] hooks.json missing SessionStart key"
        failed=$((failed+1))
    fi
fi

# --- 3. pre-tool-use ---
echo ""
echo "--- hooks/pre-tool-router ---"

PRE_TOOL_USE="${PLUGIN_ROOT}/hooks/pre-tool-router"

if [ -f "$PRE_TOOL_USE" ]; then
    echo "  [PASS] pre-tool-use exists"
    passed=$((passed+1))
else
    echo "  [FAIL] pre-tool-router missing at $PRE_TOOL_USE"
    failed=$((failed+1))
fi

if [ -x "$PRE_TOOL_USE" ]; then
    echo "  [PASS] pre-tool-use is executable"
    passed=$((passed+1))
else
    echo "  [FAIL] pre-tool-router is not executable"
    failed=$((failed+1))
fi

# Check hooks.json registers PreToolUse
if [ -f "$HOOKS_JSON" ]; then
    has_pretooluse=$(cat "$HOOKS_JSON" | jq -r '.hooks | has("PreToolUse")' 2>/dev/null || echo "false")
    if [ "$has_pretooluse" = "true" ]; then
        echo "  [PASS] hooks.json has PreToolUse key"
        passed=$((passed+1))
    else
        echo "  [FAIL] hooks.json missing PreToolUse key"
        failed=$((failed+1))
    fi
fi

# --- 4. session-start ---
echo ""
echo "--- hooks/session-start ---"

SESSION_START="${PLUGIN_ROOT}/hooks/session-start"

if [ -f "$SESSION_START" ]; then
    echo "  [PASS] session-start exists"
    passed=$((passed+1))
else
    echo "  [FAIL] session-start missing at $SESSION_START"
    failed=$((failed+1))
fi

if [ -x "$SESSION_START" ]; then
    echo "  [PASS] session-start is executable"
    passed=$((passed+1))
else
    echo "  [FAIL] session-start is not executable"
    failed=$((failed+1))
fi

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
