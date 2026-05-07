#!/usr/bin/env bash
# PostToolUse: mark that CBM was used this session (flag file).
# pre-serena-read-guard reads this flag to suppress the "try CBM first" hint.
trap 'exit 0' EXIT

JQ=$(command -v jq 2>/dev/null || command -v jaq 2>/dev/null) || exit 0

INPUT=$(cat)
TOOL_NAME=$("$JQ" -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null) || exit 0

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

SESSION_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/${CLAUDE_SESSION_ID:-default}"
mkdir -p "$SESSION_DIR"
touch "${SESSION_DIR}/cbm-used"
exit 0
