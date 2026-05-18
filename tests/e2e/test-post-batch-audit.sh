#!/usr/bin/env bash
# Unit tests for hooks/post-batch-audit.sh
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/post-batch-audit.sh
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT
AUDIT_DIR="$BASE/audit"

run() {
  echo "$1" | CLAUDE_PLUGIN_DATA="$BASE" WATCHED_PREFIX="${2:-/tmp/fake-watched}" bash "$HOOK" 2>/dev/null
}
has_violation() { [ -f "$AUDIT_DIR/violations.jsonl" ] && grep -q . "$AUDIT_DIR/violations.jsonl"; }
reset_audit() { rm -f "$AUDIT_DIR/violations.jsonl" "$AUDIT_DIR/tool-batches.jsonl"; }

# 1: empty batch → no violation, exit 0
out=$(run '{}')
ec=$?
[ $ec -eq 0 ] && ok "empty batch → exit 0" || fail "exit-code" "expected 0, got $ec"
has_violation && fail "empty-batch" "unexpected violation" || ok "empty batch → no violation"
reset_audit

# 2: always logs batch to tool-batches.jsonl
run '{"x":1}' >/dev/null
[ -f "$AUDIT_DIR/tool-batches.jsonl" ] && ok "batch always logged" || fail "batch-log" "tool-batches.jsonl missing"
reset_audit

# 3: Bash tool → no violation (not in blocked list)
run "$(python3 <<'PYEOF'
import json
print(json.dumps({"tool_results":[{"tool_name":"Bash","tool_input":{"command":"ls"}}]}))
PYEOF
)" "/tmp/fake-watched" >/dev/null
has_violation && fail "bash-tool" "unexpected violation" || ok "Bash tool → no violation"
reset_audit

# 4: CBM tool → no violation
run "$(python3 <<'PYEOF'
import json
print(json.dumps({"tool_results":[{"tool_name":"mcp__codebase-memory-mcp__search_code","tool_input":{"pattern":"foo"}}]}))
PYEOF
)" "/tmp/fake-watched" >/dev/null
has_violation && fail "cbm-tool" "unexpected violation" || ok "CBM tool → no violation"
reset_audit

# 5: Read on watched path → decision block output
WATCHED="/tmp/test-watched-$$"
out=$(run "$(python3 <<PYEOF
import json
print(json.dumps({"tool_results":[{"tool_name":"Read","tool_input":{"file_path":"$WATCHED/services/foo.py"}}]}))
PYEOF
)" "$WATCHED")
decision=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null)
[ "$decision" = "block" ] && ok "Read on watched path → decision:block" || fail "read-watched" "expected block; out='${out:0:60}'"
has_violation && ok "violation logged" || fail "violation-log" "violations.jsonl missing"
reset_audit

# 6: Edit on watched path → block
out=$(run "$(python3 <<PYEOF
import json
print(json.dumps({"tool_results":[{"tool_name":"Edit","tool_input":{"file_path":"$WATCHED/main.go"}}]}))
PYEOF
)" "$WATCHED")
decision=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null)
[ "$decision" = "block" ] && ok "Edit on watched path → block" || fail "edit-watched" "expected block"
reset_audit

# 7: Glob on watched path → block
out=$(run "$(python3 <<PYEOF
import json
print(json.dumps({"tool_results":[{"tool_name":"Glob","tool_input":{"path":"$WATCHED/**/*.go"}}]}))
PYEOF
)" "$WATCHED")
decision=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null)
[ "$decision" = "block" ] && ok "Glob on watched path → block" || fail "glob-watched" "expected block"
reset_audit

# 8: Read on NON-watched path → no violation
UNWATCHED="/tmp/other-dir-$$"
out=$(run "$(python3 <<PYEOF
import json
print(json.dumps({"tool_results":[{"tool_name":"Read","tool_input":{"file_path":"$UNWATCHED/foo.py"}}]}))
PYEOF
)" "$WATCHED")
[ -z "$out" ] && ok "Read on non-watched path → no violation" || fail "non-watched" "unexpected output: ${out:0:60}"
reset_audit

# 9: violation count in output
out=$(run "$(python3 <<PYEOF
import json
print(json.dumps({"tool_results":[
  {"tool_name":"Read","tool_input":{"file_path":"$WATCHED/a.go"}},
  {"tool_name":"Write","tool_input":{"file_path":"$WATCHED/b.py"}}
]}))
PYEOF
)" "$WATCHED")
decision=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('decision',''))" 2>/dev/null)
[ "$decision" = "block" ] && ok "multiple violations → block" || fail "multi-violation" "expected block"
reset_audit

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
