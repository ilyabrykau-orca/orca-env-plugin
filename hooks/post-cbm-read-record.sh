#!/usr/bin/env bash
# PostToolUse: record successful CBM read calls for the session.
# Used by pre-serena-read-guard.sh to determine if CBM has been tried.
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT")

# Only record CBM read tools
case "$TOOL_NAME" in
  mcp__codebase-memory-mcp__search_code|\
  mcp__codebase-memory-mcp__search_graph|\
  mcp__codebase-memory-mcp__get_code_snippet|\
  mcp__codebase-memory-mcp__trace_path|\
  mcp__codebase-memory-mcp__query_graph|\
  mcp__codebase-memory-mcp__get_architecture|\
  mcp__codebase-memory-mcp__get_graph_schema|\
  mcp__codebase-memory-mcp__detect_changes)
    ;;
  *)
    exit 0
    ;;
esac

# Record to per-session log
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
LOG_DIR="${PLUGIN_DATA}/cbm-call-log"
CBM_LOG="${LOG_DIR}/${SESSION_ID}.json"

mkdir -p "$LOG_DIR"

# Append this call to the log
ENTRY=$(jq -n --arg tool "$TOOL_NAME" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{tool: $tool, timestamp: $ts}')

if [ -f "$CBM_LOG" ]; then
    jq --argjson entry "$ENTRY" '. += [$entry]' "$CBM_LOG" > "${CBM_LOG}.tmp" && mv "${CBM_LOG}.tmp" "$CBM_LOG"
else
    echo "[$ENTRY]" > "$CBM_LOG"
fi

exit 0
