#!/usr/bin/env bash
# Unit tests for hooks/post-cbm-read-record.sh
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/post-cbm-read-record.sh
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

run() {
  local tool="$1"
  local sess="${2:-test-session}"
  local dir="$BASE/$sess"
  python3 -c "import json; print(json.dumps({'tool_name':'$tool'}))" \
    | CLAUDE_PLUGIN_DATA="$BASE" CLAUDE_SESSION_ID="$sess" bash "$HOOK" >/dev/null 2>&1
  echo "$dir"
}

# CBM read tools → cbm-used flag created
for tool in \
  mcp__codebase-memory-mcp__search_code \
  mcp__codebase-memory-mcp__search_graph \
  mcp__codebase-memory-mcp__get_code_snippet \
  mcp__codebase-memory-mcp__trace_path \
  mcp__codebase-memory-mcp__query_graph \
  mcp__codebase-memory-mcp__get_architecture \
  mcp__codebase-memory-mcp__get_graph_schema \
  mcp__codebase-memory-mcp__detect_changes
do
  dir=$(run "$tool" "s-$tool")
  [ -f "$dir/cbm-used" ] && ok "$tool → flag created" || fail "$tool" "cbm-used not found at $dir"
done

# Non-CBM tools → no flag
for tool in \
  mcp__serena__find_symbol \
  mcp__codebase-memory-mcp__list_projects \
  mcp__codebase-memory-mcp__index_repository \
  Read \
  Bash
do
  dir=$(run "$tool" "s-$tool")
  [ -f "$dir/cbm-used" ] && fail "$tool" "cbm-used should NOT exist" || ok "$tool → no flag (correct)"
done

# CLAUDE_SESSION_ID affects path
python3 -c "import json; print(json.dumps({'tool_name':'mcp__codebase-memory-mcp__search_code'}))" \
  | CLAUDE_PLUGIN_DATA="$BASE" CLAUDE_SESSION_ID="custom-sess" bash "$HOOK" >/dev/null 2>&1
[ -f "$BASE/custom-sess/cbm-used" ] && ok "CLAUDE_SESSION_ID → correct path" || fail "session-id" "flag missing at $BASE/custom-sess"

# Default session dir when CLAUDE_SESSION_ID unset
python3 -c "import json; print(json.dumps({'tool_name':'mcp__codebase-memory-mcp__search_code'}))" \
  | CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" >/dev/null 2>&1
[ -f "$BASE/default/cbm-used" ] && ok "default session → $BASE/default/cbm-used" || fail "default-sess" "flag missing"

# Exit 0 on missing jq
out=$(python3 -c "import json; print(json.dumps({'tool_name':'mcp__codebase-memory-mcp__search_code'}))" \
  | PATH=/usr/bin:/bin CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" 2>/dev/null); ec=$?
[ $ec -eq 0 ] && ok "missing jq → exit 0 (fail-open)" || fail "no-jq" "expected exit 0, got $ec"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
