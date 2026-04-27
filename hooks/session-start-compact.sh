#!/usr/bin/env bash
# SessionStart (compact): minimal routing re-injection after compaction.
# Compact wipes early context; this restores the routing block in the fewest tokens.
set -euo pipefail

read -r -d '' CTX <<'EOF' || true
<tool_routing_compact>
Routing rules survive compaction:
- Source read/search: mcp__codebase-memory-mcp__* only.
- Source write: mcp__serena__* only (find_referencing_symbols first).
- Native Read/Edit/Grep/Glob on watched source roots: denied by hook + permissions.deny.
- Non-source files: native Read/Write/Edit.
</tool_routing_compact>
EOF

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'
exit 0
