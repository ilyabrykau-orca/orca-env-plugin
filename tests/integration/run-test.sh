#!/usr/bin/env bash
# Integration test driver: runs claude -p with plugin loaded
# Usage: ./run-test.sh <test-name> <prompt-file> <work-dir>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TEST_NAME="$1"
PROMPT_FILE="$2"
WORK_DIR="${3:-$PLUGIN_ROOT}"

OUTPUT_DIR="/tmp/orca-env-tests/$(date +%s)/${TEST_NAME}"
mkdir -p "$OUTPUT_DIR"

PROMPT=$(cat "$PROMPT_FILE")
LOG_FILE="${OUTPUT_DIR}/output.json"

echo "=== Integration: ${TEST_NAME} ==="
echo "Working dir: $WORK_DIR"
echo "Prompt: $(head -1 "$PROMPT_FILE")"
echo ""

cd "$WORK_DIR"
timeout 180 claude -p "$PROMPT" \
    --plugin-dir "$PLUGIN_ROOT" \
    --dangerously-skip-permissions \
    --max-turns 5 \
    --output-format stream-json \
    > "$LOG_FILE" 2>&1 || true

echo "Log: $LOG_FILE"
cat "$LOG_FILE"
