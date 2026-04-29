#!/usr/bin/env bash
# Routing assertion helpers for E2E tests
set -euo pipefail

_ASSERT_ROUTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_ASSERT_ROUTING_DIR}/verify-transcript.sh"

assert_tool_used() {
    local transcript="$1"
    local tool_pattern="$2"
    local test_name="$3"
    local tools
    tools=$(extract_tool_calls "$transcript")
    if echo "$tools" | grep -q "$tool_pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — expected '$tool_pattern' in tool calls"
        return 1
    fi
}

assert_tool_not_used() {
    local transcript="$1"
    local tool_pattern="$2"
    local test_name="$3"
    local tools
    tools=$(extract_tool_calls "$transcript")
    if echo "$tools" | grep -q "$tool_pattern"; then
        echo "  [FAIL] $test_name — found forbidden '$tool_pattern' in tool calls"
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

assert_tool_before() {
    local transcript="$1"
    local tool_a="$2"
    local tool_b="$3"
    local test_name="$4"
    local tools
    tools=$(extract_tool_calls "$transcript")
    local pos_a pos_b
    pos_a=$(echo "$tools" | grep -n "$tool_a" | head -1 | cut -d: -f1)
    pos_b=$(echo "$tools" | grep -n "$tool_b" | head -1 | cut -d: -f1)
    if [ -n "$pos_a" ] && [ -n "$pos_b" ] && [ "$pos_a" -lt "$pos_b" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — expected '$tool_a' before '$tool_b'"
        return 1
    fi
}

assert_no_native_on_code() {
    local transcript="$1"
    local test_name="$2"
    local violations
    violations=$(echo "$transcript" | jq -r '
        .[]? |
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use") |
        select(.name == "Read" or .name == "Edit" or .name == "Write" or .name == "Grep" or .name == "Glob") |
        .input.file_path // .input.pattern // "unknown"
    ' 2>/dev/null | grep -E '\.(py|go|ts|tsx|js|jsx|rs|cpp|c|h|hpp|rb|java)$' || true)

    if [ -z "$violations" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — native tools used on source: $violations"
        return 1
    fi
}

export -f assert_tool_used
export -f assert_tool_not_used
export -f assert_tool_before
export -f assert_no_native_on_code
