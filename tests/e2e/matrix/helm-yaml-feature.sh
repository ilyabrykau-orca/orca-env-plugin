#!/usr/bin/env bash
# E2E matrix test: helm YAML feature — Add replicaCount to helm chart
# CONTROL CASE: native Read/Edit SHOULD be used on .yaml files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

MAX_RETRIES=3
REQUIRED_PASS=3
passed=0
failed=0

echo "=== helm-yaml-feature (CONTROL): Add replicaCount to helm chart ==="

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
    "In the helm chart repository, read the values.yaml and chart definition files to understand the current configuration structure." \
    'assert_tool_used "$transcript" "Read" "native Read used for YAML exploration"' || true

run_segment_with_retry "plan" \
    "In the helm chart repository, look at the existing deployment template to understand where replicaCount should be added." \
    '' || true

run_segment_with_retry "edit" \
    "In the helm chart repository, add a replicaCount field to values.yaml and reference it in the deployment template." \
    'assert_tool_used "$transcript" "Edit" "native Edit used for YAML modification"' || true

run_segment_with_retry "verify" \
    "In the helm chart repository, run helm lint or helm template to verify the chart is still valid after adding replicaCount." \
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
