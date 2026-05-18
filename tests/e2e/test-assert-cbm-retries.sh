#!/usr/bin/env bash
# Unit tests for assert_cbm_retries_on_empty
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert-routing.sh" >/dev/null 2>&1
source "$SCRIPT_DIR/lib/verify-transcript.sh" >/dev/null 2>&1
set +euo pipefail
PASS=0; FAIL=0
ok()   { echo "  [PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $1: $2"; FAIL=$((FAIL+1)); }

T_TRUNCATED=$(python3 <<'PYEOF'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"foo","project":"x"}}]}},
  {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"other_id","content":[{"type":"text","text":"ok"}]}]}},
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"s1","name":"mcp__serena__find_symbol","input":{"name_path_pattern":"foo"}}]}}
]))
PYEOF
)
T_NO_RESULTS=$(python3 <<'PYEOF'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"foo","project":"x"}}]}},
  {"type":"assistant","message":{"content":[{"type":"text","text":"note"}]}}
]))
PYEOF
)
T_TERMINAL=$(python3 <<'PYEOF'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"nope","project":"x"}}]}},
  {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c1","content":[{"type":"text","text":"{\"results\":[]}"}]}]}},
  {"type":"assistant","message":{"content":[{"type":"text","text":"not found"}]}}
]))
PYEOF
)
T_SERENA_FALLBACK=$(python3 <<'PYEOF'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"foo","project":"x"}}]}},
  {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c1","content":[{"type":"text","text":"{\"results\":[]}"}]}]}},
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"s1","name":"mcp__serena__find_symbol","input":{"name_path_pattern":"foo"}}]}}
]))
PYEOF
)
T_CBM_RETRY=$(python3 <<'PYEOF'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"foo","project":"x"}}]}},
  {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c1","content":[{"type":"text","text":"{\"results\":[]}"}]}]}},
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c2","name":"mcp__codebase-memory-mcp__search_graph","input":{"name_pattern":"foo","project":"x"}}]}}
]))
PYEOF
)
T_NO_CBM=$(python3 <<'PYEOF'
import json
print(json.dumps([{"type":"assistant","message":{"content":[{"type":"tool_use","id":"s1","name":"mcp__serena__find_symbol","input":{"name_path_pattern":"foo"}}]}}]))
PYEOF
)

T_PARTIAL_TRUNCATED=$(python3 <<'PYEOF2'
import json
print(json.dumps([
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c1","name":"mcp__codebase-memory-mcp__search_code","input":{"pattern":"foo","project":"x"}}]}},
  {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"c1","content":[{"type":"text","text":"ok result"}]}]}},
  {"type":"assistant","message":{"content":[{"type":"tool_use","id":"c2","name":"mcp__codebase-memory-mcp__search_graph","input":{"name_pattern":"foo","project":"x"}}]}}
]))
PYEOF2
)
assert_cbm_retries_on_empty "$T_PARTIAL_TRUNCATED" "t" >/dev/null 2>&1
[ $? -eq 0 ] && ok "partial-truncated (last CBM has no result, OK) → PASS" || fail "partial-truncated" "$out"

out=$(assert_cbm_retries_on_empty "$T_TRUNCATED" "t" 2>&1)
echo "$out" | grep -q '\[FAIL\]' && ok "truncated (has results, CBM missing) → FAIL" || fail "truncated" "$out"

assert_cbm_retries_on_empty "$T_NO_RESULTS" "t" >/dev/null 2>&1
[ $? -eq 0 ] && ok "no-results-at-all → vacuous PASS" || fail "no-results-at-all" "expected PASS"

assert_cbm_retries_on_empty "$T_TERMINAL" "t" >/dev/null 2>&1
[ $? -eq 0 ] && ok "empty-terminal (gave up) → PASS" || fail "terminal" "expected PASS"

out=$(assert_cbm_retries_on_empty "$T_SERENA_FALLBACK" "t" 2>&1)
echo "$out" | grep -q '\[FAIL\]' && ok "empty then Serena read → FAIL" || fail "serena-fallback" "$out"

assert_cbm_retries_on_empty "$T_CBM_RETRY" "t" >/dev/null 2>&1
[ $? -eq 0 ] && ok "empty then CBM retry → PASS" || fail "cbm-retry" "expected PASS"

assert_cbm_retries_on_empty "$T_NO_CBM" "t" >/dev/null 2>&1
[ $? -eq 0 ] && ok "no CBM → vacuous PASS" || fail "no-cbm" "expected PASS"

echo; echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
