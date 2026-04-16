#!/usr/bin/env bash
# RTK auto-rewrite hook for Claude Code PreToolUse:Bash.
# Thin delegate: parse Claude Code JSON, call `rtk rewrite`, emit updatedInput.

set -u

LOG_DIR="${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/logs"
LOG_FILE="${LOG_DIR}/hooks.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log_json() {
  local event="$1"
  local detail="$2"
  local extra="${3:-{}}"
  if command -v jq >/dev/null 2>&1; then
    jq -cn       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)"       --arg hook "rtk-rewrite"       --arg event "$event"       --arg detail "$detail"       --argjson extra "$extra"       '{ts:$ts,hook:$hook,event:$event,detail:$detail} + $extra' >> "$LOG_FILE" 2>/dev/null || true
  fi
}

if ! command -v jq >/dev/null 2>&1 || ! command -v rtk >/dev/null 2>&1; then
  log_json "skip" "deps_missing"
  exit 0
fi

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && { log_json "skip" "empty_command"; exit 0; }

case "$CMD" in
  CLAUDE_RAW=1*|*" CLAUDE_RAW=1 "*)
    log_json "skip" "raw_bypass" "$(jq -cn --arg cmd "$CMD" '{command:$cmd}')"
    exit 0 ;;
esac

case "$CMD" in
  *'|'*|*'>'*|*'<'*|*'&&'*|*'||'*|*';'*|*'$('*|*'`'*|*'<<'*)
    log_json "skip" "composite_shell" "$(jq -cn --arg cmd "$CMD" '{command:$cmd}')"
    exit 0 ;;
esac

REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null)
RC=$?
case $RC in
  0|3) ;;
  1)
    log_json "skip" "no_rewrite" "$(jq -cn --arg cmd "$CMD" '{command:$cmd}')"
    exit 0 ;;
  2)
    log_json "deny" "rtk_deny_rule" "$(jq -cn --arg cmd "$CMD" '{command:$cmd}')"
    jq -n --arg reason "RTK deny rule matched: $CMD" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0 ;;
  *)
    log_json "skip" "rtk_error" "$(jq -cn --arg cmd "$CMD" --arg rc "$RC" '{command:$cmd,rc:$rc}')"
    exit 0 ;;
esac

if [ -z "$REWRITTEN" ] || [ "$REWRITTEN" = "$CMD" ]; then
  log_json "allow" "already_raw_or_wrapped" "$(jq -cn --arg cmd "$CMD" '{command:$cmd}')"
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"RTK wrapper"}}'
  exit 0
fi

UPDATED_INPUT=$(printf '%s' "$INPUT" | jq --arg cmd "$REWRITTEN" '.tool_input | .command = $cmd' 2>/dev/null)
[ -z "$UPDATED_INPUT" ] && { log_json "skip" "updated_input_build_failed"; exit 0; }

log_json "rewrite" "rtk_auto_rewrite" "$(jq -cn --arg before "$CMD" --arg after "$REWRITTEN" '{before:$before,after:$after}')"
jq -n --argjson updated "$UPDATED_INPUT" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",permissionDecisionReason:"RTK auto-rewrite",updatedInput:$updated}}'
