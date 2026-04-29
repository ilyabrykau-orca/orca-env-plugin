#!/usr/bin/env bash
# Unit test: rtk-rewrite-bash hook (behavioral contract)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK="${PLUGIN_ROOT}/hooks/rtk-rewrite-bash"
passed=0; failed=0

echo "=== Unit: rtk-rewrite-bash hook ==="
echo ""

# Helper: pipe JSON into hook, capture exit code and stdout
run_rtk_hook() {
    local json="$1"
    local stdout_file stderr_file
    stdout_file=$(mktemp); stderr_file=$(mktemp)
    local exit_code=0
    echo "$json" | bash "$HOOK" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    local stdout_out
    stdout_out=$(cat "$stdout_file")
    rm -f "$stdout_file" "$stderr_file"
    echo "${exit_code}|${stdout_out}"
}

# ─── Always exit 0 ─────────────────────────────────────────────────────────────

echo "--- Always exits 0 ---"

result=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"ls"}}')
exit_code="${result%%|*}"
if [ "$exit_code" = "0" ]; then
    echo "  [PASS] exits 0 for normal Bash command"
    passed=$((passed+1))
else
    echo "  [FAIL] exits 0 for normal Bash command (got $exit_code)"
    failed=$((failed+1))
fi

result=$(run_rtk_hook '{}')
exit_code="${result%%|*}"
if [ "$exit_code" = "0" ]; then
    echo "  [PASS] exits 0 for empty/malformed JSON"
    passed=$((passed+1))
else
    echo "  [FAIL] exits 0 for empty/malformed JSON (got $exit_code)"
    failed=$((failed+1))
fi

# ─── Non-Bash tool passes through (no output, exit 0) ─────────────────────────

echo ""
echo "--- Non-Bash tool passes through ---"

for tool in Read Edit Write Grep Glob mcp__serena__find_symbol; do
    result=$(run_rtk_hook "{\"tool_name\":\"${tool}\",\"tool_input\":{}}")
    exit_code="${result%%|*}"
    stdout="${result#*|}"
    if [ "$exit_code" = "0" ] && [ -z "$stdout" ]; then
        echo "  [PASS] $tool: exit 0, no output"
        passed=$((passed+1))
    else
        echo "  [FAIL] $tool: expected exit 0 + no output (got exit=$exit_code output='${stdout:0:80}')"
        failed=$((failed+1))
    fi
done

# ─── Empty command → exit 0, no output ────────────────────────────────────────

echo ""
echo "--- Empty command ---"

result=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":""}}')
exit_code="${result%%|*}"
stdout="${result#*|}"
if [ "$exit_code" = "0" ] && [ -z "$stdout" ]; then
    echo "  [PASS] empty command: exit 0, no output"
    passed=$((passed+1))
else
    echo "  [FAIL] empty command: expected exit 0 + no output (got exit=$exit_code output='${stdout:0:80}')"
    failed=$((failed+1))
fi

# ─── Shell metacharacters skip rewrite (no output, exit 0) ────────────────────

echo ""
echo "--- Shell metacharacters skip rewrite ---"

check_meta() {
    local label="$1"
    local json="$2"
    local result exit_code stdout
    result=$(run_rtk_hook "$json")
    exit_code="${result%%|*}"
    stdout="${result#*|}"
    if [ "$exit_code" = "0" ] && [ -z "$stdout" ]; then
        echo "  [PASS] metachar $label: exit 0, no output (skipped)"
        passed=$((passed+1))
    else
        echo "  [FAIL] metachar $label: expected exit 0 + no output (got exit=$exit_code output='${stdout:0:80}')"
        failed=$((failed+1))
    fi
}

check_meta "pipe |"     '{"tool_name":"Bash","tool_input":{"command":"ls | grep foo"}}'
check_meta "ampersand &" '{"tool_name":"Bash","tool_input":{"command":"sleep 1 & wait"}}'
check_meta "semicolon ;" '{"tool_name":"Bash","tool_input":{"command":"echo a; echo b"}}'
check_meta "redirect <"  '{"tool_name":"Bash","tool_input":{"command":"cat < file.txt"}}'
check_meta "redirect >"  '{"tool_name":"Bash","tool_input":{"command":"echo hi > out.txt"}}'
check_meta 'dollar $'    '{"tool_name":"Bash","tool_input":{"command":"echo $HOME"}}'
check_meta "backtick"    '{"tool_name":"Bash","tool_input":{"command":"echo `date`"}}'
check_meta "parens ()"   '{"tool_name":"Bash","tool_input":{"command":"(echo hi)"}}'
check_meta "braces {}"   '{"tool_name":"Bash","tool_input":{"command":"{ echo hi; }"}}'
check_meta "heredoc <<"  '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF\nhello\nEOF"}}'

# ─── RTK not installed → graceful fallthrough ─────────────────────────────────

echo ""
echo "--- RTK not installed: graceful fallthrough ---"

result=$(PATH=/usr/bin:/bin run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
exit_code="${result%%|*}"
stdout="${result#*|}"
if [ "$exit_code" = "0" ] && [ -z "$stdout" ]; then
    echo "  [PASS] missing rtk: exit 0, no output"
    passed=$((passed+1))
else
    echo "  [FAIL] missing rtk: expected exit 0 + no output (got exit=$exit_code output='${stdout:0:80}')"
    failed=$((failed+1))
fi

# ─── CLAUDE_RAW=1 skips rewrite ───────────────────────────────────────────────

echo ""
echo "--- CLAUDE_RAW=1 bypass ---"

result=$(CLAUDE_RAW=1 run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
exit_code="${result%%|*}"
stdout="${result#*|}"
if [ "$exit_code" = "0" ] && [ -z "$stdout" ]; then
    echo "  [PASS] CLAUDE_RAW=1: exit 0, no output"
    passed=$((passed+1))
else
    echo "  [FAIL] CLAUDE_RAW=1: expected exit 0 + no output (got exit=$exit_code output='${stdout:0:80}')"
    failed=$((failed+1))
fi

# ─── RTK available: git status → JSON with updatedInput.command ──────────────

echo ""
echo "--- RTK available: produces rewrite JSON ---"

if command -v rtk >/dev/null 2>&1; then
    # Verify rtk actually rewrites "git status" before testing the hook.
    # If rtk does not rewrite it, there is nothing to assert.
    rewritten=$(rtk rewrite "git status" 2>/dev/null || true)

    result=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
    exit_code="${result%%|*}"
    stdout="${result#*|}"

    if [ "$exit_code" = "0" ]; then
        echo "  [PASS] rtk present: exit 0"
        passed=$((passed+1))
    else
        echo "  [FAIL] rtk present: expected exit 0 (got $exit_code)"
        failed=$((failed+1))
    fi

    if [ -n "$rewritten" ] && [ "$rewritten" != "git status" ]; then
        # rtk rewrites the command — hook MUST produce JSON
        if echo "$stdout" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1; then
            echo "  [PASS] rtk rewrite: JSON has hookSpecificOutput.updatedInput.command"
            passed=$((passed+1))
        else
            echo "  [FAIL] rtk rewrite: JSON missing hookSpecificOutput.updatedInput.command (hook produced: '${stdout:0:200}')"
            failed=$((failed+1))
        fi
    else
        echo "  [SKIP] rtk did not rewrite 'git status' — skipping JSON output assertion"
    fi
else
    echo "  [SKIP] rtk not found in PATH — skipping rewrite output test"
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
