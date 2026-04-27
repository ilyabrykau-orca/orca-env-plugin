#!/usr/bin/env bash
# PostToolUse: record mcp__serena__find_referencing_symbols calls into per-session state.
# Used by pre-serena-edit-guard.sh to verify find_refs was called before edits.
set -euo pipefail

INPUT=$(cat)
[[ "$(jq -r '.tool_name // empty' <<<"$INPUT")" != "mcp__serena__find_referencing_symbols" ]] && exit 0
[[ "$(jq -r '.tool_response.is_error // false' <<<"$INPUT")" == "true" ]] && exit 0

REL_PATH=$(jq -r '.tool_input.relative_path // empty' <<<"$INPUT")
SESSION_ID=$(jq -r '.session_id // "unknown"' <<<"$INPUT")
[[ -z "$REL_PATH" ]] && exit 0

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}/state}"
mkdir -p "$STATE_DIR"

STATE_FILE="$STATE_DIR/refs-traced.${SESSION_ID}.json"
LOCK_FILE="${STATE_FILE}.lock"

_do_update() {
  if [[ ! -f "$STATE_FILE" ]]; then
    jq -n --arg sid "$SESSION_ID" '{session_id: $sid, traced: {}}' > "$STATE_FILE"
  fi
  TMP=$(mktemp)
  jq --arg p "$REL_PATH" --arg ts "$(date +%s)" '.traced[$p] = ($ts | tonumber)' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
}

if command -v flock >/dev/null 2>&1; then
  (exec 9>"$LOCK_FILE"; flock 9; _do_update)
else
  _do_update
fi
exit 0
