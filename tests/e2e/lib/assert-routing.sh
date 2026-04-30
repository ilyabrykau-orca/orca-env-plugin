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

# CBM read tools — these SHOULD dominate code exploration
_CBM_READ_TOOLS='mcp__codebase-memory-mcp__search_code|mcp__codebase-memory-mcp__search_graph|mcp__codebase-memory-mcp__get_code_snippet|mcp__codebase-memory-mcp__trace_call_path|mcp__codebase-memory-mcp__query_graph|mcp__codebase-memory-mcp__semantic_query|mcp__codebase-memory-mcp__get_architecture|mcp__codebase-memory-mcp__detect_changes|mcp__codebase-memory-mcp__get_graph_schema'

# Serena read tools — these are VIOLATIONS when they dominate reads
_SERENA_READ_TOOLS='mcp__serena__find_symbol|mcp__serena__get_symbols_overview|mcp__serena__search_for_pattern|mcp__serena__read_file|mcp__serena__list_dir|mcp__serena__find_file'

# Serena edit/admin tools — allowed, not counted as reads
_SERENA_EDIT_ADMIN_TOOLS='mcp__serena__replace_symbol_body|mcp__serena__replace_content|mcp__serena__insert_after_symbol|mcp__serena__insert_before_symbol|mcp__serena__rename_symbol|mcp__serena__find_referencing_symbols|mcp__serena__activate_project|mcp__serena__list_memories|mcp__serena__read_memory|mcp__serena__write_memory|mcp__serena__edit_memory|mcp__serena__initial_instructions|mcp__serena__safe_delete_symbol'

assert_cbm_dominates_reads() {
    local transcript="$1"
    local test_name="$2"
    local tools
    tools=$(extract_tool_calls "$transcript")

    local cbm_reads serena_reads
    cbm_reads=$(echo "$tools" | grep -cE "^(${_CBM_READ_TOOLS})$" || true)
    serena_reads=$(echo "$tools" | grep -cE "^(${_SERENA_READ_TOOLS})$" || true)

    if [ "$cbm_reads" -eq 0 ] && [ "$serena_reads" -eq 0 ]; then
        echo "  [PASS] $test_name (no read activity)"
        return 0
    fi

    if [ "$cbm_reads" -ge "$serena_reads" ]; then
        echo "  [PASS] $test_name (CBM=$cbm_reads >= Serena=$serena_reads)"
        return 0
    else
        local offenders
        offenders=$(echo "$tools" | grep -E "^(${_SERENA_READ_TOOLS})$" | sort | uniq -c | sort -rn || true)
        echo "  [FAIL] $test_name — Serena reads ($serena_reads) > CBM reads ($cbm_reads)"
        echo "         Offending Serena read calls:"
        echo "$offenders" | sed 's/^/           /'
        return 1
    fi
}

assert_serena_only_for_edits() {
    local transcript="$1"
    local test_name="$2"
    local tools
    tools=$(extract_tool_calls "$transcript")

    local serena_calls
    serena_calls=$(echo "$tools" | grep "^mcp__serena__" || true)

    if [ -z "$serena_calls" ]; then
        echo "  [PASS] $test_name (no Serena calls)"
        return 0
    fi

    local violations
    violations=$(echo "$serena_calls" | grep -vE "^(${_SERENA_EDIT_ADMIN_TOOLS})$" || true)

    if [ -z "$violations" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        local violation_summary
        violation_summary=$(echo "$violations" | sort | uniq -c | sort -rn)
        echo "  [FAIL] $test_name — Serena read tools used (should use CBM):"
        echo "$violation_summary" | sed 's/^/           /'
        return 1
    fi
}

export -f assert_tool_used
export -f assert_tool_not_used
export -f assert_tool_before
export -f assert_no_native_on_code
export -f assert_cbm_dominates_reads
export -f assert_serena_only_for_edits
export _CBM_READ_TOOLS
export _SERENA_READ_TOOLS
export _SERENA_EDIT_ADMIN_TOOLS

# ─── CBM Empty-Fallback Assertion ───────────────────────────────────────────────
# Detects the production failure: CBM returns empty → Claude falls back to
# Serena reads instead of retrying CBM with different params/tool.

assert_cbm_retries_on_empty() {
    local transcript="$1"
    local test_name="$2"
    local failures=0
    local checked=0

    # Extract all CBM read tool_use IDs and their inputs
    local cbm_read_calls
    cbm_read_calls=$(echo "$transcript" | jq -r '
        [range(length)] as $indices |
        [$indices[] | select(
            .[$indices[.]] |
            (try (.type == "assistant" and
                  (.message.content[]? | select(.type == "tool_use") |
                   .name | test("^mcp__codebase-memory-mcp__")))
            catch false)
        )] | .[]
    ' 2>/dev/null || true)

    # Build a map of tool_use_id → (position, name, input_json)
    # Then find which ones got empty results
    local empty_cbm_info
    empty_cbm_info=$(echo "$transcript" | jq -r '
        . as $t |
        [range(length)] | map(
            . as $i |
            $t[$i] |
            select(.type == "assistant") |
            .message.content[]? |
            select(.type == "tool_use") |
            select(.name | test("^mcp__codebase-memory-mcp__")) |
            select(.name | test("(list_projects|index_repository|index_status|delete_project|manage_adr|ingest_traces|detect_changes)$") | not) |
            {id: .id, name: .name, input: .input, pos: $i}
        ) |
        . as $cbm_calls |
        [range($t | length)] | map(
            . as $j |
            $t[$j] |
            select(.type == "user") |
            .message.content[]? |
            select(.type == "tool_result") |
            . as $result |
            $cbm_calls[] |
            select(.id == $result.tool_use_id) |
            select(
                ($result.content | length == 0) or
                ($result.content[]? | .text // "" |
                    (test("\"results\"\\s*:\\s*\\[\\s*\\]") or
                     test("\"matches\"\\s*:\\s*\\[\\s*\\]") or
                     test("^\\s*\\[\\s*\\]\\s*$") or
                     test("[Nn]o symbols found") or
                     test("[Nn]o results") or
                     test("0 results") or
                     test("[Pp]roject .* not found") or
                     . == "" or . == "null"))
            ) |
            {id: .id, name: .name, input: .input, pos: .pos}
        ) |
        unique_by(.id) |
        .[] | @json
    ' 2>/dev/null || true)

    if [ -z "$empty_cbm_info" ]; then
        echo "  [PASS] $test_name (no empty CBM results detected)"
        return 0
    fi

    while IFS= read -r empty_call_json; do
        [ -z "$empty_call_json" ] && continue
        checked=$((checked + 1))

        local empty_id empty_name empty_pos empty_input
        empty_id=$(echo "$empty_call_json" | jq -r '.id')
        empty_name=$(echo "$empty_call_json" | jq -r '.name')
        empty_pos=$(echo "$empty_call_json" | jq -r '.pos')
        empty_input=$(echo "$empty_call_json" | jq -c '.input')

        # Find the next tool_use in any later assistant turn
        local next_tool_info
        next_tool_info=$(echo "$transcript" | jq -r --argjson pos "$empty_pos" '
            [range(length)] | map(
                select(. > $pos) |
                . as $k |
                input[$k] // null
            ) | map(select(. != null)) |
            first(
                .[] |
                select(.type == "assistant") |
                .message.content[]? |
                select(.type == "tool_use") |
                {name: .name, input: .input}
            ) // null
        ' 2>/dev/null || true)

        # Fallback: re-extract with simpler logic
        if [ -z "$next_tool_info" ] || [ "$next_tool_info" = "null" ]; then
            next_tool_info=$(echo "$transcript" | jq -r --argjson pos "$empty_pos" '
                . as $t |
                [ range($pos + 1; length) ] |
                map($t[.]) |
                map(select(.type == "assistant")) |
                map(.message.content[]? | select(.type == "tool_use")) |
                first // null |
                if . then {name: .name, input: .input} else null end
            ' 2>/dev/null || true)
        fi

        if [ -z "$next_tool_info" ] || [ "$next_tool_info" = "null" ]; then
            # PASS_TERMINAL: no further tool calls
            continue
        fi

        local next_name
        next_name=$(echo "$next_tool_info" | jq -r '.name // empty')

        # Classify the next tool call
        if echo "$next_name" | grep -qE "^mcp__codebase-memory-mcp__"; then
            # CBM tool — could be PASS_RETRY or PASS_PIVOT
            # Check if it's a different CBM family (pivot) or same tool with different params (retry)
            continue
        elif echo "$next_name" | grep -qE "^(${_SERENA_READ_TOOLS})$"; then
            # FAIL_FALLBACK: Serena read after empty CBM
            failures=$((failures + 1))
            echo "  [FAIL] $test_name — empty CBM '${empty_name}' (input: ${empty_input}) followed by Serena read '${next_name}'"
        elif echo "$next_name" | grep -qE "^(Read|Grep|Glob)$"; then
            # FAIL_NATIVE: native read after empty CBM
            failures=$((failures + 1))
            echo "  [FAIL] $test_name — empty CBM '${empty_name}' followed by native '${next_name}'"
        else
            # Other tool (ToolSearch, Bash, headroom, etc.) — not a routing violation
            continue
        fi
    done <<< "$empty_cbm_info"

    if [ "$failures" -eq 0 ]; then
        echo "  [PASS] $test_name (checked $checked empty CBM calls, all handled correctly)"
        return 0
    else
        echo "  [FAIL] $test_name — $failures of $checked empty CBM calls fell back to non-CBM reads"
        return 1
    fi
}

export -f assert_cbm_retries_on_empty
