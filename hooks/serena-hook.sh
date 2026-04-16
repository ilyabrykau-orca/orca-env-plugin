#!/usr/bin/env bash
set -u

MODE="${1:-}"
CLIENT="claude-code"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/hooks.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log_json() {
  local event="$1"
  local detail="$2"
  local extra="${3:-{}}"
  if command -v jq >/dev/null 2>&1; then
    jq -cn \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg hook "serena-hook" \
      --arg mode "$MODE" \
      --arg event "$event" \
      --arg detail "$detail" \
      --argjson extra "$extra" \
      '{ts:$ts,hook:$hook,mode:$mode,event:$event,detail:$detail} + $extra' >> "$LOG_FILE" 2>/dev/null || true
  else
    printf '%s [%s:%s] %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "serena-hook" "$MODE" "$event" "$detail" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

case "$MODE" in
  activate|auto-approve|cleanup)
    ;;
  *)
    log_json "error" "unknown_mode" "$(jq -cn --arg mode "$MODE" '{mode:$mode}')"
    exit 0
    ;;
esac

if ! command -v serena-hooks >/dev/null 2>&1; then
  log_json "skip" "serena_hooks_missing"
  exit 0
fi

INPUT="$(cat)"
OUT_FILE="$(mktemp)"
ERR_FILE="$(mktemp)"
cleanup_tmp() {
  rm -f "$OUT_FILE" "$ERR_FILE"
}
trap cleanup_tmp EXIT

printf '%s' "$INPUT" | serena-hooks "$MODE" --client="$CLIENT" >"$OUT_FILE" 2>"$ERR_FILE"
RC=$?
OUT="$(cat "$OUT_FILE")"
ERR="$(cat "$ERR_FILE")"

if [ "$RC" -eq 0 ]; then
  log_json "ok" "command_succeeded" "$(jq -cn --arg stderr "$ERR" '{stderr:$stderr}')"
  printf '%s' "$OUT"
  exit 0
fi

log_json "error" "command_failed" "$(jq -cn --arg rc "$RC" --arg stderr "$ERR" '{rc:$rc,stderr:$stderr}')"
printf '%s' "$OUT"
exit 0
