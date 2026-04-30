#!/usr/bin/env bash
# E2E matrix test: orca Python feature — read-only analysis via CBM-first routing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3

echo "=== orca-python-feature: Analyze User model and its references ==="

PROMPT='Analyze the User model in the orca Django project.
Find where it is defined, what fields it has, and which modules
reference it most frequently.
Do not modify any files. Output your analysis as text.'

best=0
best_detail=""
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 8 180)
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

    if assert_tool_used "$transcript" "codebase-memory-mcp" "CBM was used at all"; then
        p=$((p+1))
    fi
    detail+=",cbm_used=$?"

    if [ "$p" -gt "$best" ]; then
        best=$p
        best_detail="$detail"
    fi
    [ "$p" -eq 4 ] && break
done

echo ""
echo "=== Result: $best/4 assertions passed (all 4 required) ==="
[ "$best" -eq 4 ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED ($best_detail)"; exit 1; }
