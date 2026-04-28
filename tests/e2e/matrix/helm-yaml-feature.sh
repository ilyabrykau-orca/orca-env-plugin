#!/usr/bin/env bash
# E2E matrix test: helm YAML feature — CONTROL CASE
# Native Read/Edit/Bash SHOULD be used on .yaml files (no routing blocks)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
REQUIRED_PASS=2

echo "=== helm-yaml-feature (CONTROL): Add replicaCount to helm chart ==="

PROMPT='Do these steps in order:
1. Read the file helm-charts/values.yaml to see current configuration
2. Edit helm-charts/values.yaml to add a replicaCount field defaulting to 1
3. Run: helm lint helm-charts/ to verify the chart is valid'

best=0
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  attempt $attempt/$MAX_RETRIES"
    transcript=$(launch_session "$PROMPT" "$HOME/src" 6 120)
    tools=$(extract_tool_calls "$transcript")
    p=0

    # Control case: native tools SHOULD be used on yaml
    if echo "$tools" | grep -q "^Read$"; then
        echo "  [PASS] native Read used for YAML"
        p=$((p+1))
    else
        echo "  [FAIL] native Read not used — tools: $(echo "$tools" | tr '\n' ' ')"
    fi

    # Model may use Edit, Write, or Bash (sed/echo) to modify yaml — all are valid
    if echo "$tools" | grep -qE "^Edit$|^Write$|^Bash$"; then
        echo "  [PASS] file modification tool used (Edit/Write/Bash)"
        p=$((p+1))
    else
        echo "  [FAIL] no modification tool used"
    fi

    if echo "$tools" | grep -q "Bash"; then
        echo "  [PASS] Bash used"
        p=$((p+1))
    else
        echo "  [FAIL] Bash not used"
    fi

    [ "$p" -gt "$best" ] && best=$p
    [ "$p" -ge "$REQUIRED_PASS" ] && break
done

echo ""
echo "=== Result: $best/3 assertions passed (required $REQUIRED_PASS) ==="
[ "$best" -ge "$REQUIRED_PASS" ] && { echo "STATUS: PASSED"; exit 0; } || { echo "STATUS: FAILED"; exit 1; }
