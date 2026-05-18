#!/usr/bin/env bash
# Unit tests for hooks/pre-tool-router
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/pre-tool-router
PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail()  { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

mk() {
  python3 <<PYEOF
import json
d = {"tool_name": "$1", "tool_input": {}, "session_id": "${3:-sess0}"}
if "$2": d["tool_input"]["file_path"] = "$2"
if "${4:-}": d["tool_input"]["relative_path"] = "${4:-}"
print(json.dumps(d))
PYEOF
}

# expect exit code
assert_ec() {
  local name="$1" input="$2" want="$3"
  echo "$input" | bash "$HOOK" >/dev/null 2>&1; ec=$?
  [ "$ec" -eq "$want" ] && ok "$name (exit $want)" || fail "$name" "expected exit $want, got $ec"
}

# ── Layer 1: Grep/Glob always blocked ──────────────────────────────────
assert_ec "Grep blocked"     "$(mk Grep 'something')"   2
assert_ec "Glob blocked"     "$(mk Glob '**/*.go')"      2

# ── Layer 2: Read/Edit/Write on code files ──────────────────────────────
for ext in py go ts tsx js jsx rs cpp c h hpp rb java kt php scala swift sh bash; do
  assert_ec "Read .$ext blocked" "$(mk Read "pkg/foo.$ext")" 2
done
assert_ec "Edit .go blocked"  "$(mk Edit 'services/bar.go')"  2
assert_ec "Write .ts blocked" "$(mk Write 'src/app.ts')"      2

# Non-code extensions → allowed
assert_ec "Read .md allowed"   "$(mk Read 'README.md')"    0
assert_ec "Read .json allowed" "$(mk Read 'config.json')"  0
assert_ec "Read .yaml allowed" "$(mk Read 'chart.yaml')"   0
assert_ec "Read .txt allowed"  "$(mk Read 'notes.txt')"    0

# Empty file_path → allowed
assert_ec "Read empty path allowed" "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Read","tool_input":{"file_path":""},"session_id":"s0"}))
PYEOF
)" 0

# Non-blocking tool → allowed
assert_ec "Bash allowed"  "$(mk Bash '')"  0
assert_ec "Task allowed"  "$(mk Task '')"  0

# ── Layer 3: Serena edit guard ──────────────────────────────────────────
STATE_DIR=$(mktemp -d)
trap 'rm -rf "$STATE_DIR"' EXIT

# No state file → warn (exit 1)
assert_ec "serena edit no-state" "$(python3 <<PYEOF
import json
print(json.dumps({"tool_name":"mcp__serena__replace_content","tool_input":{"relative_path":"pkg/foo.go"},"session_id":"sess1"}))
PYEOF
)" 1

# State file with matching session + traced path → allow (exit 0)
mkdir -p "$STATE_DIR/state"
STATE_FILE="$STATE_DIR/state/refs-traced.json"
python3 -c "import json; open('$STATE_FILE','w').write(json.dumps({'session_id':'sess1','traced':{'pkg/foo.go':True}}))"
# Passing CLAUDE_PLUGIN_ROOT via env
echo "$(python3 <<PYEOF
import json; print(json.dumps({"tool_name":"mcp__serena__replace_content","tool_input":{"relative_path":"pkg/foo.go"},"session_id":"sess1"}))
PYEOF
)" | CLAUDE_PLUGIN_ROOT="$STATE_DIR" bash "$HOOK" >/dev/null 2>&1; ec=$?
[ "$ec" -eq 0 ] && ok "serena edit refs-traced → allow (exit 0)" || fail "refs-traced-allow" "expected 0, got $ec"

# State file exists but session mismatch → warn (exit 1)
echo "$(python3 <<PYEOF
import json; print(json.dumps({"tool_name":"mcp__serena__replace_symbol_body","tool_input":{"relative_path":"pkg/foo.go"},"session_id":"other_sess"}))
PYEOF
)" | CLAUDE_PLUGIN_ROOT="$STATE_DIR" bash "$HOOK" >/dev/null 2>&1; ec=$?
[ "$ec" -eq 1 ] && ok "serena edit session-mismatch → warn (exit 1)" || fail "session-mismatch" "expected 1, got $ec"

# Serena edit without relative_path → allow (no path to check)
assert_ec "serena edit no-relative-path" "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"mcp__serena__replace_content","tool_input":{},"session_id":"s0"}))
PYEOF
)" 0

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
