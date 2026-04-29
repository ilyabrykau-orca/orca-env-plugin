#!/usr/bin/env bash
# Test helpers for orca-env plugin tests

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Assertions ---

assert_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"
    if [[ "$output" =~ $pattern ]]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected pattern: $pattern"
        echo "  In output (first 200 chars):"
        echo "    ${output:0:200}"
        return 1
    fi
}

assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local test_name="${3:-test}"
    if [[ "$output" =~ $pattern ]]; then
        echo "  [FAIL] $test_name"
        echo "  Did not expect: $pattern"
        echo "  In output (first 200 chars):"
        echo "    ${output:0:200}"
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

assert_count() {
    local output="$1"
    local pattern="$2"
    local expected="$3"
    local test_name="${4:-count check}"
    local actual=0
    while [[ "$output" =~ $pattern ]]; do
        actual=$((actual + 1))
        output="${output#*${BASH_REMATCH[0]}}"
    done
    if [ "$actual" -eq "$expected" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected $expected occurrences of: $pattern"
        echo "  Got: $actual"
        return 1
    fi
}

assert_order() {
    local output="$1"
    local pattern_a="$2"
    local pattern_b="$3"
    local test_name="${4:-order check}"
    local before_a after_a before_b after_b pos_a pos_b
    # Find position of pattern_a by measuring length before the match
    if [[ "$output" =~ $pattern_a ]]; then
        before_a="${output%%${BASH_REMATCH[0]}*}"
        pos_a=${#before_a}
    else
        echo "  [FAIL] $test_name - pattern not found"
        echo "  Missing: $pattern_a"
        return 1
    fi
    if [[ "$output" =~ $pattern_b ]]; then
        before_b="${output%%${BASH_REMATCH[0]}*}"
        pos_b=${#before_b}
    else
        echo "  [FAIL] $test_name - pattern not found"
        echo "  Missing: $pattern_b"
        return 1
    fi
    if [ "$pos_a" -lt "$pos_b" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name"
        echo "  Expected '$pattern_a' (pos $pos_a) before '$pattern_b' (pos $pos_b)"
        return 1
    fi
}

assert_valid_json() {
    local output="$1"
    local test_name="${2:-valid JSON}"
    if echo "$output" | jq . >/dev/null 2>&1; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name - not valid JSON"
        echo "    ${output:0:200}"
        return 1
    fi
}

assert_json_field() {
    local output="$1"
    local field="$2"
    local test_name="${3:-JSON field $field}"
    local value
    value=$(echo "$output" | jq -r "$field" 2>/dev/null)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name - field '$field' missing or null"
        return 1
    fi
}

# --- Sandbox ---

setup_sandbox() {
    SANDBOX=$(mktemp -d)
    mkdir -p "$SANDBOX/src/orca/base_api"
    mkdir -p "$SANDBOX/src/orca-sensor/pkg"
    mkdir -p "$SANDBOX/src/orca-runtime-sensor"
    mkdir -p "$SANDBOX/src/helm-charts"
    export SANDBOX
}

cleanup_sandbox() {
    if [ -n "$SANDBOX" ] && [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
        unset SANDBOX
    fi
}

# --- Runners ---

run_hook_from() {
    local dir="$1"
    local hook="${2:-$PLUGIN_ROOT/hooks/session-start}"
    (
        cd "$dir" && bash "$hook" 2>/dev/null
    )
}

run_claude() {
    local prompt="$1"
    local max_time="${2:-60}"
    local plugin_dir="${3:-$PLUGIN_ROOT}"
    local work_dir="${4:-$PLUGIN_ROOT}"
    local output_file
    output_file=$(mktemp)
    local timeout_cmd=""
    if command -v gtimeout &>/dev/null; then
        timeout_cmd="gtimeout $max_time"
    elif command -v timeout &>/dev/null; then
        timeout_cmd="timeout $max_time"
    fi
    (
        cd "$work_dir"
        # Unset both nesting-detection vars so claude can run inside Claude Code
        unset CLAUDECODE
        unset CLAUDE_CODE_ENTRYPOINT
        $timeout_cmd claude -p "$prompt" \
            --plugin-dir "$plugin_dir" \
            --dangerously-skip-permissions \
            --max-turns 2 \
            --output-format stream-json 2>&1
    ) > "$output_file" || true
    cat "$output_file"
    rm -f "$output_file"
}

# --- Exports ---

export -f assert_contains
export -f assert_not_contains
export -f assert_count
export -f assert_order
export -f assert_valid_json
export -f assert_json_field
export -f setup_sandbox
export -f cleanup_sandbox
export -f run_hook_from
export -f run_claude
export PLUGIN_ROOT
