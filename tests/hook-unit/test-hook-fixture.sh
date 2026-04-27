#!/usr/bin/env bash
# Run a single hook fixture: pipe stdin JSON through the hook script, assert on output.
# Usage: bash test-hook-fixture.sh <fixture.json> [plugin_root]
set -euo pipefail

FIXTURE="$1"
PLUGIN_ROOT="${2:-$(pwd)}"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

REPO="$TMP_ROOT/repo"
PLUGIN_DATA="$TMP_ROOT/plugin-data"
BIN="$TMP_ROOT/bin"
mkdir -p "$REPO/src/app" "$REPO/src/vendor-owned" "$REPO/vendor" "$REPO/docs" \
         "$PLUGIN_DATA" "$BIN"

cat > "$REPO/CLAUDE.md" <<'ENDMD'
<tool_routing>
source reads through codebase-memory-mcp
</tool_routing>
ENDMD

cat > "$BIN/rtk" <<'ENDRTK'
#!/usr/bin/env bash
[[ "$1" == "rewrite" ]] && shift && echo "rtk $*"
ENDRTK
chmod +x "$BIN/rtk"

substitute() {
  jq -c '.' \
    | sed "s#__REPO__#$REPO#g" \
    | sed "s#__TMP__#$TMP_ROOT#g" \
    | sed "s#__PLUGIN_DATA__#$PLUGIN_DATA#g" \
    | sed "s#__BIN__#$BIN#g" \
    | sed "s#__PATH__#$PATH#g"
}

STDIN_JSON="$(jq -c '.stdin' "$FIXTURE" | substitute)"
HOOK_PATH="$(jq -r '.hook' "$FIXTURE")"
EXPECT_CODE="$(jq -r '.expect.exit_code' "$FIXTURE")"

# Build env: each key as KEY=VALUE (with __REPO__ substitution)
ENV_ARGS=()
while IFS= read -r kv; do
  ENV_ARGS+=("$kv")
done < <(jq -r '.env // {} | to_entries[] | "\(.key)=\(.value)"' "$FIXTURE" \
         | sed "s#__REPO__#$REPO#g; s#__BIN__#$BIN#g; s#__PATH__#$PATH#g")

# Seed state files if specified
while IFS= read -r entry; do
  fname="$(jq -r '.name' <<<"$entry" | sed "s#__SESSION__#sess-001#g")"
  fcontent="$(jq -r '.content' <<<"$entry" | sed "s#__REPO__#$REPO#g")"
  echo "$fcontent" > "$PLUGIN_DATA/$fname"
done < <(jq -c '.state_files // [] | .[]' "$FIXTURE")

STDOUT="$TMP_ROOT/stdout"
STDERR="$TMP_ROOT/stderr"
set +e
env ${ENV_ARGS[@]+"${ENV_ARGS[@]}"} \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    CLAUDE_PLUGIN_DATA="$PLUGIN_DATA" \
    PATH="$BIN:$PATH" \
    bash "$PLUGIN_ROOT/$HOOK_PATH" >"$STDOUT" 2>"$STDERR" <<<"$STDIN_JSON"
CODE=$?
set -e

NAME="$(jq -r '.name' "$FIXTURE")"
fail() { echo "FAIL $NAME: $1" >&2; echo "--- stderr ---" >&2; cat "$STDERR" >&2; echo "--- stdout ---" >&2; cat "$STDOUT" >&2; exit 1; }

[[ "$CODE" == "$EXPECT_CODE" ]] || fail "exit code expected $EXPECT_CODE got $CODE"

if jq -e '.expect.stdout_json == true' "$FIXTURE" >/dev/null; then
  jq empty "$STDOUT" 2>/dev/null || fail "stdout is not valid JSON"
fi

while IFS= read -r kv; do
  [[ -z "$kv" ]] && continue
  k="${kv%%=*}"; v="${kv#*=}"
  got="$(jq -r "$k" "$STDOUT" 2>/dev/null)"
  [[ "$got" == "$v" ]] || fail "$k expected '$v' got '$got'"
done < <(jq -r '.expect.json_path_equals // {} | to_entries[] | "\(.key)=\(.value)"' "$FIXTURE")

while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  jq -e "$path" "$STDOUT" >/dev/null 2>&1 || fail "$path missing in stdout"
done < <(jq -r '.expect.json_path_exists // [] | .[]' "$FIXTURE")

if jq -e '.expect.stderr_contains' "$FIXTURE" >/dev/null; then
  needle="$(jq -r '.expect.stderr_contains' "$FIXTURE")"
  grep -qF "$needle" "$STDERR" || fail "stderr missing '$needle'"
fi

# Check state files were created
while IFS= read -r entry; do
  fname="$(jq -r '.name' <<<"$entry" | sed "s#__SESSION__#sess-001#g")"
  [[ -f "$PLUGIN_DATA/$fname" ]] || fail "expected state file $fname not created"
done < <(jq -c '.expect.state_files_created // [] | .[]' "$FIXTURE")

echo "PASS $NAME"
