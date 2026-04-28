#!/usr/bin/env bash
# Parse verbose JSON transcript, extract tool calls
# Verbose output is JSONL: each line is one event object.
# Tool calls appear in {"type":"assistant","message":{"content":[{"type":"tool_use","name":"..."}]}}
set -euo pipefail

extract_tool_calls() {
    local transcript="$1"
    echo "$transcript" | while IFS= read -r line; do
        echo "$line" | jq -r '
            select(.type == "assistant") |
            .message.content[]? |
            select(.type == "tool_use") |
            .name
        ' 2>/dev/null
    done
}

extract_tool_namespaces() {
    local transcript="$1"
    extract_tool_calls "$transcript" | sed 's/__[^_]*$//' | sort -u
}

export -f extract_tool_calls
export -f extract_tool_namespaces
