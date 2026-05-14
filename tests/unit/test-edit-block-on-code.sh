#!/usr/bin/env bash
# Unit test: pre-tool-router denies Edit/Write/Read on code files.
# Locks in the Layer-2 hard-block from hooks/pre-tool-router.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK="${PLUGIN_ROOT}/hooks/pre-tool-router"
passed=0; failed=0

echo "=== Unit: pre-tool-router native-on-code block ==="

check_block() {
    local tool="$1"
    local path="$2"
    local label="$3"
    local input
    # build JSON with python to guarantee valid escaping (matches Claude Code shape)
    input=$(python3 -c "import json,sys; print(json.dumps({'tool_name':sys.argv[1],'tool_input':{'file_path':sys.argv[2],'old_string':'a\tb\nc','new_string':'x','content':'x','replace_all':False},'session_id':'unit-001'}))" "$tool" "$path")
    local out rc
    out=$(printf '%s' "$input" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
    if [ "$rc" -eq 2 ] && echo "$out" | grep -q "BLOCKED: Native $tool"; then
        echo "  [PASS] $label  (exit 2, BLOCKED message)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label  (rc=$rc, out=${out:0:120})"
        failed=$((failed+1))
    fi
}

check_allow() {
    local tool="$1"
    local path="$2"
    local label="$3"
    local input rc
    input=$(python3 -c "import json,sys; print(json.dumps({'tool_name':sys.argv[1],'tool_input':{'file_path':sys.argv[2],'content':'x'},'session_id':'unit-001'}))" "$tool" "$path")
    printf '%s' "$input" | bash "$HOOK" >/dev/null 2>&1 && rc=$? || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "  [PASS] $label  (exit 0)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $label  (rc=$rc — expected allow)"
        failed=$((failed+1))
    fi
}

# --- DENY paths: native tools on code files ---
check_block Read  "/tmp/x.go"   "Read on .go denied"
check_block Edit  "/tmp/x.go"   "Edit on .go denied"
check_block Write "/tmp/x.py"   "Write on .py denied"
check_block Read  "/tmp/x.ts"   "Read on .ts denied"
check_block Edit  "/tmp/x.tsx"  "Edit on .tsx denied"
check_block Read  "/tmp/x.rs"   "Read on .rs denied"
check_block Edit  "/tmp/x.java" "Edit on .java denied"

# --- DENY: escaped tabs/newlines inside old_string (production payload shape) ---
INPUT=$(python3 -c "import json; print(json.dumps({'tool_name':'Edit','tool_input':{'file_path':'/tmp/foo.go','old_string':'\terr := pkg.Fn()\n\tif err != nil {\n\t\treturn fmt.Errorf(\"x: %w\", err)\n\t}','new_string':'x'},'session_id':'unit-001'}))")
out=$(printf '%s' "$INPUT" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "BLOCKED: Native Edit"; then
    echo "  [PASS] Edit with embedded \\t\\n in old_string denied"
    passed=$((passed+1))
else
    echo "  [FAIL] Edit with embedded \\t\\n in old_string  (rc=$rc, out=${out:0:200})"
    failed=$((failed+1))
fi

# --- ALLOW paths: native tools on non-code files ---
check_allow Read  "/tmp/x.json"      "Read on .json allowed"
check_allow Read  "/tmp/x.md"        "Read on .md allowed"
check_allow Edit  "/tmp/x.yaml"      "Edit on .yaml allowed"
check_allow Write "/tmp/Dockerfile"  "Write on Dockerfile allowed"

# --- Grep/Glob unconditional block (Layer 1) ---
INPUT_GREP=$(python3 -c "import json; print(json.dumps({'tool_name':'Grep','tool_input':{'pattern':'foo','path':'.'},'session_id':'unit-001'}))")
out=$(printf '%s' "$INPUT_GREP" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "BLOCKED: Native Grep"; then
    echo "  [PASS] Grep unconditionally denied"
    passed=$((passed+1))
else
    echo "  [FAIL] Grep deny (rc=$rc, out=${out:0:120})"
    failed=$((failed+1))
fi

INPUT_GLOB=$(python3 -c "import json; print(json.dumps({'tool_name':'Glob','tool_input':{'pattern':'**/*.go'},'session_id':'unit-001'}))")
out=$(printf '%s' "$INPUT_GLOB" | bash "$HOOK" 2>&1) && rc=$? || rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q "BLOCKED: Native Glob"; then
    echo "  [PASS] Glob unconditionally denied"
    passed=$((passed+1))
else
    echo "  [FAIL] Glob deny (rc=$rc, out=${out:0:120})"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
