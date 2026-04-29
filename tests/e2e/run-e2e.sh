#!/usr/bin/env bash
# E2E test runner: parallel project matrix
# Usage: E2E=1 bash tests/e2e/run-e2e.sh
set -euo pipefail

if [ "${E2E:-0}" != "1" ]; then
    echo "E2E tests skipped (set E2E=1 to run)"
    exit 0
fi

if ! command -v claude &>/dev/null; then
    echo "ERROR: claude CLI not found"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "$RESULTS_DIR"

echo "========================================"
echo " E2E Test Matrix"
echo "========================================"
echo "Date: $(date)"
echo "Results: $RESULTS_DIR"
echo ""

pids=()
tests=()

for test_file in "${SCRIPT_DIR}/matrix"/*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file" .sh)
    tests+=("$test_name")
    echo "Launching: $test_name"
    bash "$test_file" > "${RESULTS_DIR}/${test_name}.log" 2>&1 &
    pids+=($!)
done

echo ""
echo "Waiting for ${#pids[@]} parallel tests..."
echo ""

failures=0
for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
        echo "[PASS] ${tests[$i]}"
    else
        echo "[FAIL] ${tests[$i]} (see ${RESULTS_DIR}/${tests[$i]}.log)"
        failures=$((failures+1))
    fi
done

echo ""
echo "========================================"
echo "Matrix: ${#tests[@]} projects, $failures failures"
echo "========================================"

if [ $failures -eq 0 ]; then
    echo "STATUS: PASSED"
    exit 0
else
    echo "STATUS: FAILED"
    exit 1
fi
