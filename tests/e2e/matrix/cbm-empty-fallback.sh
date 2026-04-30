#!/usr/bin/env bash
# E2E matrix test: CBM empty-result fallback behavior
# Tests that when CBM returns empty results, Claude retries CBM with
# different params rather than falling back to Serena reads.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3

echo "=== cbm-empty-fallback: Abstract prompt triggers empty CBM, verifies retry behavior ==="

# This prompt uses abstract language that won't match concrete symbol names
# in CBM's index. Words like "performance", "allocation hot path" are not
# function names — CBM's first search_code will likely return empty.
PROMPT='Find performance issues in
orca-runtime-sensor/pkg/containermonitor/monitor.go.
Look for allocation hot paths and recommend changes to reduce
steady-state allocations.
Do not modify any files. Output your analysis as text.'

best=0
best_detail=""
best_transcript=""
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES ($(date '+%H:%M:%S'))"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 12 240)
    p=0
    detail=""

    if assert_no_native_on_code "$transcript" "no native tools on source"; then
        p=$((p+1))
    fi
    detail+="native=$?"

    if assert_cbm_dominates_reads "$transcript" "CBM dominates reads"; then
        p=$((p+1))
    fi
    detail+=",cbm_dom=$?"

    if assert_serena_only_for_edits "$transcript" "Serena only for edits"; then
        p=$((p+1))
    fi
    detail+=",serena_edit=$?"

    if assert_cbm_retries_on_empty "$transcript" "CBM retries on empty"; then
        p=$((p+1))
    fi
    detail+=",cbm_retry=$?"

    if [ "$p" -gt "$best" ]; then
        best=$p
        best_detail="$detail"
        best_transcript="$transcript"
    fi
    [ "$p" -eq 4 ] && break
done

# Save transcript for inspection regardless of outcome
RESULTS_DIR="${SCRIPT_DIR}/../results"
mkdir -p "$RESULTS_DIR"
echo "$best_transcript" > "${RESULTS_DIR}/cbm-empty-fallback.log"

# Save as fixture if it's a live failure
if [ "$best" -lt 4 ]; then
    echo "$best_transcript" | jq '.' > "${SCRIPT_DIR}/../fixtures/cbm-empty-fallback-live.json" 2>/dev/null || true
fi

echo ""
echo "=== Result: $best/4 assertions passed (all 4 required) ==="
[ "$best" -eq 4 ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED ($best_detail)"; exit 1; }
