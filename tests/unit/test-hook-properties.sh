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

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
