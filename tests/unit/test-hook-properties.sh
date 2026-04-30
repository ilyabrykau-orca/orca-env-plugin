#!/usr/bin/env bash
# Unit test: hook behavioural properties (exit code, stderr, idempotency, perf)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

HOOK="${PLUGIN_ROOT}/hooks/session-start"
passed=0; failed=0

echo "=== Unit: hook properties ==="
echo ""

# Test: exit code 0 from known project
(cd "$SANDBOX/src/orca" && bash "$HOOK" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] exit code 0 from known project"
    passed=$((passed+1))
else
    echo "  [FAIL] exit code 0 from known project (got $rc)"
    failed=$((failed+1))
fi

# Test: exit code 0 from unknown dir
(cd /tmp && bash "$HOOK" >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] exit code 0 from unknown dir"
    passed=$((passed+1))
else
    echo "  [FAIL] exit code 0 from unknown dir (got $rc)"
    failed=$((failed+1))
fi

# Test: no stderr output
stderr=$(cd "$SANDBOX/src/orca" && bash "$HOOK" 2>&1 >/dev/null)
if [ -z "$stderr" ]; then
    echo "  [PASS] no stderr output"
    passed=$((passed+1))
else
    echo "  [FAIL] no stderr output"
    echo "  stderr: ${stderr:0:200}"
    failed=$((failed+1))
fi

# Test: idempotency (run twice, compare outputs)
out1=$(cd "$SANDBOX/src/orca" && bash "$HOOK" 2>/dev/null)
out2=$(cd "$SANDBOX/src/orca" && bash "$HOOK" 2>/dev/null)
if [ "$out1" = "$out2" ]; then
    echo "  [PASS] idempotent (two runs produce identical output)"
    passed=$((passed+1))
else
    echo "  [FAIL] idempotent (two runs produce identical output)"
    echo "  outputs differ"
    failed=$((failed+1))
fi

# Test: performance < 500ms
# NOTE: python3 startup adds ~150ms to measured time. The 500ms threshold
# accounts for this overhead. On macOS, date +%s%3N is not available.
start_ms=$(python3 -c "import time; print(int(time.time()*1000))")
(cd "$SANDBOX/src/orca" && bash "$HOOK" >/dev/null 2>&1)
end_ms=$(python3 -c "import time; print(int(time.time()*1000))")
elapsed=$((end_ms - start_ms))
if [ "$elapsed" -lt 500 ]; then
    echo "  [PASS] performance: ${elapsed}ms < 500ms"
    passed=$((passed+1))
else
    echo "  [FAIL] performance: ${elapsed}ms >= 500ms"
    failed=$((failed+1))
fi

HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"

echo ""
echo "--- hooks.json: SessionStart entries ---"

SS_COUNT=$(jq '.hooks.SessionStart | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$SS_COUNT" = "2" ]; then
    echo "  [PASS] hooks.json has 2 SessionStart entries"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json has $SS_COUNT SessionStart entries (expected 2)"
    failed=$((failed+1))
fi

echo ""
echo "--- hooks.json: PreToolUse entries ---"

PT_COUNT=$(jq '.hooks.PreToolUse | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$PT_COUNT" = "3" ]; then
    echo "  [PASS] hooks.json has 3 PreToolUse entries"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json has $PT_COUNT PreToolUse entries (expected 3)"
    failed=$((failed+1))
fi

# Check pre-tool-router is referenced in PreToolUse
PT_ROUTER=$(jq -r '[.hooks.PreToolUse[].hooks[].command] | map(select(test("pre-tool-router"))) | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$PT_ROUTER" -ge 1 ] 2>/dev/null; then
    echo "  [PASS] hooks.json PreToolUse references pre-tool-router"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json PreToolUse does not reference pre-tool-router"
    failed=$((failed+1))
fi

# Check rtk-rewrite-bash is referenced in PreToolUse
PT_RTK=$(jq -r '[.hooks.PreToolUse[].hooks[].command] | map(select(test("rtk-rewrite-bash"))) | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$PT_RTK" -ge 1 ] 2>/dev/null; then
    echo "  [PASS] hooks.json PreToolUse references rtk-rewrite-bash"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json PreToolUse does not reference rtk-rewrite-bash"
    failed=$((failed+1))
fi

echo ""
echo "--- new hook scripts exist ---"

HOOK_COMPACT="${PLUGIN_ROOT}/hooks/session-start-compact"
if [ -f "$HOOK_COMPACT" ]; then
    echo "  [PASS] session-start-compact script exists"
    passed=$((passed+1))
else
    echo "  [FAIL] session-start-compact script missing"
    failed=$((failed+1))
fi

HOOK_RTK="${PLUGIN_ROOT}/hooks/rtk-rewrite-bash"
if [ -f "$HOOK_RTK" ]; then
    echo "  [PASS] rtk-rewrite-bash script exists"
    passed=$((passed+1))
else
    echo "  [FAIL] rtk-rewrite-bash script missing"
    failed=$((failed+1))
fi

# Verify session-start-compact is referenced in hooks.json SessionStart
SC_REF=$(jq -r '[.hooks.SessionStart[].hooks[].command] | map(select(test("session-start-compact"))) | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$SC_REF" -ge 1 ] 2>/dev/null; then
    echo "  [PASS] session-start-compact referenced in hooks.json"
    passed=$((passed+1))
else
    echo "  [FAIL] session-start-compact not referenced in hooks.json"
    failed=$((failed+1))
fi

# Verify rtk-rewrite-bash is referenced in hooks.json PreToolUse (already checked above, but confirm via script existence cross-check)
RTK_REF=$(jq -r '[.hooks.PreToolUse[].hooks[].command] | map(select(test("rtk-rewrite-bash"))) | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$RTK_REF" -ge 1 ] 2>/dev/null; then
    echo "  [PASS] rtk-rewrite-bash referenced in hooks.json"
    passed=$((passed+1))
else
    echo "  [FAIL] rtk-rewrite-bash not referenced in hooks.json"
    failed=$((failed+1))
fi

echo ""
echo "--- hooks.json: all PreToolUse hooks have timeout ---"

NO_TIMEOUT=$(jq '[.hooks.PreToolUse[].hooks[] | select(.timeout == null)] | length' "$HOOKS_JSON" 2>/dev/null)
if [ "$NO_TIMEOUT" = "0" ]; then
    echo "  [PASS] all PreToolUse hooks have timeout values"
    passed=$((passed+1))
else
    echo "  [FAIL] $NO_TIMEOUT PreToolUse hook(s) missing timeout"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
