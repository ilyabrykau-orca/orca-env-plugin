#!/usr/bin/env bash
# Unit tests for hooks/skill-activation-prompt
HOOK=/Users/ilyabrykau/src/orca-env-plugin/hooks/skill-activation-prompt
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

# Minimal skill-rules.json for testing
mkdir -p "$BASE/skills"
cat > "$BASE/skills/skill-rules.json" << 'RULES'
{
  "skills": {
    "cbm-workflow": {
      "priority": "high",
      "promptTriggers": {"keywords": ["explore", "find function", "codebase"]}
    },
    "orca-dev": {
      "priority": "critical",
      "promptTriggers": {"keywords": ["edit", "refactor", "modify"]}
    },
    "no-keywords-skill": {
      "priority": "medium"
    }
  }
}
RULES

run() {
  python3 - <<PYEOF | CLAUDE_PLUGIN_ROOT="$BASE" bash "$HOOK" 2>/dev/null
import json
print(json.dumps({"user_prompt": "$1"}))
PYEOF
}

# 1: no rules file → no output
out=$(echo '{"user_prompt":"explore codebase"}' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok "no rules file → no output" || fail "no-rules" "expected empty; out='${out:0:60}'"

# 2: prompt matches keyword → JSON with additionalContext
out=$(run "explore the codebase")
ctx=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null)
echo "$ctx" | grep -q "cbm-workflow" && ok "keyword match → skill in context" || fail "keyword-match" "ctx='${ctx:0:80}'"

# 3: prompt doesn't match → no output
out=$(run "what is the weather today")
[ -z "$out" ] && ok "no keyword match → no output" || fail "no-match" "expected empty"

# 4: critical priority skill → REQUIRED label
out=$(run "refactor this function")
ctx=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null)
echo "$ctx" | grep -qi "REQUIRED" && ok "critical priority → REQUIRED label" || fail "critical-label" "ctx='${ctx:0:80}'"

# 5: high priority skill → RECOMMENDED label
out=$(run "explore the codebase")
ctx=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null)
echo "$ctx" | grep -qi "RECOMMENDED" && ok "high priority → RECOMMENDED label" || fail "high-label" "ctx='${ctx:0:80}'"

# 6: skill without keywords → never matched
out=$(run "no-keywords-skill test")
ctx=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null)
echo "$ctx" | grep -q "no-keywords-skill" && fail "no-keywords" "should not match skill without keywords" || ok "skill without keywords → not matched"

# 7: case-insensitive matching
out=$(run "EXPLORE the CODEBASE")
ctx=$(echo "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))" 2>/dev/null)
echo "$ctx" | grep -q "cbm-workflow" && ok "case-insensitive keyword match" || fail "case-insensitive" "ctx='${ctx:0:80}'"

# 8: empty prompt → no output
out=$(run "")
[ -z "$out" ] && ok "empty prompt → no output" || fail "empty-prompt" "expected empty"

# 9: missing jq → exit 0 fail-open
echo '{"user_prompt":"explore"}' | PATH=/usr/bin:/bin CLAUDE_PLUGIN_ROOT="$BASE" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok "missing jq → exit 0 (fail-open)" || fail "no-jq" "expected exit 0"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
