#!/usr/bin/env bash
# Unit test: PreToolUse enforcement (v2 binary)
# The binary outputs JSON with permissionDecision:"deny" on stdout (exit 0) for blocks.
# For allow, binary outputs nothing (exit 0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
passed=0; failed=0

echo "=== Unit: PreToolUse enforcement ==="
echo ""

# Helper: run binary with JSON input, capture stdout
run_enforcement() {
    local json="$1"
    echo "$json" | "$BINARY" pre-tool-use 2>/dev/null
}

# Expect a deny: stdout contains permissionDecision:"deny"
test_block() {
    local json="$1"
    local test_name="$2"
    local expected_msg="$3"
    local stdout
    stdout=$(run_enforcement "$json")
    local decision
    decision=$(echo "$stdout" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" = "deny" ]; then
        echo "  [PASS] $test_name (deny in JSON output)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name (expected deny, got: ${stdout:0:200})"
        failed=$((failed+1))
    fi
    local reason
    reason=$(echo "$stdout" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true)
    if echo "$reason" | /usr/bin/grep -q "$expected_msg"; then
        echo "  [PASS] $test_name — correct suggestion"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — wrong suggestion: $reason"
        failed=$((failed+1))
    fi
}

# Expect allow: stdout is empty (no deny JSON)
test_allow() {
    local json="$1"
    local test_name="$2"
    local stdout
    stdout=$(run_enforcement "$json")
    local decision
    decision=$(echo "$stdout" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)
    if [ "$decision" != "deny" ]; then
        echo "  [PASS] $test_name (allowed — no deny in output)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name (expected allow, got deny: ${stdout:0:200})"
        failed=$((failed+1))
    fi
}

echo "--- Blocks on code files ---"
test_block '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}' \
    "Read .py blocked" "codebase-memory-mcp"
test_block '{"tool_name":"Read","tool_input":{"file_path":"pkg/agent/agent.go"}}' \
    "Read .go blocked" "codebase-memory-mcp"
test_block '{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts"}}' \
    "Edit .ts blocked" "Serena"
test_block '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}' \
    "Write .rs blocked" "Serena"
test_block '{"tool_name":"Grep","tool_input":{"file_path":"src/sensor.cpp"}}' \
    "Grep .cpp blocked" "codebase-memory-mcp"
test_block '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}' \
    "Glob *.py blocked" "codebase-memory-mcp"
test_block '{"tool_name":"Read","tool_input":{"file_path":"test/test_main.java"}}' \
    "Read .java blocked" "codebase-memory-mcp"

echo ""
echo "--- Allows non-code files ---"
test_allow '{"tool_name":"Read","tool_input":{"file_path":"config.yaml"}}' \
    "Read .yaml allowed"
test_allow '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
    "Read .md allowed"
test_allow '{"tool_name":"Edit","tool_input":{"file_path":"settings.json"}}' \
    "Edit .json allowed"
test_allow '{"tool_name":"Read","tool_input":{"file_path":".gitignore"}}' \
    "Read .gitignore allowed"
test_allow '{"tool_name":"Read","tool_input":{"file_path":"Makefile"}}' \
    "Read Makefile allowed"
test_allow '{"tool_name":"Read","tool_input":{"file_path":"Dockerfile"}}' \
    "Read Dockerfile allowed"

echo ""
echo "--- Edge cases (v2 behavioral changes) ---"
# Grep with no file_path → ALLOWED (fail open, no path to check)
test_allow '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' \
    "Grep no file_path — ALLOWED (fail open)"
# Glob with non-code pattern → ALLOWED
test_allow '{"tool_name":"Glob","tool_input":{"pattern":"**/*.md"}}' \
    "Glob *.md — ALLOWED (not source ext)"
# Read .sh → ALLOWED (shell scripts allowed)
test_allow '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}' \
    "Read .sh — ALLOWED (shell scripts not blocked)"
# Grep with type=go → DENIED
test_block '{"tool_name":"Grep","tool_input":{"pattern":"func","type":"go","path":"/Users/ilyabrykau/src"}}' \
    "Grep type=go under src — DENIED" "codebase-memory-mcp"
# Bash always allowed
test_allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "Bash always allowed"

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
