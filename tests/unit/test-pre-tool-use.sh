#!/usr/bin/env bash
# Unit test: PreToolUse enforcement hook
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK="${PLUGIN_ROOT}/hooks/pre-tool-router"
passed=0; failed=0

echo "=== Unit: PreToolUse enforcement ==="
echo ""

# Helper: run hook with JSON input, capture exit code and stderr
run_enforcement() {
    local json="$1"
    local stderr_file
    stderr_file=$(mktemp)
    local exit_code=0
    echo "$json" | bash "$HOOK" 2>"$stderr_file" || exit_code=$?
    local stderr_out
    stderr_out=$(cat "$stderr_file")
    rm -f "$stderr_file"
    echo "${exit_code}|${stderr_out}"
}

test_block() {
    local json="$1"
    local test_name="$2"
    local expected_msg="$3"
    local result
    result=$(run_enforcement "$json")
    local exit_code="${result%%|*}"
    local stderr="${result#*|}"
    if [ "$exit_code" = "2" ]; then
        echo "  [PASS] $test_name (exit 2 = blocked)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name (expected exit 2, got $exit_code)"
        failed=$((failed+1))
    fi
    if echo "$stderr" | /usr/bin/grep -q "$expected_msg"; then
        echo "  [PASS] $test_name — correct suggestion"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — wrong suggestion: $stderr"
        failed=$((failed+1))
    fi
}

test_allow() {
    local json="$1"
    local test_name="$2"
    local result
    result=$(run_enforcement "$json")
    local exit_code="${result%%|*}"
    if [ "$exit_code" = "0" ]; then
        echo "  [PASS] $test_name (exit 0 = allowed)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name (expected exit 0, got $exit_code)"
        failed=$((failed+1))
    fi
}

echo "--- Blocks on code files ---"
test_block '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}' \
    "Read .py blocked" "mcp__serena__"
test_block '{"tool_name":"Read","tool_input":{"file_path":"pkg/agent/agent.go"}}' \
    "Read .go blocked" "mcp__serena__"
test_block '{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts"}}' \
    "Edit .ts blocked" "mcp__serena__replace"
test_block '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}' \
    "Write .rs blocked" "mcp__serena__replace"
test_block '{"tool_name":"Grep","tool_input":{"file_path":"src/sensor.cpp"}}' \
    "Grep .cpp blocked" "mcp__codanna__"
test_block '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}' \
    "Glob *.py blocked" "mcp__codanna__"
test_block '{"tool_name":"Read","tool_input":{"file_path":"test/test_main.java"}}' \
    "Read .java blocked" "mcp__serena__"

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
echo "--- Edge cases ---"
test_block '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' \
    "Grep blocked unconditionally (no file_path needed)" "mcp__codanna__"
test_block '{"tool_name":"Glob","tool_input":{"pattern":"**/*.md"}}' \
    "Glob blocked unconditionally (even non-code pattern)" "mcp__codanna__"
test_block '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}' \
    "Read .sh blocked (code file)" "mcp__serena__"
test_allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "Bash always allowed"

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
