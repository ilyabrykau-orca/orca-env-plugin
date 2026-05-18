#!/usr/bin/env bash
# PostToolBatch: log every batch and block if a native source tool escaped routing.
# Catches escapes that slipped past PreToolUse deny (known bypass: #37210, #33106).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INPUT=$(cat)
AUDIT_DIR="${CLAUDE_PLUGIN_DATA:-${PLUGIN_ROOT}/state}/audit"
mkdir -p "$AUDIT_DIR"

TS=$(date -u +%FT%TZ)
printf '{"ts":"%s","batch":%s}\n' "$TS" "$INPUT" >> "$AUDIT_DIR/tool-batches.jsonl"

# WATCHED_PREFIX overrides default list — for tests.
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

# Build a jq alternation pattern from the watched list
PREFIX_TESTS=""
for p in "${WATCHED_LIST[@]}"; do
  PREFIX_TESTS="${PREFIX_TESTS}${PREFIX_TESTS:+,}\"$p\""
done

VIOLATIONS=$(jq -r --argjson prefixes "[${PREFIX_TESTS}]" '
  [.. | objects
   | select((.tool_name? // "") | test("^(Read|Edit|Write|MultiEdit|Grep|Glob)$"))
   | select(
       (.tool_input.file_path? // .tool_input.path? // "") as $p |
       $prefixes | any(. as $pfx | $p | startswith($pfx))
     )
   | {tool: .tool_name, path: (.tool_input.file_path // .tool_input.path)}
  ]
' <<<"$INPUT")

COUNT=$(jq 'length' <<<"$VIOLATIONS")
if [[ "$COUNT" != "0" ]]; then
  printf '{"ts":"%s","violation_count":%s,"violations":%s}\n' "$TS" "$COUNT" "$VIOLATIONS" \
    >> "$AUDIT_DIR/violations.jsonl"
  jq -n --arg msg "Native source-tool calls escaped routing enforcement: $(jq -c <<<"$VIOLATIONS"). The next response must revert these changes (use mcp__serena__* for retained edits) and route through codebase-memory-mcp / Serena going forward." \
    '{decision: "block", reason: $msg}'
fi
exit 0
