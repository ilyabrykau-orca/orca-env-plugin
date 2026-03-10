#!/usr/bin/env bash
# Unit test: JSON escaping edge cases (jq-based, no escape_for_json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: JSON escaping edge cases ==="
echo ""

# The session-start hook now uses jq --arg for escaping.
# Test that jq handles all edge cases correctly.

wrap_json() {
    jq -n --arg val "$1" '{"content": $val}'
}

# Test: double quotes
json=$(wrap_json 'say "hello"')
if echo "$json" | jq -e '.content == "say \"hello\""' >/dev/null 2>&1; then
    echo "  [PASS] double quotes survive jq round-trip"
    passed=$((passed+1))
else
    echo "  [FAIL] double quotes survive jq round-trip"
    failed=$((failed+1))
fi

# Test: backslashes
json=$(wrap_json 'path\to')
if echo "$json" | jq -e '.content == "path\\to"' >/dev/null 2>&1; then
    echo "  [PASS] backslashes survive jq round-trip"
    passed=$((passed+1))
else
    echo "  [FAIL] backslashes survive jq round-trip"
    failed=$((failed+1))
fi

# Test: newlines
json=$(wrap_json $'line1\nline2')
if echo "$json" | jq -e '.content == "line1\nline2"' >/dev/null 2>&1; then
    echo "  [PASS] newlines survive jq round-trip"
    passed=$((passed+1))
else
    echo "  [FAIL] newlines survive jq round-trip"
    failed=$((failed+1))
fi

# Test: tabs
json=$(wrap_json $'col1\tcol2')
if echo "$json" | jq -e '.content == "col1\tcol2"' >/dev/null 2>&1; then
    echo "  [PASS] tabs survive jq round-trip"
    passed=$((passed+1))
else
    echo "  [FAIL] tabs survive jq round-trip"
    failed=$((failed+1))
fi

# Test: full SKILL.md wrapped in JSON validates with jq
skill_content=$(< "${PLUGIN_ROOT}/skills/orca-setup/SKILL.md") 2>/dev/null || skill_content=""
json=$(jq -n --arg val "$skill_content" '{"content": $val}')
if echo "$json" | jq . >/dev/null 2>&1; then
    echo "  [PASS] SKILL.md content in JSON validates with jq"
    passed=$((passed+1))
else
    echo "  [FAIL] SKILL.md content in JSON validates with jq"
    failed=$((failed+1))
fi

# Test: markdown table with pipes and backticks
md_table='| Tool | Use `this` | Result |
| --- | --- | --- |
| `grep` | pattern\here | "found" |'
json=$(jq -n --arg val "$md_table" '{"table": $val}')
if echo "$json" | jq . >/dev/null 2>&1; then
    echo "  [PASS] markdown table with pipes and backticks survives jq escaping"
    passed=$((passed+1))
else
    echo "  [FAIL] markdown table with pipes and backticks survives jq escaping"
    failed=$((failed+1))
fi

# Test: Unicode characters
json=$(wrap_json 'émojis: 🎯 arrows: → ← ↑')
if echo "$json" | jq -e '.content | test("🎯")' >/dev/null 2>&1; then
    echo "  [PASS] Unicode characters survive jq round-trip"
    passed=$((passed+1))
else
    echo "  [FAIL] Unicode characters survive jq round-trip"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
