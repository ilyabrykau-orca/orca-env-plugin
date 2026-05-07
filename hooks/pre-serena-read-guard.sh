#!/usr/bin/env bash
# PreToolUse guard: hint (non-blocking) when Serena read tools used without prior CBM.
# Outputs additionalContext JSON to stdout. Throttled to once per 300s per session.
trap 'exit 0' EXIT

JQ=$(command -v jq 2>/dev/null || command -v jaq 2>/dev/null) || exit 0

INPUT=$(cat)
TOOL_NAME=$("$JQ" -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null) || exit 0

case "$TOOL_NAME" in
  mcp__serena__find_symbol|\
  mcp__serena__get_symbols_overview|\
  mcp__serena__search_for_pattern|\
  mcp__serena__read_file|\
  mcp__serena__list_dir|\
  mcp__serena__find_file)
    ;;
  *)
    exit 0
    ;;
esac

SESSION_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/${CLAUDE_SESSION_ID:-default}"

# CBM used this session — hint not needed
[[ -f "${SESSION_DIR}/cbm-used" ]] && exit 0

# Throttle: suppress if warned within last 300s
WARN_TS_FILE="${SESSION_DIR}/serena-read-warned-ts"
if [[ -f "$WARN_TS_FILE" ]]; then
    last_ts=$(cat "$WARN_TS_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - last_ts < 300 )); then
        exit 0
    fi
fi

mkdir -p "$SESSION_DIR"
date +%s > "$WARN_TS_FILE"

MSG="Serena read tools are a FALLBACK. Try CBM first:
  mcp__codebase-memory-mcp__search_code(pattern=..., project=\"...\")
  mcp__codebase-memory-mcp__get_architecture(project=\"...\")
If CBM returns empty: (1) verify project name with list_projects() (2) broaden pattern (3) try search_graph.
This hint is non-blocking — proceed if CBM truly cannot help."

"$JQ" -n --arg msg "$MSG" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
exit 0
