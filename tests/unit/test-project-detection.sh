#!/usr/bin/env bash
# Unit test: session-start binary project detection
# Tests binary output from different $PWD values.
# Note: orca-unified detection requires the real ~/src path (not sandbox),
# because the binary compares against the actual HOME-based SRC_PREFIX.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

run_test() {
    local dir="$1"
    local expected_project="$2"
    local test_name="$3"
    local output
    output=$(cd "$dir" 2>/dev/null && echo '{}' | "$BINARY" session-start 2>/dev/null || echo '{"error":"hook_failed"}')
    if [ -n "$expected_project" ]; then
        if assert_contains "$output" "activate_project.*$expected_project|$expected_project.*activate_project" "$test_name"; then
            passed=$((passed+1))
        else
            failed=$((failed+1))
        fi
    else
        if assert_not_contains "$output" "SERENA WORKSPACE DETECTED" "$test_name (no activation expected)"; then
            passed=$((passed+1))
        else
            failed=$((failed+1))
        fi
    fi
}

echo "=== Unit: project detection ==="
echo ""

# orca-unified: must use the real ~/src path (binary matches against $HOME/src/)
REAL_SRC="${HOME}/src"
if [ -d "$REAL_SRC" ]; then
    run_test "$REAL_SRC"                            "orca-unified"          "~/src → orca-unified (real path)"
else
    echo "  [SKIP] ~/src not found — skipping orca-unified test"
fi

# Sandbox-based tests: these use cwd.includes("/<dir>") matching
run_test "$SANDBOX/src/orca"                    "orca"                  "orca/ → orca"
run_test "$SANDBOX/src/orca/base_api"           "orca"                  "orca subdir → orca"
run_test "$SANDBOX/src/orca-sensor"             "orca-sensor"           "orca-sensor/ → orca-sensor"
run_test "$SANDBOX/src/orca-sensor/pkg"         "orca-sensor"           "orca-sensor subdir → orca-sensor"
run_test "$SANDBOX/src/orca-runtime-sensor"     "orca-runtime-sensor"   "runtime-sensor/ → orca-runtime-sensor"
run_test "$SANDBOX/src/helm-charts"             "helm-charts"           "helm-charts/ → helm-charts"
run_test "/tmp"                                 ""                      "/tmp → no activation"
run_test "$SANDBOX"                             ""                      "sandbox root → no activation"

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
