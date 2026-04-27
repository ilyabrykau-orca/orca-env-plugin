#!/usr/bin/env bash
# PreToolUse: block Serena edits unless find_referencing_symbols was called for the file
# in the current session. State recorded by post-record-refs.sh.
set -euo pipefail

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")

case "$TOOL" in
  mcp__serena__replace_symbol_body|mcp__serena__replace_content|\
  mcp__serena__insert_after_symbol|mcp__serena__insert_before_symbol|\
  mcp__serena__rename_symbol|mcp__serena__safe_delete_symbol) ;;
  *) exit 0 ;;
esac

REL_PATH=$(jq -r '.tool_input.relative_path // empty' <<<"$INPUT")
SESSION_ID=$(jq -r '.session_id // empty' <<<"$INPUT")
[[ -z "$REL_PATH" || -z "$SESSION_ID" ]] && exit 0

STATE_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}/state}"
STATE_FILE="$STATE_DIR/refs-traced.${SESSION_ID}.json"

DENY=1
if [[ -f "$STATE_FILE" ]]; then
  HAS=$(jq --arg p "$REL_PATH" '.traced[$p] // null' "$STATE_FILE" 2>/dev/null)
  [[ "$HAS" != "null" ]] && DENY=0
fi

if [[ "$DENY" == "1" ]]; then
  REASON="${TOOL} on '${REL_PATH}' is blocked: no mcp__serena__find_referencing_symbols recorded for this file in the current session. Call mcp__serena__find_referencing_symbols(name_path=<symbol>, relative_path=${REL_PATH}) first, then retry the edit."
  printf '%s\n' "$REASON" >&2
  jq -n --arg r "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 2
fi
exit 0
