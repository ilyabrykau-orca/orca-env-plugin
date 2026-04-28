#!/usr/bin/env bash
# Unit test: PreToolUse enforcement hook (behavioral contract)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK="${PLUGIN_ROOT}/hooks/pre-tool-router"
passed=0; failed=0

echo "=== Unit: PreToolUse enforcement ==="
echo ""

# Helper: run hook, capture exit code and stderr
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

# Assert exit 2 + alternative string present in stderr
test_denied_with_alternative() {
    local json="$1"
    local test_name="$2"
    local expected_alt="$3"
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
    if echo "$stderr" | /usr/bin/grep -q "$expected_alt"; then
        echo "  [PASS] $test_name — correct alternative: $expected_alt"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — missing '$expected_alt' in stderr: $stderr"
        failed=$((failed+1))
    fi
}

# Assert exit 0 (allowed)
test_allowed() {
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

# Assert exit 1 + string in stderr
test_warned_with_message() {
    local json="$1"
    local test_name="$2"
    local expected_msg="$3"
    local result
    result=$(run_enforcement "$json")
    local exit_code="${result%%|*}"
    local stderr="${result#*|}"
    if [ "$exit_code" = "1" ]; then
        echo "  [PASS] $test_name (exit 1 = warn)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name (expected exit 1, got $exit_code)"
        failed=$((failed+1))
    fi
    if echo "$stderr" | /usr/bin/grep -q "$expected_msg"; then
        echo "  [PASS] $test_name — correct message: $expected_msg"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — missing '$expected_msg' in stderr: $stderr"
        failed=$((failed+1))
    fi
}

# ─── Layer 1: Grep/Glob unconditionally denied with CBM alternatives ──────────

echo "--- Layer 1: Grep/Glob → CBM alternatives ---"

test_denied_with_alternative \
    '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' \
    "Grep blocked unconditionally" \
    "mcp__codebase-memory-mcp__search_code"

test_denied_with_alternative \
    '{"tool_name":"Grep","tool_input":{"file_path":"src/sensor.cpp"}}' \
    "Grep on .cpp blocked" \
    "mcp__codebase-memory-mcp__search_code"

test_denied_with_alternative \
    '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}' \
    "Glob *.py blocked" \
    "mcp__codebase-memory-mcp__search_graph"

test_denied_with_alternative \
    '{"tool_name":"Glob","tool_input":{"pattern":"**/*.md"}}' \
    "Glob *.md blocked (even non-code pattern)" \
    "mcp__codebase-memory-mcp__search_graph"

# ─── Layer 2: Read/Edit/Write on code files denied ───────────────────────────

echo ""
echo "--- Layer 2: Read on code files → CBM/Serena alternatives ---"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}' \
    "Read .py blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"pkg/agent/agent.go"}}' \
    "Read .go blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"src/index.ts"}}' \
    "Read .ts blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"lib/utils.rs"}}' \
    "Read .rs blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"test/test_main.java"}}' \
    "Read .java blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

test_denied_with_alternative \
    '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}' \
    "Read .sh blocked" \
    "mcp__codebase-memory-mcp__get_code_snippet"

echo ""
echo "--- Layer 2: Edit/Write on code files → Serena alternatives ---"

test_denied_with_alternative \
    '{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts"}}' \
    "Edit .ts blocked" \
    "mcp__serena__replace"

test_denied_with_alternative \
    '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}' \
    "Write .rs blocked" \
    "mcp__serena__replace"

# ─── Read/Edit/Write on non-code files: allowed ──────────────────────────────

echo ""
echo "--- Non-code files: native tools allowed ---"

test_allowed \
    '{"tool_name":"Read","tool_input":{"file_path":"config.yaml"}}' \
    "Read .yaml allowed"

test_allowed \
    '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
    "Read .md allowed"

test_allowed \
    '{"tool_name":"Edit","tool_input":{"file_path":"settings.json"}}' \
    "Edit .json allowed"

test_allowed \
    '{"tool_name":"Read","tool_input":{"file_path":".gitignore"}}' \
    "Read .gitignore allowed"

test_allowed \
    '{"tool_name":"Read","tool_input":{"file_path":"Makefile"}}' \
    "Read Makefile allowed"

test_allowed \
    '{"tool_name":"Read","tool_input":{"file_path":"Dockerfile"}}' \
    "Read Dockerfile allowed"

# ─── Bash always allowed ─────────────────────────────────────────────────────

echo ""
echo "--- Bash: always allowed ---"

test_allowed \
    '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "Bash always allowed"

# ─── Layer 3: Serena edit guard ───────────────────────────────────────────────

echo ""
echo "--- Layer 3: Serena edit guard ---"

# Serena edit without refs → exit 1 warn with find_referencing_symbols suggestion
test_warned_with_message \
    '{"tool_name":"mcp__serena__replace_symbol_body","tool_input":{"name_path":"MyFunc","relative_path":"orca/sensors/base.py"}}' \
    "replace_symbol_body without refs → warn" \
    "find_referencing_symbols"

test_warned_with_message \
    '{"tool_name":"mcp__serena__replace_content","tool_input":{"relative_path":"orca/config.py","needle":"x","repl":"y","mode":"literal"}}' \
    "replace_content without refs → warn" \
    "find_referencing_symbols"

test_warned_with_message \
    '{"tool_name":"mcp__serena__insert_after_symbol","tool_input":{"name_path":"MyFunc","relative_path":"orca/utils.py"}}' \
    "insert_after_symbol without refs → warn" \
    "find_referencing_symbols"

test_warned_with_message \
    '{"tool_name":"mcp__serena__insert_before_symbol","tool_input":{"name_path":"MyFunc","relative_path":"orca/utils.py"}}' \
    "insert_before_symbol without refs → warn" \
    "find_referencing_symbols"

test_warned_with_message \
    '{"tool_name":"mcp__serena__rename_symbol","tool_input":{"name_path":"OldName","relative_path":"orca/models.py"}}' \
    "rename_symbol without refs → warn" \
    "find_referencing_symbols"

# safe_delete_symbol without refs → exit 1 warn
test_warned_with_message \
    '{"tool_name":"mcp__serena__safe_delete_symbol","tool_input":{"name_path":"DeadFunc","relative_path":"orca/dead.py"}}' \
    "safe_delete_symbol without refs → warn" \
    "find_referencing_symbols"

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
