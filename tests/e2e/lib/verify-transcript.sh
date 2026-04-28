#!/usr/bin/env bash
# Parse verbose JSON transcript, extract tool calls
# Verbose output is a JSON array on a single line: [{...},{...},...]
# Tool calls appear in {"type":"assistant","message":{"content":[{"type":"tool_use","name":"..."}]}}
set -euo pipefail

extract_tool_calls() {
    local transcript="$1"
    echo "$transcript" | jq -r '
        .[]? |
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use") |
        .name
    ' 2>/dev/null
}

extract_tool_namespaces() {
    local transcript="$1"
    extract_tool_calls "$transcript" | sed 's/__[^_]*$//' | sort -u
}

export -f extract_tool_calls
export -f extract_tool_namespaces
