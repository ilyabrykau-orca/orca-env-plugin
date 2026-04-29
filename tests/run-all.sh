#!/usr/bin/env bash
# orca-env plugin test runner — v1.1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# --- timeout command (macOS lacks GNU timeout) ---
if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &>/dev/null; then
    TIMEOUT_CMD="gtimeout"
else
    # fallback: run without timeout
    TIMEOUT_CMD=""
fi

# --- defaults ---
UNIT_ONLY=true
INTEGRATION=false
VERBOSE=false
SINGLE_TEST=""
TIMEOUT=300

# --- arg parsing ---
usage() {
    cat <<'EOF'
Usage: run-all.sh [OPTIONS]

Options:
  --unit              Run unit tests only (default)
  --integration, -i   Include integration tests
  --verbose, -v       Show full test output
  --test, -t NAME     Run only the named test file
  --timeout SECONDS   Per-test timeout (default: 300)
  --help, -h          Show this help message

Examples:
  bash tests/run-all.sh --unit
  bash tests/run-all.sh --unit --test test-skills-lint.sh
  bash tests/run-all.sh --integration --verbose
  bash tests/run-all.sh --unit --timeout 60
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)           UNIT_ONLY=true; INTEGRATION=false; shift ;;
        --integration|-i) INTEGRATION=true; UNIT_ONLY=false; shift ;;
        --verbose|-v)     VERBOSE=true; shift ;;
        --test|-t)        SINGLE_TEST="$2"; shift 2 ;;
        --timeout)        TIMEOUT="$2"; shift 2 ;;
        --help|-h)        usage ;;
        *) echo "Unknown option: $1"; echo "Try --help for usage."; exit 1 ;;
    esac
done

# --- header ---
echo "========================================"
echo " orca-env plugin test suite"
echo "========================================"
echo "Plugin:  $PLUGIN_ROOT"
echo "Date:    $(date)"
echo "Options: unit_only=$UNIT_ONLY integration=$INTEGRATION verbose=$VERBOSE timeout=${TIMEOUT}s"
if [ -n "$SINGLE_TEST" ]; then
    echo "Filter:  $SINGLE_TEST"
fi
echo ""

# --- counters ---
passed=0; failed=0; skipped=0

# --- runner ---
run_test_file() {
    local f="$1"
    local name
    name=$(basename "$f")

    # filter by --test if given
    if [ -n "$SINGLE_TEST" ] && [ "$name" != "$SINGLE_TEST" ]; then
        skipped=$((skipped+1))
        return
    fi

    # guard: file must exist
    [ -f "$f" ] || { skipped=$((skipped+1)); return; }

    echo "--- $name ---"
    chmod +x "$f"

    local start_time end_time duration exit_code
    start_time=$(date +%s)

    local cmd=()
    if [ -n "$TIMEOUT_CMD" ]; then
        cmd=("$TIMEOUT_CMD" "$TIMEOUT")
    fi
    cmd+=(bash "$f")

    if $VERBOSE; then
        "${cmd[@]}" && exit_code=0 || exit_code=$?
    else
        "${cmd[@]}" >/dev/null 2>&1 && exit_code=0 || exit_code=$?
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    if [ "$exit_code" -eq 0 ]; then
        passed=$((passed+1))
        echo "[PASS] $name (${duration}s)"
    elif [ "$exit_code" -eq 124 ]; then
        failed=$((failed+1))
        echo "[FAIL] $name — TIMEOUT after ${TIMEOUT}s"
    else
        failed=$((failed+1))
        echo "[FAIL] $name (${duration}s, exit=$exit_code)"
    fi
    echo ""
}

# --- unit tests ---
echo "=== Unit Tests (no LLM) ==="
for f in "${SCRIPT_DIR}/unit"/test-*.sh; do
    [ -f "$f" ] || continue
    run_test_file "$f"
done

# --- integration tests ---
if [ "$INTEGRATION" = true ]; then
    if ! command -v claude &>/dev/null; then
        echo "WARNING: claude CLI not found, skipping integration tests"
    else
        echo "=== Integration Tests (LLM) ==="
        for f in "${SCRIPT_DIR}/integration"/test-*.sh; do
            [ -f "$f" ] || continue
            run_test_file "$f"
        done
    fi
fi

# --- summary ---
echo "========================================"
echo "Passed: $passed  Failed: $failed  Skipped: $skipped"
echo "========================================"
if [ $failed -eq 0 ]; then
    echo "STATUS: PASSED"
    exit 0
else
    echo "STATUS: FAILED"
    exit 1
fi
