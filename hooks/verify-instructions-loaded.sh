#!/usr/bin/env bash
# InstructionsLoaded: record when CLAUDE.md with tool_routing block actually loads.
# Observability-only; cannot block. Used by tests to verify the routing block loaded.
set -euo pipefail

INPUT=$(cat)
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}/state}"
mkdir -p "$STATE_DIR"

FILE=$(jq -r '.file_path // empty' <<<"$INPUT")
REASON=$(jq -r '.load_reason // empty' <<<"$INPUT")
TS=$(date -u +%FT%TZ)
[[ -z "$FILE" ]] && exit 0

printf '{"ts":"%s","file":"%s","reason":"%s"}\n' "$TS" "$FILE" "$REASON" \
  >> "$STATE_DIR/instructions-loaded.jsonl"

if [[ "$(basename "$FILE")" == "CLAUDE.md" ]] && grep -q "<tool_routing>" "$FILE" 2>/dev/null; then
  jq -n --arg f "$FILE" --arg r "$REASON" --arg ts "$TS" \
    '{file: $f, load_reason: $r, ts: $ts}' \
    > "$STATE_DIR/last-routing-load.json"
fi
exit 0
