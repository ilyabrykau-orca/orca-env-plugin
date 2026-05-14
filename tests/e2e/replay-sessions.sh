#!/usr/bin/env bash
# Replay routing-policy stats across all Claude Code session transcripts.
# Counts per session: total tool_use, cbm reads (passed), serena reads (bypassed),
# serena edits (allowed), native on code (bypassed), denied (tool_result is_error).
#
# Usage:
#   bash tests/e2e/replay-sessions.sh                       # all sessions
#   bash tests/e2e/replay-sessions.sh --since 2026-05-01    # mtime filter
#   bash tests/e2e/replay-sessions.sh --top 20              # only top-N violators
#   bash tests/e2e/replay-sessions.sh --jobs 8              # parallel jq
set -o pipefail

PROJECTS_DIR="${HOME}/.claude/projects"
SINCE=""
TOP=0
JOBS=4

while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --top)   TOP="$2";   shift 2 ;;
    --jobs)  JOBS="$2";  shift 2 ;;
    *)       echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT

if [ -n "$SINCE" ]; then
  find "$PROJECTS_DIR" -name '*.jsonl' -type f -size +1k -newermt "$SINCE" 2>/dev/null > "$LIST"
else
  find "$PROJECTS_DIR" -name '*.jsonl' -type f -size +1k 2>/dev/null > "$LIST"
fi

n=$(wc -l < "$LIST" | tr -d ' ')
echo "Scanning $n session transcripts..." >&2

JQ_PROG='
  [.[] | select(.type=="assistant") | (.message.content // []) | .[]? | select(.type=="tool_use")] as $tools |
  [.[] | select(.type=="user") | (.message.content // []) | .[]? | select(.type=="tool_result")] as $results |
  {
    total: ($tools | length),
    cbm: [$tools[] | select(.name|test("^mcp__codebase-memory-mcp__"))] | length,
    serena_read: [$tools[] | select(.name|test("^mcp__serena__(find_symbol|get_symbols_overview|search_for_pattern|read_file|list_dir|find_file)$"))] | length,
    serena_edit: [$tools[] | select(.name|test("^mcp__serena__(replace|insert|rename|safe_delete|find_referencing|activate|.*_memory|initial_instructions)"))] | length,
    native_code: [$tools[] | select(.name=="Read" or .name=="Edit" or .name=="Write" or .name=="Grep" or .name=="Glob") | select((.input.file_path // .input.pattern // "")|test("\\.(py|go|ts|tsx|js|jsx|rs|cpp|c|h|hpp|rb|java)$"))] | length,
    denied: [$results[] | select(.is_error==true) | select((.content // [] | tostring) | test("denied|blocked|permission|not allowed";"i"))] | length
  } | [.total, .cbm, .serena_read, .serena_edit, .native_code, .denied] | @tsv
'

process_one() {
  local f="$1"
  local row
  row=$(jq -s -r "$JQ_PROG" "$f" 2>/dev/null) || row="0	0	0	0	0	0"
  printf '%s\t%s\n' "$row" "$f"
}
export -f process_one
export JQ_PROG

TMP=$(mktemp)
trap 'rm -f "$LIST" "$TMP"' EXIT

xargs -P "$JOBS" -I{} bash -c 'process_one "{}"' < "$LIST" > "$TMP"

awk_summary=$(awk -F'\t' '
  $1 > 0 { active++ }
  { t+=$1; cbm+=$2; sr+=$3; se+=$4; nc+=$5; d+=$6 }
  END {
    printf "active_sessions=%d\n", active
    printf "total_tool_uses=%d\n", t
    printf "cbm_reads=%d\n", cbm
    printf "serena_reads_BYPASS=%d\n", sr
    printf "serena_edits_OK=%d\n", se
    printf "native_on_code_BYPASS=%d\n", nc
    printf "denied=%d\n", d
    pol = (cbm + sr + nc); pol = (pol == 0 ? 1 : pol)
    printf "pass_rate=%.2f%%\n", 100.0 * cbm / pol
    printf "bypass_rate=%.2f%%\n", 100.0 * (sr + nc) / pol
  }
' "$TMP")

echo
echo "========== AGGREGATE =========="
echo "$awk_summary"
echo "==============================="
echo

# Per-session table: sort by bypass count desc (serena_read + native_code)
echo "Per-session breakdown (sorted by bypass count desc):"
echo
printf '%-7s %-7s %-12s %-12s %-12s %-7s  %s\n' \
  total cbm serena_R serena_E native_C denied file
echo "---------------------------------------------------------------------------------------------"

SORTED=$(awk -F'\t' '
  $1 > 0 {
    bypass = $3 + $5
    printf "%d\t%s\n", bypass, $0
  }
' "$TMP" | sort -rn | cut -f2-)

if [ "$TOP" -gt 0 ]; then
  SORTED=$(echo "$SORTED" | head -n "$TOP")
fi

echo "$SORTED" | awk -F'\t' -v home="$HOME" '
  {
    f = $7
    sub(home "/.claude/projects/", "", f)
    printf "%-7s %-7s %-12s %-12s %-12s %-7s  %s\n", $1, $2, $3, $4, $5, $6, f
  }
'
