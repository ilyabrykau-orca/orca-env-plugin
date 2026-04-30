#!/usr/bin/env bash
# Unit test: plugin structure validation (v7 layout)
# Verifies:
#   - plugin.json: v7.x version, correct name
#   - hooks.json: v7 structure with split SessionStart, rtk-rewrite-bash, safe_delete_symbol
#   - hook scripts: session-start, session-start-compact, skill-activation-prompt,
#                   pre-tool-router, rtk-rewrite-bash, post-serena-refs, stop.js, subagent-stop.js
#   - skill dirs: cbm-workflow, serena-workflow, orca-setup, orca-dev
#   - no settings.json at root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: plugin structure validation (v7) ==="
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

    # name must be orca-env-plugin
    plugin_name=$(echo "$plugin_content" | jq -r '.name' 2>/dev/null || echo "")
    if [ "$plugin_name" = "orca-env-plugin" ]; then
        echo "  [PASS] plugin.json name is 'orca-env-plugin'"
        passed=$((passed+1))
    else
        echo "  [FAIL] plugin.json name: expected 'orca-env-plugin', got '$plugin_name'"
        failed=$((failed+1))
    fi

    # version must be 7.x
    plugin_version=$(echo "$plugin_content" | jq -r '.version' 2>/dev/null || echo "")
    if [[ "$plugin_version" =~ ^7\. ]]; then
        echo "  [PASS] plugin.json version is 7.x ($plugin_version)"
        passed=$((passed+1))
    else
        echo "  [FAIL] plugin.json version: expected 7.x, got '$plugin_version'"
        failed=$((failed+1))
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

    for key in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop SubagentStop; do
        has_key=$(echo "$hooks_content" | jq -r --arg k "$key" '.hooks | has($k)' 2>/dev/null || echo "false")
        if [ "$has_key" = "true" ]; then
            echo "  [PASS] hooks.json has $key"
            passed=$((passed+1))
        else
            echo "  [FAIL] hooks.json missing $key"
            failed=$((failed+1))
        fi
    done

    # SessionStart must have 2 entries (startup|clear and resume|compact)
    session_count=$(echo "$hooks_content" | jq '.hooks.SessionStart | length' 2>/dev/null || echo "0")
    if [ "$session_count" -eq 2 ]; then
        echo "  [PASS] SessionStart has 2 entries (startup and compact)"
        passed=$((passed+1))
    else
        echo "  [FAIL] SessionStart: expected 2 entries, got $session_count"
        failed=$((failed+1))
    fi

    # SessionStart compact entry references session-start-compact
    if assert_contains "$hooks_content" "session-start-compact" "hooks.json references session-start-compact"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi

    # PreToolUse must have 2 entries (router + rtk-rewrite-bash)
    pretool_count=$(echo "$hooks_content" | jq '.hooks.PreToolUse | length' 2>/dev/null || echo "0")
    if [ "$pretool_count" -eq 3 ]; then
        echo "  [PASS] PreToolUse has 3 entries (router + serena-read-guard + rtk-rewrite-bash)"
        passed=$((passed+1))
    else
        echo "  [FAIL] PreToolUse: expected 3 entries, got $pretool_count"
        failed=$((failed+1))
    fi

    # rtk-rewrite-bash must appear in hooks.json
    if assert_contains "$hooks_content" "rtk-rewrite-bash" "hooks.json references rtk-rewrite-bash"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi

    # safe_delete_symbol must appear in the pre-tool-router matcher
    if assert_contains "$hooks_content" "safe_delete_symbol" "hooks.json pre-tool-router includes safe_delete_symbol"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi
fi

# --- 3. Hook scripts exist and are executable ---
echo ""
echo "--- Hook scripts ---"

HOOK_SCRIPTS=(
    "session-start"
    "session-start-compact"
    "skill-activation-prompt"
    "pre-tool-router"
    "rtk-rewrite-bash"
    "post-serena-refs"
    "stop.js"
    "subagent-stop.js"
)

for script in "${HOOK_SCRIPTS[@]}"; do
    path="${PLUGIN_ROOT}/hooks/${script}"
    if [ -f "$path" ]; then
        echo "  [PASS] hooks/${script} exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] hooks/${script} missing"
        failed=$((failed+1))
    fi

    # .js files don't need to be executable via chmod; bash scripts do
    if [[ "$script" != *.js ]]; then
        if [ -x "$path" ]; then
            echo "  [PASS] hooks/${script} is executable"
            passed=$((passed+1))
        else
            echo "  [FAIL] hooks/${script} is not executable"
            failed=$((failed+1))
        fi
    fi
done

# --- 4. Skill directories (exactly 4) ---
echo ""
echo "--- Skill directories ---"

REQUIRED_SKILLS=(cbm-workflow serena-workflow orca-setup orca-dev)

for skill in "${REQUIRED_SKILLS[@]}"; do
    skill_dir="${PLUGIN_ROOT}/skills/${skill}"
    if [ -d "$skill_dir" ]; then
        echo "  [PASS] skills/${skill}/ exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] skills/${skill}/ missing"
        failed=$((failed+1))
    fi

    skill_md="${skill_dir}/SKILL.md"
    if [ -f "$skill_md" ]; then
        echo "  [PASS] skills/${skill}/SKILL.md exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] skills/${skill}/SKILL.md missing"
        failed=$((failed+1))
    fi
done

# --- 5. No settings.json at repo root ---
echo ""
echo "--- settings.json absent ---"

if [ ! -f "${PLUGIN_ROOT}/settings.json" ]; then
    echo "  [PASS] no settings.json at repo root"
    passed=$((passed+1))
else
    echo "  [FAIL] settings.json should not exist at repo root"
    failed=$((failed+1))
fi

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
