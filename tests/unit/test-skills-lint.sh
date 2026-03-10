#!/usr/bin/env bash
# Unit test: skills and commands lint
# Validates frontmatter, replace_content param names, and command descriptions.
# Expected: RED — serena-workflow/SKILL.md uses wrong replace_content params
#   (pattern=, replacement=, is_regex= instead of needle=, repl=, mode=)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: skills & commands lint ==="
echo ""

# --- 1. Frontmatter validation for all SKILL.md ---
echo "--- Skill frontmatter ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    # Check --- delimiter exists
    if head -1 "$skill_file" | grep -q '^---$'; then
        echo "  [PASS] ${skill_name}: has --- frontmatter delimiter"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing --- frontmatter delimiter"
        failed=$((failed+1))
    fi

    # Check name: field
    if grep -q '^name:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has name: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing name: field"
        failed=$((failed+1))
    fi

    # Check description: field
    if grep -q '^description:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has description: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing description: field"
        failed=$((failed+1))
    fi
done

# --- 2. replace_content param validation ---
echo ""
echo "--- replace_content param names ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    # Only check files that mention replace_content(
    if ! grep -q 'replace_content(' "$skill_file"; then
        continue
    fi

    echo "  Checking ${skill_name}/SKILL.md ..."

    # Extract lines around replace_content( calls (the call + next 5 lines)
    context=$(grep -A5 'replace_content(' "$skill_file")

    # MUST NOT have pattern= (wrong param name)
    if echo "$context" | grep -q 'pattern='; then
        echo "  [FAIL] ${skill_name}: replace_content uses 'pattern=' (should be 'needle=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'pattern=' param"
        passed=$((passed+1))
    fi

    # MUST NOT have replacement= (wrong param name)
    if echo "$context" | grep -q 'replacement='; then
        echo "  [FAIL] ${skill_name}: replace_content uses 'replacement=' (should be 'repl=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'replacement=' param"
        passed=$((passed+1))
    fi

    # MUST NOT have is_regex= (wrong param name)
    if echo "$context" | grep -q 'is_regex='; then
        echo "  [FAIL] ${skill_name}: replace_content uses 'is_regex=' (should be 'mode=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'is_regex=' param"
        passed=$((passed+1))
    fi

    # MUST have needle= (correct param name)
    if echo "$context" | grep -q 'needle='; then
        echo "  [PASS] ${skill_name}: has correct 'needle=' param"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing correct 'needle=' param"
        failed=$((failed+1))
    fi

    # MUST have repl= (correct param name)
    if echo "$context" | grep -q 'repl='; then
        echo "  [PASS] ${skill_name}: has correct 'repl=' param"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing correct 'repl=' param"
        failed=$((failed+1))
    fi

    # MUST have mode= (correct param name)
    if echo "$context" | grep -q 'mode='; then
        echo "  [PASS] ${skill_name}: has correct 'mode=' param"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing correct 'mode=' param"
        failed=$((failed+1))
    fi
done

# --- 3. Commands frontmatter ---
echo ""
echo "--- Command frontmatter ---"

for cmd_file in "${PLUGIN_ROOT}"/commands/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file" .md)

    if grep -q '^description:' "$cmd_file"; then
        echo "  [PASS] ${cmd_name}: has description: in frontmatter"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${cmd_name}: missing description: in frontmatter"
        failed=$((failed+1))
    fi
done

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
