#!/usr/bin/env bash
# Unit tests for hooks/post-serena-refs (Layer 3 producer: writes refs-traced.json)
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/post-serena-refs
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT
STATE_FILE="$BASE/state/refs-traced.json"

# Helpers
jval() { cat "$STATE_FILE" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)" 2>/dev/null; }
run_refs() {
  local path="$1" sess="${2:-sess1}" is_err="${3:-False}"
  python3 - <<PYEOF | CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" >/dev/null 2>&1
import json
print(json.dumps({"tool_name":"mcp__serena__find_referencing_symbols","tool_input":{"relative_path":"$path"},"tool_response":{"is_error":$is_err},"session_id":"$sess"}))
PYEOF
}
run_other() {
  local tool="$1"
  python3 - <<PYEOF | CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" >/dev/null 2>&1
import json
print(json.dumps({"tool_name":"$tool","tool_input":{"relative_path":"pkg/x.go"},"tool_response":{"is_error":False},"session_id":"sess1"}))
PYEOF
}

# 1: correct tool + ok + path → state file
run_refs pkg/foo.go sess1
[ -f "$STATE_FILE" ] && ok "find_refs → state file created" || fail "state-created" "file missing at $STATE_FILE"

# 2: session_id written correctly
sess=$(jval "d.get('session_id','MISSING')")
[ "$sess" = "sess1" ] && ok "session_id=sess1" || fail "session-id" "got: $sess"

# 3: path traced with numeric timestamp
ts=$(jval "type(d.get('traced',{}).get('pkg/foo.go',None)).__name__")
[ "$ts" = "int" ] && ok "path traced with int timestamp" || fail "timestamp-type" "got type=$ts"

# 4: different tool → no state change
before=$(cat "$STATE_FILE")
run_other mcp__serena__find_symbol
after=$(cat "$STATE_FILE")
[ "$before" = "$after" ] && ok "different tool → no change" || fail "diff-tool" "state changed"

# 5: error response → not traced
run_refs pkg/err.go sess1 True
path_err=$(jval "d.get('traced',{}).get('pkg/err.go','NOT_TRACED')")
[ "$path_err" = "NOT_TRACED" ] && ok "error response → not traced" || fail "error-skip" "got: $path_err"

# 6: no relative_path → no change
before=$(cat "$STATE_FILE")
python3 - <<PYEOF | CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" >/dev/null 2>&1
import json
print(json.dumps({"tool_name":"mcp__serena__find_referencing_symbols","tool_input":{},"tool_response":{"is_error":False},"session_id":"sess1"}))
PYEOF
after=$(cat "$STATE_FILE")
[ "$before" = "$after" ] && ok "no relative_path → no change" || fail "no-path" "state changed"

# 7: second path same session → both traced
run_refs pkg/bar.go sess1
k1=$(jval "'pkg/foo.go' in d.get('traced',{})")
k2=$(jval "'pkg/bar.go' in d.get('traced',{})")
[ "$k1" = "True" ] && [ "$k2" = "True" ] && ok "two paths same session → both traced" || fail "multi-path" "k1=$k1 k2=$k2"

# 8: session change → old paths cleared, new path added
run_refs new/path.go sess2
new_sess=$(jval "d.get('session_id','')")
old_key=$(jval "'pkg/foo.go' in d.get('traced',{})")
new_key=$(jval "'new/path.go' in d.get('traced',{})")
[ "$new_sess" = "sess2" ] && ok "session change → session_id=sess2" || fail "sess-update" "got: $new_sess"
[ "$old_key" = "False" ] && ok "session change → old paths cleared" || fail "old-cleared" "old path still in traced"
[ "$new_key" = "True" ] && ok "session change → new path added" || fail "new-added" "new path missing"

# 9: atomic write → no stale temp files
stale=$(ls "$BASE/state/"*.tmp.* 2>/dev/null | wc -l | tr -d ' ')
[ "${stale:-0}" -eq 0 ] && ok "no stale .tmp files" || fail "tmp-stale" "$stale files remain"

# 10: fail-open when jq missing
echo '{}' | PATH=/usr/bin:/bin CLAUDE_PLUGIN_DATA="$BASE" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok "missing jq → exit 0 (fail-open)" || fail "no-jq" "expected exit 0"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
