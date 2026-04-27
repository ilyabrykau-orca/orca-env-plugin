#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${1:-$(pwd)}"
PROMPTS="${2:-$PLUGIN_ROOT/tests/e2e/prompts.json}"
RUNS="${RUNS:-3}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"
REPO="${REPO:-/tmp/e2e-test-repo}"

mkdir -p "$REPO/src/app" "$REPO/src/service" "$REPO/vendor" "$REPO/docs"

count=0; failed=0
while IFS= read -r prompt_obj; do
  id=$(jq -r '.id' <<<"$prompt_obj")
  raw_prompt=$(jq -r '.prompt' <<<"$prompt_obj")
  prompt="${raw_prompt//__REPO__/$REPO}"
  runs=$(jq -r --arg d "$RUNS" '.runs // $d' <<<"$prompt_obj")

  for _ in $(seq 1 "$runs"); do
    count=$((count+1))
    transcript=$(mktemp)
    claude -p "$prompt" \
      --model "$MODEL" \
      --permission-mode default \
      --setting-sources project \
      --output-format stream-json \
      --verbose \
      --mcp-config "$PLUGIN_ROOT/tests/.mcp.json" \
      --append-system-prompt "Test harness: obey plugin routing. Execute the task." \
      > "$transcript" 2>&1 || true

    if ! python3 "$PLUGIN_ROOT/tests/e2e/assert-tools.py" \
           --transcript "$transcript" \
           --spec "$prompt_obj" \
           --repo "$REPO"; then
      echo "FAIL e2e $id" >&2
      failed=$((failed+1))
    else
      echo "PASS e2e $id"
    fi
    rm -f "$transcript"
  done
done < <(jq -c '.[]' "$PROMPTS")

echo ""
echo "[e2e] $((count-failed))/$count passed" >&2
[[ "$failed" -eq 0 ]]
