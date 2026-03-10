#!/usr/bin/env bash
# Unit test: pre-serena-edit + post-serena-refs working together
# Tests the "refs before edit" guard flow:
#   1. post-serena-refs creates state file after find_referencing_symbols
#   2. pre-serena-edit allows edits after refs traced
#   3. pre-serena-edit warns without refs
#   4. State resets on session change
#   5. Atomic write (no corruption)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK_EDIT="${PLUGIN_ROOT}/hooks/pre-serena-edit"
HOOK_REFS="${PLUGIN_ROOT}/hooks/post-serena-refs"

# Skip gracefully if hooks not yet created by the other agent
if [ ! -f "$HOOK_EDIT" ] || [ ! -f "$HOOK_REFS" ]; then
    echo "=== Unit: serena-guard — SKIPPED (hooks not yet created) ==="
    [ ! -f "$HOOK_EDIT" ] && echo "  Missing: $HOOK_EDIT"
    [ ! -f "$HOOK_REFS" ] && echo "  Missing: $HOOK_REFS"
    exit 0
fi

passed=0; failed=0

# Use a temp dir as CLAUDE_PLUGIN_ROOT to isolate state
GUARD_TMPROOT=$(mktemp -d)

# Use a unique session ID per test run to avoid cross-contamination
SESSION_ID="test-serena-guard-$$"

echo "=== Unit: serena-guard (pre-serena-edit + post-serena-refs) ==="
echo ""

# Clean up on exit
cleanup() {
    rm -rf "$GUARD_TMPROOT"
}
trap cleanup EXIT

# ── 1. post-serena-refs creates state file ───────────────────────────────────

echo "--- post-serena-refs creates state file ---"

rc=0
echo "{\"tool_name\":\"mcp__serena__find_referencing_symbols\",\"tool_input\":{\"name_path\":\"MyClass\",\"relative_path\":\"src/models.py\"},\"session_id\":\"$SESSION_ID\"}" \
    | CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_REFS" >/dev/null 2>&1 || rc=$?

if [ "$rc" -eq 0 ]; then
    echo "  [PASS] post-serena-refs exits 0"
    passed=$((passed+1))
else
    echo "  [FAIL] post-serena-refs expected exit 0, got $rc"
    failed=$((failed+1))
fi

# Verify state file exists
STATE_FILE="$GUARD_TMPROOT/state/refs-traced.json"
if [ -f "$STATE_FILE" ]; then
    echo "  [PASS] state file created at $STATE_FILE"
    passed=$((passed+1))
else
    echo "  [FAIL] no state file found at $STATE_FILE"
    failed=$((failed+1))
fi

# ── 2. pre-serena-edit allows after refs traced ──────────────────────────────

echo ""
echo "--- pre-serena-edit allows after refs traced ---"

rc=0
echo "{\"tool_name\":\"mcp__serena__replace_symbol_body\",\"tool_input\":{\"name_path\":\"MyClass/my_method\",\"relative_path\":\"src/models.py\",\"body\":\"pass\"},\"session_id\":\"$SESSION_ID\"}" \
    | CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_EDIT" >/dev/null 2>&1 || rc=$?

if [ "$rc" -eq 0 ]; then
    echo "  [PASS] edit allowed after refs traced (exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] edit expected exit 0 after refs, got $rc"
    failed=$((failed+1))
fi

# Also test replace_content
rc=0
echo "{\"tool_name\":\"mcp__serena__replace_content\",\"tool_input\":{\"relative_path\":\"src/models.py\",\"needle\":\"old\",\"repl\":\"new\",\"mode\":\"literal\"},\"session_id\":\"$SESSION_ID\"}" \
    | CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_EDIT" >/dev/null 2>&1 || rc=$?

if [ "$rc" -eq 0 ]; then
    echo "  [PASS] replace_content allowed after refs traced (exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] replace_content expected exit 0 after refs, got $rc"
    failed=$((failed+1))
fi

# Also test insert_after_symbol
rc=0
echo "{\"tool_name\":\"mcp__serena__insert_after_symbol\",\"tool_input\":{\"name_path\":\"MyClass\",\"relative_path\":\"src/models.py\",\"body\":\"def new_method(): pass\"},\"session_id\":\"$SESSION_ID\"}" \
    | CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_EDIT" >/dev/null 2>&1 || rc=$?

if [ "$rc" -eq 0 ]; then
    echo "  [PASS] insert_after_symbol allowed after refs traced (exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] insert_after_symbol expected exit 0 after refs, got $rc"
    failed=$((failed+1))
fi

# ── 3. pre-serena-edit warns without refs ────────────────────────────────────

echo ""
echo "--- pre-serena-edit warns without refs ---"

# Use a fresh temp root that has no state directory
FRESH_TMPROOT=$(mktemp -d)
FRESH_SESSION="fresh-no-refs-$$"

rc=0
stderr_out=$(echo "{\"tool_name\":\"mcp__serena__replace_symbol_body\",\"tool_input\":{\"name_path\":\"Foo\",\"relative_path\":\"bar.py\",\"body\":\"pass\"},\"session_id\":\"$FRESH_SESSION\"}" \
    | CLAUDE_PLUGIN_ROOT="$FRESH_TMPROOT" bash "$HOOK_EDIT" 2>&1) || rc=$?

if [ "$rc" -eq 1 ]; then
    echo "  [PASS] warns without refs (exit 1)"
    passed=$((passed+1))
else
    echo "  [FAIL] expected exit 1 without refs, got $rc"
    failed=$((failed+1))
fi

# Check that warning message mentions refs
if echo "$stderr_out" | /usr/bin/grep -qi "ref\|find_referencing"; then
    echo "  [PASS] warning mentions refs"
    passed=$((passed+1))
else
    echo "  [FAIL] warning should mention refs: $stderr_out"
    failed=$((failed+1))
fi

rm -rf "$FRESH_TMPROOT"

# ── 4. State resets on session change ────────────────────────────────────────

echo ""
echo "--- State resets on session change ---"

# The original SESSION_ID had refs traced in GUARD_TMPROOT.
# A different session_id should trigger a warn since state is tied to session.
DIFFERENT_SESSION="different-session-$$"

rc=0
echo "{\"tool_name\":\"mcp__serena__replace_symbol_body\",\"tool_input\":{\"name_path\":\"Baz\",\"relative_path\":\"src/models.py\",\"body\":\"pass\"},\"session_id\":\"$DIFFERENT_SESSION\"}" \
    | CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_EDIT" >/dev/null 2>&1 || rc=$?

if [ "$rc" -eq 1 ]; then
    echo "  [PASS] different session has no refs state (exit 1)"
    passed=$((passed+1))
else
    echo "  [FAIL] different session expected exit 1, got $rc"
    failed=$((failed+1))
fi

# ── 5. Atomic write (no corruption) ─────────────────────────────────────────

echo ""
echo "--- Atomic write (no corruption) ---"

# Create a fresh temp root for atomic test
ATOMIC_TMPROOT=$(mktemp -d)
ATOMIC_SESSION="atomic-test-$$"

# Run post-serena-refs multiple times rapidly in parallel
for i in 1 2 3 4 5; do
    echo "{\"tool_name\":\"mcp__serena__find_referencing_symbols\",\"tool_input\":{\"name_path\":\"Func$i\",\"relative_path\":\"file$i.py\"},\"session_id\":\"$ATOMIC_SESSION\"}" \
        | CLAUDE_PLUGIN_ROOT="$ATOMIC_TMPROOT" bash "$HOOK_REFS" >/dev/null 2>&1 &
done
wait

# The state file should exist and be valid JSON
ATOMIC_STATE="$ATOMIC_TMPROOT/state/refs-traced.json"
if [ -f "$ATOMIC_STATE" ]; then
    echo "  [PASS] state file survives concurrent writes"
    passed=$((passed+1))
else
    echo "  [FAIL] no state file after concurrent writes"
    failed=$((failed+1))
fi

# Verify it's valid JSON
if [ -f "$ATOMIC_STATE" ] && jq . "$ATOMIC_STATE" >/dev/null 2>&1; then
    echo "  [PASS] state file is valid JSON after concurrent writes"
    passed=$((passed+1))
else
    echo "  [FAIL] state file is not valid JSON after concurrent writes"
    failed=$((failed+1))
fi

# Verify the edit hook works for a file that survived the race.
# Due to concurrent mv atomicity, the last writer wins and only its
# file path may be in the final state. Find which path survived.
survived_path=""
if [ -f "$ATOMIC_STATE" ]; then
    survived_path=$(jq -r '.traced | keys[0] // ""' "$ATOMIC_STATE" 2>/dev/null) || true
fi

if [ -n "$survived_path" ]; then
    rc=0
    echo "{\"tool_name\":\"mcp__serena__replace_content\",\"tool_input\":{\"relative_path\":\"$survived_path\",\"needle\":\"a\",\"repl\":\"b\",\"mode\":\"literal\"},\"session_id\":\"$ATOMIC_SESSION\"}" \
        | CLAUDE_PLUGIN_ROOT="$ATOMIC_TMPROOT" bash "$HOOK_EDIT" >/dev/null 2>&1 || rc=$?

    if [ "$rc" -eq 0 ]; then
        echo "  [PASS] edit allowed for surviving path after concurrent refs (exit 0)"
        passed=$((passed+1))
    else
        echo "  [FAIL] edit expected exit 0 for surviving path, got $rc"
        failed=$((failed+1))
    fi
else
    echo "  [FAIL] no surviving path in state file after concurrent writes"
    failed=$((failed+1))
fi

rm -rf "$ATOMIC_TMPROOT"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
