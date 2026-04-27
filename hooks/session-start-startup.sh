#!/usr/bin/env bash
# SessionStart (startup|resume|clear): inject full routing block + workspace detection.
# Compact gets a smaller payload from session-start-compact.sh.
set -euo pipefail

INPUT=$(cat)
CWD=$(jq -r '.cwd // empty' <<<"$INPUT")

PROJECT=""
case "$CWD" in
  *"/src/orca-env-plugin"*)     PROJECT="orca-env-plugin" ;;
  *"/src/orca-cloud-platform"*) PROJECT="orca-cloud-platform" ;;
  *"/src/orca-runtime-sensor"*) PROJECT="orca-runtime-sensor" ;;
  *"/src/orca-sensor"*)         PROJECT="orca-sensor" ;;
  *"/src/helm-charts"*)         PROJECT="helm-charts" ;;
  *"/src/grafana-provisioning"*)PROJECT="grafana-provisioning" ;;
  *"/src/orca"*)                PROJECT="orca" ;;
esac
HOME_SRC="${HOME}/src"
if [[ "$CWD" == "$HOME_SRC" || "$CWD" == "$HOME_SRC/" ]]; then
  PROJECT="orca-unified"
fi

read -r -d '' CTX <<'EOF' || true
SERENA WORKSPACE DETECTED (if project set below): activate via mcp__serena__activate_project(project=<PROJECT>) before the first Serena edit.

<tool_routing>
Mandatory routing. Re-read before each tool call on source code.
- Source read/search/navigate: mcp__codebase-memory-mcp__* only.
  Use search_code, get_code_snippet, search_graph, trace_path, get_architecture, query_graph.
- Source write/edit/refactor: mcp__serena__* only.
  Call find_referencing_symbols(relative_path=...) FIRST in the same turn.
- Non-source (.md .json .yaml configs): native Read/Write/Edit.
- Bash: passes through; rtk auto-rewrites for token savings.
- Exempt: vendor/ third_party/ generated/ node_modules/ dist/ build/
- Hooks + permissions.deny enforce these rules at runtime.
- Batch independent tool calls in parallel.
</tool_routing>

If CBM index is missing or stale: run mcp__codebase-memory-mcp__index_repository first.
EOF

if [[ -n "$PROJECT" ]]; then
  CTX="SERENA WORKSPACE DETECTED: project='${PROJECT}' at ${CWD}
IMMEDIATELY call: mcp__serena__activate_project(project=${PROJECT})

${CTX}"
fi

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
