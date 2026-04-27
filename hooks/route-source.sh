#!/usr/bin/env bash
# PreToolUse: deny native tools on watched orca source repos. Suggests the MCP replacement.
# No eval; tool input is treated as data.
set -euo pipefail

INPUT=$(cat)
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT")
PATH_ARG=$(jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // empty' <<<"$INPUT")
PATTERN=$(jq -r '.tool_input.pattern // empty' <<<"$INPUT")

# WATCHED_PREFIX overrides the default list — used by tests and for ad-hoc overrides.
# Production: hardcoded 6-repo list (orca-env-plugin and rtk are intentionally excluded).
if [[ -n "${WATCHED_PREFIX:-}" ]]; then
  EXPANDED="${WATCHED_PREFIX/#\~/$HOME}"
  WATCHED_LIST=("$EXPANDED")
else
  WATCHED_LIST=(
    "${HOME}/src/orca"
    "${HOME}/src/orca-cloud-platform"
    "${HOME}/src/orca-runtime-sensor"
    "${HOME}/src/orca-sensor"
    "${HOME}/src/grafana-provisioning"
    "${HOME}/src/helm-charts"
  )
fi

SRC_EXT_RE='\.(go|ts|tsx|py|rs|c|h|js|jsx|cpp|cc|hpp|rb|java|kt|swift|m|mm)$'
EXEMPT_RE='/(vendor|third_party|generated|node_modules|dist|build|\.git|\.venv|target)/'

is_watched_source() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  local prefix
  for prefix in "${WATCHED_LIST[@]}"; do
    if [[ "$p" == "$prefix"* ]]; then
      [[ "$p" =~ $EXEMPT_RE ]] && return 1
      [[ "$p" =~ $SRC_EXT_RE ]] && return 0
    fi
  done
  return 1
}

is_watched_prefix() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  local prefix
  for prefix in "${WATCHED_LIST[@]}"; do
    [[ "$p" == "$prefix"* ]] && return 0
  done
  return 1
}

deny() {
  local reason="$1"
  printf '%s\n' "$reason" >&2
  jq -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    },
    systemMessage: $r
  }'
  exit 2
}

case "$TOOL" in
  Read)
    if is_watched_source "$PATH_ARG"; then
      deny "Native Read on source ($PATH_ARG) is blocked. Use mcp__codebase-memory-mcp__get_code_snippet(qualified_name=...) to read symbol bodies — ~120x more token-efficient. For text search use mcp__codebase-memory-mcp__search_code(pattern, project)."
    fi
    ;;
  Edit|Write|MultiEdit|NotebookEdit)
    if is_watched_source "$PATH_ARG"; then
      deny "Native ${TOOL} on source ($PATH_ARG) is blocked. Use mcp__serena__replace_symbol_body / replace_content / insert_after_symbol / insert_before_symbol. Call mcp__serena__find_referencing_symbols(name_path=<symbol>, relative_path=${PATH_ARG}) FIRST in the same turn."
    fi
    ;;
  Grep|Glob)
    if is_watched_prefix "$PATH_ARG"; then
      deny "Native ${TOOL} on the source tree ($PATH_ARG) is blocked. Use mcp__codebase-memory-mcp__search_code(pattern=\"$PATTERN\", project=...) for graph-ranked results."
    fi
    if [[ -z "$PATH_ARG" && -n "$PATTERN" ]]; then
      if is_watched_prefix "${PWD:-}"; then
        deny "Native ${TOOL} from watched source tree (${PWD:-}) is blocked. Use mcp__codebase-memory-mcp__search_code(pattern=\"$PATTERN\", project=...)."
      fi
    fi
    ;;
esac

exit 0
