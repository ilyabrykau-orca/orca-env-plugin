#!/usr/bin/env bash
# Unit smoke test: live hook behaviour checks (no LLM)
# v2: uses dist/claude-toolkit binary instead of shell hook scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

echo "=== Unit: hooks smoke ==="
echo ""

# ── session-start ─────────────────────────────────────────────────────────────

echo "--- session-start: known project (/src → orca-unified) ---"

ss_out=$(cd /Users/ilyabrykau/src && echo '{}' | "$BINARY" session-start 2>/dev/null)

if assert_valid_json "$ss_out" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "SERENA WORKSPACE DETECTED" "project detected"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "activate_project.*orca-unified" "activation call for orca-unified"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: no HARD-BLOCKED section in session-start output (routing table only)
if assert_not_contains "$ss_out" "HARD-BLOCKED" "no HARD-BLOCKED in v2 session-start"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: no Params Cheat Sheet
if assert_not_contains "$ss_out" "Params Cheat Sheet" "no Params Cheat Sheet in v2 session-start"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: routing table is present
if assert_contains "$ss_out" "codebase-memory-mcp" "routing table mentions codebase-memory-mcp"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "--- session-start: unknown dir (/tmp) ---"

ss_tmp=$(cd /tmp && echo '{}' | "$BINARY" session-start 2>/dev/null)

if assert_valid_json "$ss_tmp" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$ss_tmp" "SERENA WORKSPACE DETECTED" "no project activation"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
# v2: still outputs routing table even without project
if assert_contains "$ss_tmp" "codebase-memory-mcp" "routing table present without project"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "--- pre-tool-use: block on code files ---"

# v2: binary outputs JSON deny on stdout (exit 0), not exit 2
check_block() {
    local label="$1" json="$2"
    local stdout
    stdout=$(echo "$json" | "$BINARY" pre-tool-use 2>/dev/null)
    local decision
    decision=$(echo "$stdout" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" = "deny" ]; then
        echo "  [PASS] $label (deny in JSON output)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label (expected deny, got: ${stdout:0:200})"
        failed=$((failed+1))
    fi
}

check_allow() {
    local label="$1" json="$2"
    local stdout
    stdout=$(echo "$json" | "$BINARY" pre-tool-use 2>/dev/null)
    local decision
    decision=$(echo "$stdout" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" != "deny" ]; then
        echo "  [PASS] $label (allowed — no deny)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label (expected allow, got deny: ${stdout:0:200})"
        failed=$((failed+1))
    fi
}

check_block "Read .py"   '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}'
check_block "Edit .go"   '{"tool_name":"Edit","tool_input":{"file_path":"pkg/sensor.go"}}'
check_block "Write .rs"  '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}'
check_block "Grep .cpp"  '{"tool_name":"Grep","tool_input":{"file_path":"src/sensor.cpp"}}'
check_block "Glob *.py"  '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}'
check_block "Read .java" '{"tool_name":"Read","tool_input":{"file_path":"Test.java"}}'

echo ""
echo "--- pre-tool-use: allow non-code files ---"

check_allow "Read .yaml"  '{"tool_name":"Read","tool_input":{"file_path":"config.yaml"}}'
check_allow "Read .md"    '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}'
check_allow "Edit .json"  '{"tool_name":"Edit","tool_input":{"file_path":"settings.json"}}'
# v2: .sh is ALLOWED (shell scripts are permitted)
check_allow "Read .sh"    '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}'
# v2: Grep with no file_path is ALLOWED (fail open)
check_allow "Grep no path" '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}'
check_allow "Bad JSON"    'not-json'

echo ""
echo "--- pre-tool-use: block message content ---"

block_out=$(echo '{"tool_name":"Read","tool_input":{"file_path":"main.py"}}' | "$BINARY" pre-tool-use 2>/dev/null)

if assert_contains "$block_out" "deny" "deny decision in JSON output"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$block_out" "codebase-memory-mcp" "codebase-memory-mcp redirect in deny reason"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── pre-serena-edit (via binary pre-tool-use) ────────────────────────────────

SMOKE_TMPROOT=$(mktemp -d)
trap "rm -rf '$SMOKE_TMPROOT'" EXIT

echo "--- pre-serena-edit: warn when no refs traced ---"

# Without refs state file, binary exits 1 (warning) for serena edit tools
rc=0
echo '{"tool_name":"mcp__serena__replace_symbol_body","tool_input":{"name_path":"Foo","relative_path":"bar.py","body":"pass"},"session_id":"smoke-test"}' \
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" "$BINARY" pre-tool-use >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
    echo "  [PASS] warns without refs (exit 1)"
    passed=$((passed+1))
else
    echo "  [FAIL] expected exit 1 without refs, got $rc"
    failed=$((failed+1))
fi

echo ""
echo "--- pre-serena-edit: allow non-edit tool ---"
rc=0
echo '{"tool_name":"mcp__serena__find_symbol","tool_input":{"name_path_pattern":"Foo"}}' \
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" "$BINARY" pre-tool-use >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] non-edit tool allowed (exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] non-edit tool expected exit 0, got $rc"
    failed=$((failed+1))
fi

# ── post-tool-use (refs tracker) ─────────────────────────────────────────────

echo ""
echo "--- post-tool-use (refs tracker): creates state file ---"

rm -rf "$SMOKE_TMPROOT/state"

rc=0
echo '{"tool_name":"mcp__serena__find_referencing_symbols","tool_input":{"name_path":"Foo","relative_path":"bar.py"},"session_id":"smoke-refs"}' \
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" "$BINARY" post-tool-use >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] post-tool-use exits 0"
    passed=$((passed+1))
else
    echo "  [FAIL] post-tool-use expected exit 0, got $rc"
    failed=$((failed+1))
fi

if [ -f "$SMOKE_TMPROOT/state/refs-traced.json" ]; then
    echo "  [PASS] state file created"
    passed=$((passed+1))
else
    echo "  [FAIL] state file not found at $SMOKE_TMPROOT/state/refs-traced.json"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
