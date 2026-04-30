#!/usr/bin/env bash
# E2E matrix test: helm YAML feature — CONTROL CASE
# Native Read/Edit/Bash SHOULD be used on .yaml files (no routing blocks)
# No CBM dominance assertion — helm is YAML, outside CBM scope
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3

echo "=== helm-yaml-feature (CONTROL): Analyze replicaCount in helm chart ==="

PROMPT='Read the helm chart values file at helm-charts/values.yaml.
Check if a replicaCount field exists and what its current default is.
If it is missing, describe where it should be added.
Do not modify any files. Output your analysis as text.'

best=0
best_detail=""
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 6 120)
    tools=$(extract_tool_calls "$transcript")
    p=0
    detail=""

    # Control case: native Read SHOULD be used on yaml
    if echo "$tools" | grep -qE "^(Read|Bash)$"; then
        echo "  [PASS] native Read or Bash used for YAML"
        p=$((p+1))
    else
        echo "  [FAIL] native Read/Bash not used — tools: $(echo "$tools" | tr '\n' ' ')"
    fi
    detail+="native_yaml=$?"

    # No MCP needed for pure YAML work
    if assert_tool_not_used "$transcript" "codebase-memory-mcp" "no CBM needed for YAML"; then
        p=$((p+1))
    fi
    detail+=",no_cbm=$?"

    # Serena should not be used for YAML reads either
    if assert_serena_only_for_edits "$transcript" "Serena only for edits (if used at all)"; then
        p=$((p+1))
    fi
    detail+=",serena_edit=$?"

    if [ "$p" -gt "$best" ]; then
        best=$p
        best_detail="$detail"
    fi
    [ "$p" -eq 3 ] && break
done

echo ""
echo "=== Result: $best/3 assertions passed (all 3 required) ==="
[ "$best" -eq 3 ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED ($best_detail)"; exit 1; }
