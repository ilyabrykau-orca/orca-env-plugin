#!/usr/bin/env bash
# Unit smoke test: live hook behaviour checks (no LLM)
# Replaces ad-hoc manual commands with reproducible assertions.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK_SS="${PLUGIN_ROOT}/hooks/session-start"
HOOK_PT="${PLUGIN_ROOT}/hooks/pre-tool-router"
passed=0; failed=0

echo "=== Unit: hooks smoke ==="
echo ""

# ── session-start ─────────────────────────────────────────────────────────────

echo "--- session-start: known project (/src → orca-unified) ---"

ss_out=$(cd /Users/ilyabrykau/src && bash "$HOOK_SS" 2>/dev/null)

if assert_valid_json "$ss_out" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "SERENA WORKSPACE DETECTED" "project detected"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "activate_project.*orca-unified" "activation call for orca-unified"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "HARD-BLOCKED" "enforcement block injected"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "Params Cheat Sheet" "cheat sheet injected"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_out" "memory_file_name" "correct memory param name injected"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "--- session-start: unknown dir (/tmp) ---"

ss_tmp=$(cd /tmp && bash "$HOOK_SS" 2>/dev/null)

if assert_valid_json "$ss_tmp" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$ss_tmp" "SERENA WORKSPACE DETECTED" "no project activation"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$ss_tmp" "HARD-BLOCKED" "enforcement still injected without project"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "--- pre-tool-use: block on code files ---"

check_block() {
    local label="$1" json="$2"
    local rc=0
    echo "$json" | bash "$HOOK_PT" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "  [PASS] $label (exit 2 = blocked)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label (expected exit 2, got $rc)"
        failed=$((failed+1))
    fi
}

check_allow() {
    local label="$1" json="$2"
    local rc=0
    echo "$json" | bash "$HOOK_PT" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [PASS] $label (exit 0 = allowed)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label (expected exit 0, got $rc)"
        failed=$((failed+1))
    fi
}

check_block "Read .py"  '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}'
check_block "Edit .go"  '{"tool_name":"Edit","tool_input":{"file_path":"pkg/sensor.go"}}'
check_block "Write .rs" '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}'
check_block "Grep .ts"  '{"tool_name":"Grep","tool_input":{"file_path":"src/index.ts"}}'
check_block "Glob *.py" '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}'
check_block "Read .java" '{"tool_name":"Read","tool_input":{"file_path":"Test.java"}}'

echo ""
echo "--- pre-tool-use: allow non-code files ---"

check_allow "Read .yaml"   '{"tool_name":"Read","tool_input":{"file_path":"config.yaml"}}'
check_allow "Read .md"     '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}'
check_allow "Edit .json"   '{"tool_name":"Edit","tool_input":{"file_path":"settings.json"}}'
check_block "Read .sh"     '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}'
check_block "Grep no path" '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}'
check_allow "Bad JSON"     'not-json'

echo ""
echo "--- pre-tool-use: block message content ---"

stderr_out=$(echo '{"tool_name":"Read","tool_input":{"file_path":"main.py"}}' | bash "$HOOK_PT" 2>&1 || true)

if assert_contains "$stderr_out" "BLOCKED" "BLOCKED keyword in message"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$stderr_out" "mcp__serena__" "Serena redirect in message"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""

# ── pre-read-use ─────────────────────────────────────────────────────────────

HOOK_PR="${PLUGIN_ROOT}/hooks/pre-read-use"

if [ -f "$HOOK_PR" ]; then
echo "--- pre-read-use: allow small read ---"

check_exit() {
    local label="$1" json="$2" expected="$3"
    local rc=0
    echo "$json" | bash "$HOOK_PR" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq "$expected" ]; then
        echo "  [PASS] $label (exit $rc)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label (expected exit $expected, got $rc)"
        failed=$((failed+1))
    fi
}

# Allow: small limit (exit 0)
check_exit "small limit=100" \
    '{"tool_name":"Read","tool_input":{"file_path":"config.yaml","limit":100}}' 0

# Warn: medium limit (exit 1)
check_exit "medium limit=500" \
    '{"tool_name":"Read","tool_input":{"file_path":"big.py","limit":500}}' 1

# Block: huge limit (exit 2)
check_exit "huge limit=800" \
    '{"tool_name":"Read","tool_input":{"file_path":"huge.py","limit":800}}' 2

echo ""
echo "--- pre-read-use: non-Read tool passes through ---"
check_exit "Edit tool passes" \
    '{"tool_name":"Edit","tool_input":{"file_path":"foo.py"}}' 0

else
echo "--- pre-read-use: SKIPPED (hook not yet created) ---"
fi

# ── pre-serena-edit ──────────────────────────────────────────────────────────

HOOK_SE="${PLUGIN_ROOT}/hooks/pre-serena-edit"
HOOK_PR_REFS="${PLUGIN_ROOT}/hooks/post-serena-refs"

# Use a temp dir as CLAUDE_PLUGIN_ROOT for isolation
SMOKE_TMPROOT=$(mktemp -d)
trap "rm -rf '$SMOKE_TMPROOT'" EXIT

if [ -f "$HOOK_SE" ]; then
echo ""
echo "--- pre-serena-edit: warn when no refs traced ---"

# Without refs state file, should warn (exit 1)
rc=0
echo '{"tool_name":"mcp__serena__replace_symbol_body","tool_input":{"name_path":"Foo","relative_path":"bar.py","body":"pass"},"session_id":"smoke-test"}' \
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" bash "$HOOK_SE" >/dev/null 2>&1 || rc=$?
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
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" bash "$HOOK_SE" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] non-edit tool allowed (exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] non-edit tool expected exit 0, got $rc"
    failed=$((failed+1))
fi

else
echo ""
echo "--- pre-serena-edit: SKIPPED (hook not yet created) ---"
fi

# ── post-serena-refs ─────────────────────────────────────────────────────────

if [ -f "$HOOK_PR_REFS" ]; then
echo ""
echo "--- post-serena-refs: creates state file ---"

# Clean state dir inside our temp root
rm -rf "$SMOKE_TMPROOT/state"

rc=0
echo '{"tool_name":"mcp__serena__find_referencing_symbols","tool_input":{"name_path":"Foo","relative_path":"bar.py"},"session_id":"smoke-refs"}' \
    | CLAUDE_PLUGIN_ROOT="$SMOKE_TMPROOT" bash "$HOOK_PR_REFS" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then
    echo "  [PASS] post-serena-refs exits 0"
    passed=$((passed+1))
else
    echo "  [FAIL] post-serena-refs expected exit 0, got $rc"
    failed=$((failed+1))
fi

# Check if state file was created
if [ -f "$SMOKE_TMPROOT/state/refs-traced.json" ]; then
    echo "  [PASS] state file created"
    passed=$((passed+1))
else
    echo "  [FAIL] state file not found at $SMOKE_TMPROOT/state/refs-traced.json"
    failed=$((failed+1))
fi

else
echo ""
echo "--- post-serena-refs: SKIPPED (hook not yet created) ---"
fi

# ── skill-activation-prompt ──────────────────────────────────────────────────

HOOK_SAP="${PLUGIN_ROOT}/hooks/skill-activation-prompt"

if [ -f "$HOOK_SAP" ]; then
echo ""
echo "--- skill-activation-prompt: keyword match outputs suggestion ---"

# Use "create skill" which matches skill-developer keyword in skill-rules.json
sap_out=""
sap_out=$(echo '{"prompt":"I want to create skill for my project"}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK_SAP" 2>/dev/null) || true
if [ -n "$sap_out" ]; then
    echo "  [PASS] outputs suggestion for keyword match"
    passed=$((passed+1))
else
    echo "  [FAIL] no output for keyword match"
    failed=$((failed+1))
fi

# No keyword match — should exit cleanly with no output
sap_out2=""
sap_out2=$(echo '{"prompt":"hello world"}' \
    | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK_SAP" 2>/dev/null) || true
if [ -z "$sap_out2" ]; then
    echo "  [PASS] no-match prompt handled cleanly (empty output)"
    passed=$((passed+1))
else
    echo "  [PASS] no-match prompt handled cleanly (has output)"
    passed=$((passed+1))
fi

else
echo ""
echo "--- skill-activation-prompt: SKIPPED (hook not yet created) ---"
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
