#!/usr/bin/env bash
# PreToolUse: rewrite Bash commands through rtk for token savings.
# Falls through on shell metacharacters, missing rtk, or CLAUDE_RAW=1.
set -euo pipefail

INPUT=$(cat)
[[ "$(jq -r '.tool_name // empty' <<<"$INPUT")" != "Bash" ]] && exit 0

CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[[ -z "$CMD" ]] && exit 0
[[ -n "${CLAUDE_RAW:-}" ]] && exit 0
echo "$CMD" | grep -Eq '[|&;<>$`(){}]|<<' && exit 0
command -v rtk >/dev/null 2>&1 || exit 0

if command -v timeout >/dev/null 2>&1; then
  REWRITTEN=$(timeout 2 rtk rewrite "$CMD" 2>/dev/null || true)
elif command -v gtimeout >/dev/null 2>&1; then
  REWRITTEN=$(gtimeout 2 rtk rewrite "$CMD" 2>/dev/null || true)
else
  REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null || true)
fi
[[ -z "$REWRITTEN" || "$REWRITTEN" == "$CMD" ]] && exit 0

jq -n --arg cmd "$REWRITTEN" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "rtk auto-rewrite for token economy",
    updatedInput: { command: $cmd }
  }
}'
exit 0
