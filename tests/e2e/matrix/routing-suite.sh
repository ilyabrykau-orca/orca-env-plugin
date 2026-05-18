#!/usr/bin/env bash
# E2E matrix test: routing-suite — five prompts distilled from real W20 native-bypass
# sessions in ~/.claude/projects/-Users-ilyabrykau-src.
#
# Cited sessions (each contributes one task; prompt is a focused slice of the
# session's real text, keyed to the specific file that got Read-bypassed):
#   66d800bd-4e25 — rt_fast_asset Python read spam (breach_detection/services/...)
#   7e3d095e-d061 — orca-env-plugin TS handlers read spam
#   7a2867ae-d483 — runtime-sensor bpfstream zero-alloc review (Go)
#   0eff2b68-29d4 — runtime-sensor pkg/http protocol tests read spam (Go)
#   e78bcf80-db76 — sensor-management bu_cache_refresher bug verify (Go)
#
# Each task runs through launch-session.sh (real `claude -p`, plugin-dir = orca-env-plugin),
# and is scored against the same 6 routing asserts:
#   1. no native tools on source files
#   2. CBM dominates reads
#   3. Serena only for edits
#   4. CBM was used at all
#   5. tool-call budget
#   6. no subagent spawning (subagents' tool calls are invisible to the main transcript,
#      so Agent() on a trivial lookup is itself a routing bypass)
# Suite passes iff every task scores 6/6 on its best attempt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES="${ROUTING_SUITE_RETRIES:-2}"
CWD="${ROUTING_SUITE_CWD:-$HOME/src}"
RESULTS_DIR="${SCRIPT_DIR}/../results"
mkdir -p "$RESULTS_DIR"
SUITE_LOG="${RESULTS_DIR}/routing-suite.tsv"
: > "$SUITE_LOG"

# Per-task: name | prompt | max_turns | max_time | call_budget
# Prompts are deliberately short and bounded so simple lookups can complete in ≤3 turns;
# turn budgets are tighter than other matrix files to force CBM-first behavior rather
# than 8-turn native-Read spelunking. The call_budget feeds assert_max_tool_calls and
# drives ROUTING.md toward one-shot lookups (vs search→snippet→verify chains).
run_task() {
    local name="$1" prompt="$2" max_turns="$3" max_time="$4" call_budget="$5"

    echo ""
    echo "=== routing-suite/${name} ==="
    local best=0 best_detail=""
    for attempt in $(seq 1 "$MAX_RETRIES"); do
        echo "  attempt ${attempt}/${MAX_RETRIES} (max_turns=${max_turns}, max_time=${max_time}s, budget=${call_budget})"
        local transcript
        transcript=$(launch_session "$prompt" "$CWD" "$max_turns" "$max_time")

        local p=0 detail=""
        if assert_no_native_on_code "$transcript" "no native tools on source"; then
            p=$((p+1)); detail+="native=ok,"
        else
            detail+="native=FAIL,"
        fi
        if assert_cbm_dominates_reads "$transcript" "CBM dominates reads"; then
            p=$((p+1)); detail+="cbm_dom=ok,"
        else
            detail+="cbm_dom=FAIL,"
        fi
        if assert_serena_only_for_edits "$transcript" "Serena only for edits"; then
            p=$((p+1)); detail+="serena_edit=ok,"
        else
            detail+="serena_edit=FAIL,"
        fi
        if assert_tool_used "$transcript" "codebase-memory-mcp" "CBM was used at all"; then
            p=$((p+1)); detail+="cbm_used=ok,"
        else
            detail+="cbm_used=FAIL,"
        fi
        if assert_max_tool_calls "$transcript" "$call_budget" "tool-call budget"; then
            p=$((p+1)); detail+="budget=ok,"
        else
            detail+="budget=FAIL,"
        fi
        # Subagent spawning on simple lookups bypasses CBM/Serena routing since
        # subagents inherit native tools and their calls are invisible to this transcript.
        if assert_tool_not_used "$transcript" "^Agent$" "no subagent spawning"; then
            p=$((p+1)); detail+="no_subagent=ok"
        else
            detail+="no_subagent=FAIL"
        fi

        if [ "$p" -gt "$best" ]; then
            best=$p
            best_detail="$detail"
        fi
        [ "$p" -eq 6 ] && break
    done

    printf '%s\t%d\t%s\n' "$name" "$best" "$best_detail" >> "$SUITE_LOG"
    echo "  -> ${name}: ${best}/6  (${best_detail})"
    [ "$best" -eq 6 ] && return 0 || return 1
}

# --- Task 1: rt_fast_asset Python — derived from 66d800bd ---
# Real session asked for a file-by-file CLEAN CODE pass on rt_fast_asset; the model
# answered with native Read of pipeline.py/builders.py/etc. Distilled lookup:
P1='List the public functions defined in
orca/breach_detection/services/rt_fast_asset/pipeline.py.
Read-only — do not modify anything.'

# --- Task 2: orca-env-plugin TS handlers — derived from 7e3d095e ---
# Real session asked to "proceed from last state" on env-plugin; model native-Read'd
# every src/handlers/*.ts. Distilled lookup — must force a real code read (not
# answer from training/--plugin-dir context):
P2='Show me the implementation of the SessionStart hook handler in
orca-env-plugin/src/handlers/session-start.ts. Include the full function body so
I can see how it builds its system-reminder payload. Read-only.'

# --- Task 3: runtime-sensor bpfstream zero-alloc — derived from 7a2867ae ---
# Real session asked to review allocations in base_bpf_event_stream.go for zero-alloc.
P3='Show me the allocation hot paths in
orca-runtime-sensor/eventsource/bpfstream/base_bpf_event_stream.go.
Identify functions that allocate per-event. Read-only.'

# --- Task 4: runtime-sensor http protocol tests — derived from 0eff2b68 ---
# Real session asked to review e2e failures on feat/ssl-zero-alloc; model native-Read'd
# every pkg/http/protocol_*_test.go. Distilled lookup:
P4='List the test functions in orca-runtime-sensor/pkg/http/ that exercise
HTTP/2 protocol recovery. Read-only.'

# --- Task 5: sensor-management bu_cache_refresher bug — derived from e78bcf80 ---
# Real session asked to verify a TTL bug at bu_cache_refresher.go:53.
P5='Verify the TTL bug claim at
orca-sensor/services/sensor-management/server/bu_cache_refresher.go line 53:
the refresher reportedly hard-codes config.DefaultBusinessUnitCacheTTL instead of
honoring cfg.BusinessUnitCacheTTL. Read-only.'

failures=0
# Per-task call budgets: simple single-file lookups get 3 (CBM + answer, with one slack call);
# 03-bpfstream is a legitimately broader hot-path review across multiple files so gets 8.
run_task "01-rt-fast-asset"       "$P1" 4 150 3 || failures=$((failures+1))
run_task "02-env-plugin-handlers" "$P2" 4 150 3 || failures=$((failures+1))
run_task "03-bpfstream-zeroalloc" "$P3" 5 180 8 || failures=$((failures+1))
run_task "04-http-protocol-tests" "$P4" 5 180 3 || failures=$((failures+1))
run_task "05-bu-cache-refresher"  "$P5" 5 180 3 || failures=$((failures+1))

echo ""
echo "=== routing-suite: ${failures} task(s) failed (of 5 tasks, 6 asserts each) ==="
echo "    detailed scores -> ${SUITE_LOG}"
[ "$failures" -eq 0 ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED"; exit 1; }
