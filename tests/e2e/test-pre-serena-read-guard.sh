#!/usr/bin/env bash
# Unit tests for hooks/pre-serena-read-guard.sh
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/pre-serena-read-guard.sh
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
SESS="test-sess"
SESSION_DIR="$BASE/$SESS"
trap 'rm -rf "$BASE"' EXIT

run() {
  local tool="$1"
  python3 - <<PYEOF | CLAUDE_PLUGIN_DATA="$BASE" CLAUDE_SESSION_ID="$SESS" bash "$HOOK" 2>/dev/null
import json
print(json.dumps({"tool_name": "$tool", "session_id": "$SESS"}))
PYEOF
}
has_hint() { echo "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print('additionalContext' in d.get('hookSpecificOutput',{}))" 2>/dev/null; }

# 1: non-Serena tool → no output
out=$(run mcp__serena__find_symbol_extra_not_matched)
[ -z "$out" ] && ok "unmatched Serena tool → no output" || fail "unmatched" "expected empty"

# 2: Serena read tool, no cbm-used → hint output
for tool in mcp__serena__find_symbol mcp__serena__get_symbols_overview mcp__serena__read_file mcp__serena__list_dir mcp__serena__find_file mcp__serena__search_for_pattern; do
  out=$(run "$tool")
  res=$(has_hint "$out")
  [ "$res" = "True" ] && ok "$tool → hint output" || fail "$tool" "expected hint; out='${out:0:40}'"
  # Reset throttle for next iteration
  rm -f "$SESSION_DIR/serena-read-warned-ts"
done

# 3: cbm-used flag exists → no hint
mkdir -p "$SESSION_DIR"
touch "$SESSION_DIR/cbm-used"
out=$(run mcp__serena__find_symbol)
[ -z "$out" ] && ok "cbm-used exists → no hint" || fail "cbm-used" "expected empty"
rm "$SESSION_DIR/cbm-used"

# 4: throttle active (warned <300s ago) → no hint
mkdir -p "$SESSION_DIR"
date +%s > "$SESSION_DIR/serena-read-warned-ts"
out=$(run mcp__serena__find_symbol)
[ -z "$out" ] && ok "throttle active → suppressed" || fail "throttle-active" "expected empty"

# 5: throttle expired (warned >300s ago) → hint again
echo "1" > "$SESSION_DIR/serena-read-warned-ts"  # epoch 1 = very old
out=$(run mcp__serena__find_symbol)
res=$(has_hint "$out")
[ "$res" = "True" ] && ok "throttle expired → hint again" || fail "throttle-expired" "expected hint"

# 6: missing jq → exit 0 fail-open
out=$(echo '{}' | PATH=/usr/bin:/bin CLAUDE_PLUGIN_DATA="$BASE" CLAUDE_SESSION_ID="$SESS" bash "$HOOK" 2>/dev/null); ec=$?
[ $ec -eq 0 ] && ok "missing jq → exit 0 (fail-open)" || fail "no-jq" "expected exit 0"

# 7: hint updates warned timestamp
before_ts=$(cat "$SESSION_DIR/serena-read-warned-ts" 2>/dev/null || echo 0)
sleep 1
rm -f "$SESSION_DIR/serena-read-warned-ts"  # reset so hint fires
run mcp__serena__find_symbol > /dev/null
after_ts=$(cat "$SESSION_DIR/serena-read-warned-ts" 2>/dev/null || echo 0)
[ "$after_ts" -gt "$before_ts" ] && ok "hint updates warned-ts" || fail "ts-update" "ts not updated"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
