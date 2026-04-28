#!/usr/bin/env bash
# E2E matrix test: sensor Go feature — Add --dry-run flag to collector CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
REQUIRED_PASS=3
passed=0
failed=0

echo "=== sensor-go-feature: Add --dry-run flag to collector CLI ==="

run_segment_with_retry() {
    local segment_name="$1"
    local prompt="$2"
    shift 2
    local attempt
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [$segment_name] attempt $attempt/$MAX_RETRIES"
        local transcript
        transcript=$(launch_session "$prompt" "$HOME/src" 3 120)
        local segment_pass=true
        for assertion in "$@"; do
            eval "$assertion" || segment_pass=false
        done
        if $segment_pass; then
            passed=$((passed+1))
            return 0
        fi
    done
    failed=$((failed+1))
    return 1
}

run_segment_with_retry "explore" \
    "In the sensors repository, explore the collector CLI entrypoint — find all files that define CLI flags or commands. Use codebase-memory tools." \
    'assert_tool_used "$transcript" "codebase" "CBM used for exploration"' \
    'assert_no_native_on_code "$transcript" "no native tools on source during explore"' || true

run_segment_with_retry "plan" \
    "In the sensors repository, find all symbols that reference the collector CLI flag parsing so we can plan adding a --dry-run flag." \
    'assert_tool_used "$transcript" "find_referencing_symbols" "find_referencing_symbols used in plan"' || true

run_segment_with_retry "edit" \
    "In the sensors repository, add a --dry-run flag to the collector CLI using Serena tools." \
    'assert_tool_used "$transcript" "serena" "Serena used for edit"' \
    'assert_no_native_on_code "$transcript" "no native Edit on source files"' || true

run_segment_with_retry "verify" \
    "In the sensors repository, run the tests to verify the --dry-run flag addition did not break anything." \
    'assert_tool_used "$transcript" "Bash" "Bash used for verification"' || true

echo ""
echo "=== Result: $passed passed, $failed failed (required $REQUIRED_PASS) ==="

if [ "$passed" -ge "$REQUIRED_PASS" ]; then
    echo "STATUS: PASSED"
    exit 0
else
    echo "STATUS: FAILED"
    exit 1
fi
