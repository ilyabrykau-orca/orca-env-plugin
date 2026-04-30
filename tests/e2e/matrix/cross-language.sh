#!/usr/bin/env bash
# E2E matrix test: Cross-language abstract prompt
# Tests that the CBM empty-fallback fix works across all language domains
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=2

echo "=== cross-language: Abstract performance prompt across multiple projects ==="

# Prompts designed to trigger empty CBM on first call (abstract language, not symbol names)
declare -A PROMPTS
PROMPTS[go-runtime]='Analyze memory usage patterns in orca-runtime-sensor/pkg/containermonitor/.
Focus on goroutine lifecycle and channel buffer sizing efficiency.
Do not modify any files. Output your analysis as text.'

PROMPTS[python-orca]='Review the database query patterns in orca/apps/core/ for N+1 query risks
and connection pool exhaustion scenarios.
Do not modify any files. Output your analysis as text.'

total_pass=0
total_fail=0

for domain in go-runtime python-orca; do
    echo ""
    echo "--- $domain ---"
    prompt="${PROMPTS[$domain]}"

    best=0
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  attempt $attempt/$MAX_RETRIES ($(date '+%H:%M:%S'))"
        transcript=$(launch_session "$prompt" "$HOME/src" 12 240)
        p=0

        if assert_no_native_on_code "$transcript" "$domain: no native on source"; then
            p=$((p+1))
        fi
        if assert_cbm_dominates_reads "$transcript" "$domain: CBM dominates reads"; then
            p=$((p+1))
        fi
        if assert_serena_only_for_edits "$transcript" "$domain: Serena only for edits"; then
            p=$((p+1))
        fi
        if assert_cbm_retries_on_empty "$transcript" "$domain: CBM retries on empty"; then
            p=$((p+1))
        fi

        if [ "$p" -gt "$best" ]; then
            best=$p
        fi
        [ "$p" -eq 4 ] && break
    done

    if [ "$best" -eq 4 ]; then
        echo "  [PASS] $domain: 4/4"
        total_pass=$((total_pass+1))
    else
        echo "  [FAIL] $domain: $best/4"
        total_fail=$((total_fail+1))
    fi
done

echo ""
echo "=== Cross-language result: $total_pass passed, $total_fail failed ==="
[ "$total_fail" -eq 0 ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED"; exit 1; }
