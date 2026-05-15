#!/usr/bin/env bash
# Launch a claude -p session with plugin-dir, capture stream-json transcript
set -euo pipefail

_LAUNCH_SESSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${_LAUNCH_SESSION_DIR}/../../.." && pwd)"

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

    # NOTE: as of 2026-05-15 we drop --plugin-dir so the test exercises the
    # same load path real users hit (orca-env-plugin loaded via settings.json
    # `enabledPlugins`). If you re-add --plugin-dir, every routing assertion
    # also passes when the plugin is disabled in settings — that hides regressions
    # in the settings-load path. See docs/notes/routing-e2e-report-2026-05-14.md.
    (
        cd "$work_dir"
        unset CLAUDECODE
        unset CLAUDE_CODE_ENTRYPOINT
        $timeout_cmd claude -p "$prompt" \
            --dangerously-skip-permissions \
            --max-turns "$max_turns" \
            --output-format json \
            --verbose 2>/dev/null
    ) > "$output_file" || true

    cat "$output_file"
    rm -f "$output_file"
}

export -f launch_session
export PLUGIN_ROOT
