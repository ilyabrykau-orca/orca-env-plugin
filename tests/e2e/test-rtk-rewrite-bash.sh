#!/usr/bin/env bash
# Unit tests for hooks/rtk-rewrite-bash
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/rtk-rewrite-bash
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

# fallthrough: expect exit 0, empty stdout
should_passthrough() {
  local name="$1" input="$2"
  out=$(echo "$input" | bash "$HOOK" 2>/dev/null); ec=$?
  [ $ec -eq 0 ] && [ -z "$out" ] \
    && ok "$name → fallthrough" \
    || fail "$name" "ec=$ec out='${out:0:60}'"
}

# JSON builder via heredoc (avoids quoting issues)
mk_input() {
  python3 <<PYEOF
import json
print(json.dumps({"tool_name": "$1", "tool_input": {"command": "$2"}}))
PYEOF
}

# 1: non-Bash tool
should_passthrough "non-Bash (Read)" "$(mk_input Read 'foo.py')"

# 2: empty command
should_passthrough "empty command" "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": ""}}))
PYEOF
)"

# 3: CLAUDE_RAW=1
out=$(mk_input Bash 'git status' | CLAUDE_RAW=1 bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "CLAUDE_RAW=1 → passthrough" || fail "CLAUDE_RAW" "expected empty"

# 4-10: metacharacter passthroughs (using heredoc to avoid nested quoting)
for meta_test in \
    'pipe|||git log | head' \
    'redirect>>>echo foo > out.txt' \
    'semicolon;;;cd /tmp; ls' \
    'background_&&&sleep 1 &'
do
  name="${meta_test%%|||*}"; name="${name%%>>>*}"; name="${name%%;;;*}"; name="${name%%&&&*}"
  cmd="${meta_test#*|||}"; cmd="${cmd#*>>>}"; cmd="${cmd#*;;;}"; cmd="${cmd#*&&&}"
  should_passthrough "$name metachar" "$(mk_input Bash "$cmd")"
done

# curly brace, subshell, backtick — use python heredocs
should_passthrough "curly brace {}" "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo {a,b}"}}))
PYEOF
)"
should_passthrough 'subshell $()' "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"r=$(git log)"}}))
PYEOF
)"
should_passthrough 'backtick ``' "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"r=`git log`"}}))
PYEOF
)"
should_passthrough 'heredoc <<' "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"cat <<EOF\nhello\nEOF"}}))
PYEOF
)"
should_passthrough 'multiline \n' "$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"for f in *.go; do\necho $f\ndone"}}))
PYEOF
)"

# missing rtk (clean PATH without rtk)
out=$(mk_input Bash 'git status' | PATH=/usr/bin:/bin bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "missing rtk → passthrough" || fail "no-rtk" "expected empty"

# tests with mock rtk
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# rtk returns same → passthrough
printf '#!/usr/bin/env bash\nshift; echo "$@"\n' > "$MOCK_DIR/rtk"
chmod +x "$MOCK_DIR/rtk"
out=$(mk_input Bash 'git status' | PATH="$MOCK_DIR:$PATH" bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "rtk returns same → passthrough" || fail "rtk-same" "$out"

# rtk rewrites differently → JSON
printf '#!/usr/bin/env bash\nshift; printf "rtk %%s" "$*"\n' > "$MOCK_DIR/rtk"
chmod +x "$MOCK_DIR/rtk"
out=$(mk_input Bash 'git status' | PATH="$MOCK_DIR:$PATH" bash "$HOOK" 2>/dev/null)
cmd=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['hookSpecificOutput']['updatedInput']['command'])" 2>/dev/null)
[[ "$cmd" == "rtk "* ]] \
  && ok "rtk rewrites → JSON with updatedInput (cmd=$cmd)" \
  || fail "rtk-rewrite" "cmd='$cmd' out='${out:0:80}'"

# ! not a metachar → rtk rewrite attempted
input_bang=$(python3 <<'PYEOF'
import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"echo !hello"}}))
PYEOF
)
out=$(echo "$input_bang" | PATH="$MOCK_DIR:$PATH" bash "$HOOK" 2>/dev/null)
cmd=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['hookSpecificOutput']['updatedInput']['command'])" 2>/dev/null)
[[ -n "$cmd" ]] \
  && ok "! not metachar → rtk attempted (cmd=$cmd)" \
  || fail "bang-history" "expected rewrite; out='${out:0:60}'"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
