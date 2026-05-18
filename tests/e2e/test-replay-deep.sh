#!/usr/bin/env bash
REPLAY="/Users/ilyabrykau/src/orca-env-plugin/tests/e2e/replay-deep.sh"
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

mk_session() {
  local name="$1" cwd="$2" path="$3" tid="t_$1"
  local dir="$TMPDIR_TEST/$name"; mkdir -p "$dir"
  python3 - > "$dir/session.jsonl" <<PYEOF
import json
print(json.dumps({"type":"assistant","cwd":"$cwd","message":{"content":[{"type":"tool_use","id":"$tid","name":"Read","input":{"file_path":"$path"}}]}}))
print(json.dumps({"type":"user","cwd":"$cwd","message":{"content":[{"type":"tool_result","tool_use_id":"$tid","content":[{"type":"text","text":"code"}]}]}}))
PYEOF
}

mk_session "s1" "/home/u/src/orca-sensor"         "/home/u/src/orca-sensor/pkg/foo.py"
mk_session "s2" "/home/u/src/orca-runtime-sensor" "/home/u/src/orca-runtime-sensor/main.go"
mk_session "s3" "/home/u/src/other-repo"           "/home/u/src/other-repo/app.py"

rows() { PROJECTS_DIR="$TMPDIR_TEST" bash "$REPLAY" --no-cache --min-size 0 --tsv "$@" 2>/dev/null | awk 'NF>0' | wc -l | tr -d ' '; }

# 1: no filter → 3 rows
n=$(rows); [ "$n" -eq 3 ] && ok "no-filter: 3 rows" || fail "no-filter" "expected 3, got $n"

# 2: literal filter → orca-sensor only (1 row)
n=$(rows --cwd-filter "/home/u/src/orca-sensor$")
[ "$n" -eq 1 ] && ok "literal filter: 1 orca-sensor row" || fail "literal" "expected 1, got $n"

# 3: non-matching → 0
n=$(rows --cwd-filter "nomatch-xyz"); [ "$n" -eq 0 ] && ok "non-matching → 0" || fail "nomatch" "expected 0, got $n"

# 4: regex alternation → 2 orca repos
n=$(rows --cwd-filter "orca-sensor|orca-runtime")
[ "$n" -eq 2 ] && ok "regex alternation: 2 rows" || fail "regex-alt" "expected 2, got $n"

# 5: substring match — 'orca' matches both orca-* repos
n=$(rows --cwd-filter "/home/u/src/orca")
[ "$n" -eq 2 ] && ok "substring 'orca' matches both orca repos" || fail "substring" "expected 2, got $n"

# 6: invalid regex → exit 2
PROJECTS_DIR="$TMPDIR_TEST" bash "$REPLAY" --no-cache --min-size 0 --tsv --cwd-filter "[" >/dev/null 2>&1
ec=$?; [ "$ec" -eq 2 ] && ok "invalid regex → exit 2" || fail "invalid-regex" "expected exit 2, got $ec"

# 7: empty filter → pass-through (3 rows)
n=$(rows --cwd-filter ""); [ "$n" -eq 3 ] && ok "empty filter → pass-through (3 rows)" || fail "empty-filter" "expected 3, got $n"

# 8: --projects-dir flag overrides PROJECTS_DIR env
TMPDIR2=$(mktemp -d)
D="$TMPDIR2/s4"; mkdir -p "$D"
python3 -c "
import json, sys
e1 = {'type':'assistant','cwd':'/extra/cloud','message':{'content':[{'type':'tool_use','id':'t4','name':'Read','input':{'file_path':'/extra/cloud/main.py'}}]}}
e2 = {'type':'user','cwd':'/extra/cloud','message':{'content':[{'type':'tool_result','tool_use_id':'t4','content':[{'type':'text','text':'x'}]}]}}
print(json.dumps(e1)); print(json.dumps(e2))
" > "$D/session.jsonl"
n=$(PROJECTS_DIR="$TMPDIR_TEST" bash "$REPLAY" --no-cache --min-size 0 --tsv --projects-dir "$TMPDIR2" 2>/dev/null | awk 'NF>0' | wc -l | tr -d ' ')
rm -rf "$TMPDIR2"
[ "$n" -eq 1 ] && ok "--projects-dir overrides PROJECTS_DIR env" || fail "projects-dir" "expected 1, got $n"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
