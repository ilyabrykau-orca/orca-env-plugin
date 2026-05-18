#!/usr/bin/env bash
# Unit tests for hooks/session-start and hooks/session-start-compact
HOOK_START=/Users/ilyabrykau/src/orca-env-plugin/hooks/session-start
HOOK_COMPACT=/Users/ilyabrykau/src/orca-env-plugin/hooks/session-start-compact
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

has_ctx() { echo "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); ctx=d.get('hookSpecificOutput',{}).get('additionalContext',''); exit(0 if ctx else 1)" 2>/dev/null; }
get_ctx() { echo "$1" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null; }

# ── session-start-compact tests ──────────────────────────────────────────────

# 1: exit 0
echo '{}' | bash "$HOOK_COMPACT" >/dev/null 2>&1; ec=$?
[ $ec -eq 0 ] && ok "compact: exit 0" || fail "compact-exit" "ec=$ec"

# 2: valid JSON output
out=$(echo '{}' | bash "$HOOK_COMPACT" 2>/dev/null)
echo "$out" | python3 -m json.tool >/dev/null 2>&1 && ok "compact: valid JSON" || fail "compact-json" "out='${out:0:40}'"

# 3: additionalContext contains routing rules
ctx=$(get_ctx "$out")
echo "$ctx" | grep -q "mcp__codebase-memory-mcp__search_code" && ok "compact: routing rules in context" || fail "compact-ctx" "missing CBM instruction"

# 4: fail-open without jq (outputs empty context, still valid JSON)
out=$(echo '{}' | PATH=/usr/bin:/bin bash "$HOOK_COMPACT" 2>/dev/null); ec=$?
[ $ec -eq 0 ] && ok "compact: no-jq → exit 0" || fail "compact-no-jq-ec" "ec=$ec"
echo "$out" | python3 -m json.tool >/dev/null 2>&1 && ok "compact: no-jq → valid JSON" || fail "compact-no-jq-json" "out='${out:0:40}'"

# ── session-start tests ──────────────────────────────────────────────────────

# 5: exit 0
out=$(echo '{}' | bash "$HOOK_START" 2>/dev/null); ec=$?
[ $ec -eq 0 ] && ok "start: exit 0" || fail "start-exit" "ec=$ec"

# 6: valid JSON
echo "$out" | python3 -m json.tool >/dev/null 2>&1 && ok "start: valid JSON" || fail "start-json" "out='${out:0:40}'"

# 7: CWD=orca-sensor → project detected in context
out=$(cd /tmp && mkdir -p /tmp/fake-orca-sensor-test && cd /tmp/fake-orca-sensor-test && bash "$HOOK_START" 2>/dev/null)
ctx=$(get_ctx "$out")
echo "$ctx" | grep -qi "orca-sensor" && ok "start: orca-sensor CWD → project in context" || fail "start-sensor-detect" "ctx='${ctx:0:80}'"
rm -rf /tmp/fake-orca-sensor-test

# 8: CWD=orca-runtime-sensor → project detected
out=$(cd /tmp && mkdir -p /tmp/fake-orca-runtime-sensor && cd /tmp/fake-orca-runtime-sensor && bash "$HOOK_START" 2>/dev/null)
ctx=$(get_ctx "$out")
echo "$ctx" | grep -qi "orca-runtime-sensor" && ok "start: orca-runtime-sensor CWD → project in context" || fail "start-runtime-detect" "ctx='${ctx:0:80}'"
rm -rf /tmp/fake-orca-runtime-sensor

# 9: CWD=random path → orca-unified or no project
out=$(cd /tmp && bash "$HOOK_START" 2>/dev/null)
ec=$?
[ $ec -eq 0 ] && ok "start: non-orca CWD → exit 0" || fail "start-nonorca-exit" "ec=$ec"

# 10: context includes skill content marker (EXTREMELY_IMPORTANT)
out=$(bash "$HOOK_START" 2>/dev/null)
ctx=$(get_ctx "$out")
echo "$ctx" | grep -q "EXTREMELY_IMPORTANT" && ok "start: EXTREMELY_IMPORTANT wrapper present" || fail "start-wrapper" "missing wrapper in ctx"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
