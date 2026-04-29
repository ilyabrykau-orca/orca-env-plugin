#!/usr/bin/env bash
# Unit test: skills lint — v7
# Validates frontmatter, correct tool names, no codanna references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: skills lint ==="
echo ""

# --- 1. Frontmatter validation for all SKILL.md ---
echo "--- Skill frontmatter ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    if head -1 "$skill_file" | grep -q '^---$'; then
        echo "  [PASS] ${skill_name}: has --- frontmatter delimiter"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing --- frontmatter delimiter"
        failed=$((failed+1))
    fi

    if grep -q '^name:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has name: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing name: field"
        failed=$((failed+1))
    fi

    if grep -q '^description:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has description: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing description: field"
        failed=$((failed+1))
    fi
done

# --- 2. No codanna references in any skill ---
echo ""
echo "--- No codanna references ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    if grep -qi 'codanna' "$skill_file"; then
        echo "  [FAIL] ${skill_name}: contains codanna reference (must use CBM)"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no codanna references"
        passed=$((passed+1))
    fi
done

# --- 3. No codanna skill directory ---
echo ""
echo "--- No codanna skill dir ---"

if [ -d "${PLUGIN_ROOT}/skills/codanna" ]; then
    echo "  [FAIL] skills/codanna/ still exists (should be removed in v7)"
    failed=$((failed+1))
else
    echo "  [PASS] skills/codanna/ does not exist"
    passed=$((passed+1))
fi

# --- 4. CBM tool names in cbm-workflow ---
echo ""
echo "--- CBM tool names in cbm-workflow ---"

CBM_SKILL="${PLUGIN_ROOT}/skills/cbm-workflow/SKILL.md"
if [ -f "$CBM_SKILL" ]; then
    for tool in search_code search_graph get_code_snippet get_architecture trace_path; do
        if grep -q "$tool" "$CBM_SKILL"; then
            echo "  [PASS] cbm-workflow references $tool"
            passed=$((passed+1))
        else
            echo "  [FAIL] cbm-workflow missing $tool reference"
            failed=$((failed+1))
        fi
    done

    if grep -q 'query_graph' "$CBM_SKILL"; then
        echo "  [PASS] cbm-workflow has progressive disclosure (query_graph)"
        passed=$((passed+1))
    else
        echo "  [FAIL] cbm-workflow missing query_graph progressive disclosure"
        failed=$((failed+1))
    fi

    if grep -q 'Wrong.*Right\|Wrong|Right' "$CBM_SKILL"; then
        echo "  [PASS] cbm-workflow has Wrong vs Right table"
        passed=$((passed+1))
    else
        echo "  [FAIL] cbm-workflow missing Wrong vs Right table"
        failed=$((failed+1))
    fi
else
    echo "  [FAIL] cbm-workflow/SKILL.md does not exist"
    failed=$((failed+1))
fi

# --- 5. Serena tool names in serena-workflow ---
echo ""
echo "--- Serena tool names in serena-workflow ---"

SERENA_SKILL="${PLUGIN_ROOT}/skills/serena-workflow/SKILL.md"
if [ -f "$SERENA_SKILL" ]; then
    for tool in replace_symbol_body replace_content insert_after_symbol find_referencing_symbols; do
        if grep -q "$tool" "$SERENA_SKILL"; then
            echo "  [PASS] serena-workflow references $tool"
            passed=$((passed+1))
        else
            echo "  [FAIL] serena-workflow missing $tool reference"
            failed=$((failed+1))
        fi
    done

    if grep -q '\$!1' "$SERENA_SKILL"; then
        echo "  [PASS] serena-workflow has backrefs \$!1 guidance"
        passed=$((passed+1))
    else
        echo "  [FAIL] serena-workflow missing backrefs guidance"
        failed=$((failed+1))
    fi
else
    echo "  [FAIL] serena-workflow/SKILL.md does not exist"
    failed=$((failed+1))
fi

# --- 6. replace_content param validation ---
echo ""
echo "--- replace_content param names ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")
    if ! grep -q 'replace_content(' "$skill_file"; then
        continue
    fi

    context=$(grep -A5 'replace_content(' "$skill_file")

    if echo "$context" | grep -q 'pattern='; then
        echo "  [FAIL] ${skill_name}: replace_content uses 'pattern=' (should be 'needle=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'pattern=' param"
        passed=$((passed+1))
    fi

    if echo "$context" | grep -q 'replacement='; then
        echo "  [FAIL] ${skill_name}: uses 'replacement=' (should be 'repl=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'replacement=' param"
        passed=$((passed+1))
    fi

    if echo "$context" | grep -q 'is_regex='; then
        echo "  [FAIL] ${skill_name}: uses 'is_regex=' (should be 'mode=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'is_regex=' param"
        passed=$((passed+1))
    fi
done

# --- 7. orca-setup references CBM not codanna ---
echo ""
echo "--- orca-setup uses CBM tools ---"

SETUP_SKILL="${PLUGIN_ROOT}/skills/orca-setup/SKILL.md"
if [ -f "$SETUP_SKILL" ]; then
    if grep -q 'mcp__codebase-memory-mcp__' "$SETUP_SKILL"; then
        echo "  [PASS] orca-setup references CBM namespace"
        passed=$((passed+1))
    else
        echo "  [FAIL] orca-setup missing CBM namespace references"
        failed=$((failed+1))
    fi
fi

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
