#!/usr/bin/env bash
# Unit tests for hooks/stop.js and hooks/subagent-stop.js
STOP_HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/stop.js
SUBAGENT_HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/subagent-stop.js
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

# Minimal JSONL transcript
TRANSCRIPT="$BASE/transcript.jsonl"
python3 - <<PYEOF > "$TRANSCRIPT"
import json
# assistant message with tool use and token usage
print(json.dumps({"type":"assistant","session_id":"test","timestamp":"2026-05-18T00:00:00Z",
  "message":{"model":"claude-sonnet","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}],
  "usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":200,"cache_creation_input_tokens":10}}}))
# user tool result
print(json.dumps({"type":"user","session_id":"test","timestamp":"2026-05-18T00:00:01Z",
  "message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"ok"}]}]}}))
PYEOF

mk_input() {
  python3 -c "import json; print(json.dumps({'transcript_path':'$1','cwd':'$BASE','gitBranch':'main','session_id':'test'}))"
}

# ── stop.js tests ──────────────────────────────────────────────────────────

# 1: missing transcript → exit 0 (fail-open)
echo '{}' | node "$STOP_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "stop.js: missing transcript → exit 0" || fail "stop-no-transcript" "ec=$ec"

# 2: invalid JSON input → exit 0
echo 'not-json' | node "$STOP_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "stop.js: invalid JSON → exit 0" || fail "stop-bad-json" "ec=$ec"

# 3: nonexistent path → exit 0
mk_input "/nonexistent/path.jsonl" | node "$STOP_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "stop.js: nonexistent path → exit 0" || fail "stop-bad-path" "ec=$ec"

# 4: valid transcript → stats file created, exit 0
STATS_DIR="$BASE/logs/stats"
mk_input "$TRANSCRIPT" | CLAUDE_PROJECT_DIR="$BASE" node "$STOP_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "stop.js: valid transcript → exit 0" || fail "stop-valid-ec" "ec=$ec"
[ -f "$STATS_DIR/sessions.jsonl" ] && ok "stop.js: sessions.jsonl created" || fail "stop-stats-file" "file missing"
[ -f "$STATS_DIR/latest-session.json" ] && ok "stop.js: latest-session.json created" || fail "stop-latest" "file missing"

# 5: sessions.jsonl contains valid JSON with token data
if [ -f "$STATS_DIR/sessions.jsonl" ]; then
  tokens=$(tail -1 "$STATS_DIR/sessions.jsonl" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tokens',{}).get('input',0))" 2>/dev/null)
  [ "${tokens:-0}" -gt 0 ] && ok "stop.js: token stats extracted (input=$tokens)" || fail "stop-tokens" "tokens=$tokens"
fi

# ── subagent-stop.js tests ─────────────────────────────────────────────────

# 6: missing transcript → exit 0
echo '{}' | node "$SUBAGENT_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "subagent-stop.js: missing transcript → exit 0" || fail "sub-no-transcript" "ec=$ec"

# 7: valid transcript → subagent-sessions.jsonl
mk_input "$TRANSCRIPT" | CLAUDE_PROJECT_DIR="$BASE" node "$SUBAGENT_HOOK" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "subagent-stop.js: valid transcript → exit 0" || fail "sub-valid-ec" "ec=$ec"
[ -f "$STATS_DIR/subagent-sessions.jsonl" ] && ok "subagent-stop.js: subagent-sessions.jsonl created" || fail "sub-stats" "file missing"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
