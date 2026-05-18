#!/usr/bin/env bash
# Replay assertions against recorded transcript fixtures.
# Output: per-fixture pass/fail matrix for all 4 routing assertions.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/assert-routing.sh"
set +e
set +u
set +o pipefail

FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# Each entry: fixture_basename:expected (pass|fail per assertion order)
# Order: native, cbm_dominates, serena_edits_only, cbm_retries_on_empty
expected_for() {
  case "$1" in
    cbm-dominates-transcript.json)    echo "pass pass pass pass" ;;
    cbm-empty-fallback-bad.json)      echo "pass fail fail fail" ;;
    cbm-empty-fallback-live.json)     echo "any any any any" ;;
    cbm-empty-pivots-good.json)       echo "pass pass pass pass" ;;
    cbm-empty-retries-good.json)      echo "pass pass pass pass" ;;
    cbm-empty-terminates-good.json)   echo "pass pass pass pass" ;;
    serena-dominates-transcript.json) echo "pass fail fail pass" ;; # cbm-retries vacuous pass: no tool_results in fixture
    *)                                echo "any any any any" ;;
  esac
}

assertions=(
  "assert_no_native_on_code:no-native-on-code"
  "assert_cbm_dominates_reads:cbm-dominates"
  "assert_serena_only_for_edits:serena-edits-only"
  "assert_cbm_retries_on_empty:cbm-retries-on-empty"
)

printf '%s\n' "===================================================================="
printf '%s\n' " E2E Fixture Replay: routing assertions vs recorded transcripts"
printf '%s\n' "===================================================================="
printf '\n'

total_runs=0
total_pass=0
total_fail=0
mismatch=0

# Header row
printf '%-42s' "fixture"
for a in "${assertions[@]}"; do
  short="${a##*:}"
  printf ' %-20s' "$short"
done
printf ' %s\n' "expectations"
printf '%s\n' "--------------------------------------------------------------------"

for f in "$FIXTURES_DIR"/*.json; do
  fname=$(basename "$f")
  transcript=$(cat "$f")
  expected=$(expected_for "$fname")
  read -r -a exp_arr <<< "$expected"

  printf '%-42s' "$fname"

  i=0
  for a in "${assertions[@]}"; do
    fn="${a%%:*}"
    out=$("$fn" "$transcript" "$fname" 2>&1)
    rc=$?
    total_runs=$((total_runs+1))

    if [ "$rc" -eq 0 ]; then
      status="PASS"; total_pass=$((total_pass+1))
    else
      status="FAIL"; total_fail=$((total_fail+1))
    fi

    exp="${exp_arr[$i]:-any}"
    indicator=""
    if [ "$exp" = "any" ]; then
      indicator=""
    elif [ "$exp" = "pass" ] && [ "$status" = "PASS" ]; then
      indicator="✓"
    elif [ "$exp" = "fail" ] && [ "$status" = "FAIL" ]; then
      indicator="✓"
    else
      indicator="✗"; mismatch=$((mismatch+1))
    fi

    printf ' %-20s' "${status}${indicator:+ $indicator}"
    i=$((i+1))
  done

  printf ' %s\n' "$expected"
done

printf '\n%s\n' "===================================================================="
printf 'Total runs: %d  passed: %d  failed: %d  expectation mismatches: %d\n' \
  "$total_runs" "$total_pass" "$total_fail" "$mismatch"
printf '%s\n' "===================================================================="
printf '\nLegend: ✓ matches expectation  ✗ DOES NOT match expectation  (blank = no expectation set)\n'

[ "$mismatch" -eq 0 ] && exit 0 || exit 1
