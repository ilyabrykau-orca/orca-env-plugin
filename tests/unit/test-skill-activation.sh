#!/usr/bin/env bash
# Unit test: skill-activation-prompt behavioral contract — v7
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: skill-activation-prompt ==="
echo ""

HOOK="${PLUGIN_ROOT}/hooks/skill-activation-prompt"

if [ ! -f "$HOOK" ]; then
    echo "  SKIPPED (hook not found: $HOOK)"
    exit 0
fi

run_prompt() {
    local prompt_text="$1"
    local json
    json=$(jq -n --arg p "$prompt_text" '{"prompt": $p}')
    echo "$json" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>/dev/null || true
}

# ── 1. CBM keyword: "search code" ───────────────────────────────────────────

echo "--- cbm-workflow triggers ---"

out=$(run_prompt "search code for authentication")
if echo "$out" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'search code for authentication' → cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'search code for authentication' → expected cbm-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── 2. CBM keyword: "who calls" ─────────────────────────────────────────────

out=$(run_prompt "who calls process_event")
if echo "$out" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'who calls process_event' → cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'who calls process_event' → expected cbm-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── 3. CBM keyword: "how does" ───────────────────────────────────────────────

out=$(run_prompt "how does the sensor pipeline work")
if echo "$out" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'how does the sensor pipeline work' → cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'how does the sensor pipeline work' → expected cbm-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── 4. Serena keyword: "refactor" ────────────────────────────────────────────

echo ""
echo "--- serena-workflow triggers ---"

out=$(run_prompt "refactor the authentication module")
if echo "$out" | grep -qi "serena-workflow"; then
    echo "  [PASS] 'refactor the authentication module' → serena-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'refactor the authentication module' → expected serena-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── 5. Serena keyword: "fix bug" ─────────────────────────────────────────────

out=$(run_prompt "fix bug in process_event handler")
if echo "$out" | grep -qi "serena-workflow"; then
    echo "  [PASS] 'fix bug in process_event handler' → serena-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'fix bug in process_event handler' → expected serena-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── 6. No match: generic greeting ────────────────────────────────────────────

echo ""
echo "--- no-match cases ---"

out=$(run_prompt "hello how are you")
if [ -z "$out" ]; then
    echo "  [PASS] 'hello how are you' → empty output (no match)"
    passed=$((passed+1))
else
    echo "  [FAIL] 'hello how are you' → expected empty output, got:"
    echo "  ${out:0:200}"
    failed=$((failed+1))
fi

# ── 7. No match: unrelated question ──────────────────────────────────────────

out=$(run_prompt "what time is it")
if [ -z "$out" ]; then
    echo "  [PASS] 'what time is it' → empty output (no match)"
    passed=$((passed+1))
else
    echo "  [FAIL] 'what time is it' → expected empty output, got:"
    echo "  ${out:0:200}"
    failed=$((failed+1))
fi

# ── 8. Both skills triggered ─────────────────────────────────────────────────

echo ""
echo "--- dual trigger ---"

out=$(run_prompt "find callers and refactor the function")
cbm_ok=0; serena_ok=0
echo "$out" | grep -qi "cbm-workflow"    && cbm_ok=1
echo "$out" | grep -qi "serena-workflow" && serena_ok=1

if [ "$cbm_ok" -eq 1 ] && [ "$serena_ok" -eq 1 ]; then
    echo "  [PASS] 'find callers and refactor the function' → cbm-workflow AND serena-workflow"
    passed=$((passed+1))
elif [ "$cbm_ok" -eq 0 ]; then
    echo "  [FAIL] 'find callers and refactor the function' → missing cbm-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
else
    echo "  [FAIL] 'find callers and refactor the function' → missing serena-workflow"
    echo "  Output: ${out:0:200}"
    failed=$((failed+1))
fi

# ── JSON output shape ────────────────────────────────────────────────────────

echo ""
echo "--- JSON output shape ---"

json_out=$(run_prompt "search code for authentication")

if assert_valid_json "$json_out" "output is valid JSON"; then
    passed=$((passed+1))
else
    failed=$((failed+1))
fi

if echo "$json_out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    echo "  [PASS] hookSpecificOutput.additionalContext present and non-empty"
    passed=$((passed+1))
else
    echo "  [FAIL] hookSpecificOutput.additionalContext missing or empty"
    echo "  Output: ${json_out:0:300}"
    failed=$((failed+1))
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: $passed passed, $failed failed"
echo ""

if [ "$failed" -gt 0 ]; then
    exit 1
fi
exit 0
