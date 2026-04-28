#!/usr/bin/env bash
# Launch a claude -p session with plugin-dir, capture stream-json transcript
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

launch_session() {
    local prompt="$1"
    local work_dir="${2:-$HOME/src}"
    local max_turns="${3:-3}"
    local max_time="${4:-120}"
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
        unset CLAUDECODE
        unset CLAUDE_CODE_ENTRYPOINT
        $timeout_cmd claude -p "$prompt" \
            --plugin-dir "$PLUGIN_ROOT" \
            --dangerously-skip-permissions \
            --max-turns "$max_turns" \
            --output-format stream-json 2>&1
    ) > "$output_file" || true

    cat "$output_file"
    rm -f "$output_file"
}

export -f launch_session
export PLUGIN_ROOT
