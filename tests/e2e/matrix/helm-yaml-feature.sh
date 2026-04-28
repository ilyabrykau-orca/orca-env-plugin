#!/usr/bin/env bash
# E2E matrix test: helm YAML feature — CONTROL CASE
# Native Read/Edit SHOULD be used on .yaml files (no routing blocks)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
passed=0
failed=0

echo "=== helm-yaml-feature (CONTROL): Add replicaCount to helm chart ==="

PROMPT='Do these steps in order:
1. Read the file helm-charts/values.yaml to see current configuration
2. Edit helm-charts/values.yaml to add a replicaCount field defaulting to 1
3. Run: helm lint helm-charts/ to verify the chart is valid'

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 6 120)
    tools=$(extract_tool_calls "$transcript")

    all_pass=true

    if echo "$tools" | grep -q "^Read$"; then
        echo "  [PASS] native Read used for YAML (correct — not blocked)"
    else
        echo "  [FAIL] native Read not used — tools: $(echo "$tools" | tr '\n' ' ')"
        all_pass=false
    fi

    if echo "$tools" | grep -q "^Edit$\|^Write$"; then
        echo "  [PASS] native Edit/Write used for YAML (correct — not blocked)"
    else
        echo "  [FAIL] native Edit/Write not used — tools: $(echo "$tools" | tr '\n' ' ')"
        all_pass=false
    fi

    if echo "$tools" | grep -q "Bash"; then
        echo "  [PASS] Bash used for helm lint"
    else
        echo "  [FAIL] Bash not used"
        all_pass=false
    fi

    if $all_pass; then
        passed=3
        break
    fi
done

if [ "$passed" -ge 2 ]; then
    echo "=== STATUS: PASSED ($passed/3 assertions) ==="
    exit 0
else
    echo "=== STATUS: FAILED ($passed/3 assertions) ==="
    exit 1
fi
