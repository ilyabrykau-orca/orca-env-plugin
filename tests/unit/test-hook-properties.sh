#!/usr/bin/env bash
# Unit test: binary behavioural properties (exit code, stderr, idempotency, perf)
# v2: uses dist/claude-toolkit binary
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

echo "=== Unit: hook properties ==="
echo ""

# Test: exit code 0 from known project
(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] exit code 0 from known project"
    passed=$((passed+1))
else
    echo "  [FAIL] exit code 0 from known project (got $rc)"
    failed=$((failed+1))
fi

# Test: exit code 0 from unknown dir
(cd /tmp && echo '{}' | "$BINARY" session-start >/dev/null 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] exit code 0 from unknown dir"
    passed=$((passed+1))
else
    echo "  [FAIL] exit code 0 from unknown dir (got $rc)"
    failed=$((failed+1))
fi

# Test: no stderr output for session-start
stderr=$(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start 2>&1 >/dev/null)
if [ -z "$stderr" ]; then
    echo "  [PASS] no stderr output"
    passed=$((passed+1))
else
    echo "  [FAIL] unexpected stderr output"
    echo "  stderr: ${stderr:0:200}"
    failed=$((failed+1))
fi

# Test: idempotency (run twice, compare outputs)
out1=$(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start 2>/dev/null)
out2=$(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start 2>/dev/null)
if [ "$out1" = "$out2" ]; then
    echo "  [PASS] idempotent (two runs produce identical output)"
    passed=$((passed+1))
else
    echo "  [FAIL] not idempotent (two runs produce different output)"
    echo "  outputs differ"
    failed=$((failed+1))
fi

# Test: performance < 500ms
start_ms=$(python3 -c "import time; print(int(time.time()*1000))")
(cd "$SANDBOX/src/orca" && echo '{}' | "$BINARY" session-start >/dev/null 2>&1)
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
