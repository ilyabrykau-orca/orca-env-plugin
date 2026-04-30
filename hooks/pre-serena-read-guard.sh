#!/usr/bin/env bash
# PreToolUse guard: warn when Serena read tools are used without prior CBM reads this session.
# Exit 0 = allow, exit 2 = warn (non-blocking), exit 1 would be error (not used here).
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT")

# Only guard Serena read tools
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

# Check per-session CBM call log
PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}"
SESSION_ID="${CLAUDE_SESSION_ID:-default}"
CBM_LOG="${PLUGIN_DATA}/cbm-call-log/${SESSION_ID}.json"

cbm_successful=false
if [ -f "$CBM_LOG" ]; then
    # Check if there's at least one successful CBM read call recorded
    count=$(jq -r 'length // 0' "$CBM_LOG" 2>/dev/null || echo "0")
    if [ "$count" -gt 0 ]; then
        cbm_successful=true
    fi
fi

if [ "$cbm_successful" = "true" ]; then
    exit 0
fi

# No prior CBM calls — emit warning
cat >&2 << 'WARN'
⚠️ Serena read tools are a FALLBACK, not a starting point.

Try CBM first:
  mcp__codebase-memory-mcp__search_code(pattern=..., project="Users-ilyabrykau-src-...")
  mcp__codebase-memory-mcp__get_architecture(project="Users-ilyabrykau-src-...")
  mcp__codebase-memory-mcp__search_graph(query="MATCH (n) WHERE n.file CONTAINS '...' RETURN n", project="...")

If CBM returned empty:
  1. Verify project name with list_projects()
  2. Broaden pattern — drop path_filter, use concrete symbol names
  3. Try get_architecture or search_graph instead of search_code

This warning does not block; you can proceed if CBM truly cannot help.
WARN

exit 2
