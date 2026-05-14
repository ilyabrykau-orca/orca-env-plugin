#!/usr/bin/env bash
# Deep replay: classify each routing-relevant tool_use as DENIED/SLIPPED/PASS by
# correlating tool_use IDs against matching tool_result content.
#
# Outputs:
#   - aggregate bypass split (DENIED vs SLIPPED) per tool family
#   - parent vs subagent breakdown
#   - per-cwd top offenders
#   - top sessions by SLIPPED count
set -o pipefail

PROJECTS_DIR="${HOME}/.claude/projects"
SINCE=""
JOBS=8
FORMAT="report"
CACHE_DIR="${TMPDIR:-/tmp}/orca-replay-cache"
NO_CACHE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --since)    SINCE="$2"; shift 2 ;;
    --jobs)     JOBS="$2";  shift 2 ;;
    --csv)      FORMAT="csv"; shift ;;
    --tsv)      FORMAT="tsv"; shift ;;
    --report)   FORMAT="report"; shift ;;
    --no-cache) NO_CACHE=1; shift ;;
    *)          echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE_DIR"

LIST=$(mktemp)
TMP=$(mktemp)
trap 'rm -f "$LIST" "$TMP"' EXIT

if [ -n "$SINCE" ]; then
  find "$PROJECTS_DIR" -name '*.jsonl' -type f -size +1k -newermt "$SINCE" 2>/dev/null > "$LIST"
else
  find "$PROJECTS_DIR" -name '*.jsonl' -type f -size +1k 2>/dev/null > "$LIST"
fi

n=$(wc -l < "$LIST" | tr -d ' ')
echo "Scanning $n transcripts..." >&2

# Per call: emit one TSV line per routing-relevant tool_use:
#   cwd \t kind \t tool \t verdict \t session_path
# kind: native_code | serena_read | cbm_read
# verdict: DENIED | SLIPPED | PASS
JQ_PROG='
  . as $events |
  ([$events[] | .cwd // empty] | last // "?") as $cwd |
  ([$events[]
    | select(.type=="user")
    | .message as $m
    | (if ($m.content | type)=="array" then $m.content[] else empty end)
    | select(.type=="tool_result")
    | {id: .tool_use_id, err: (.is_error // false), text: (.content | tostring)}
   ]) as $results |
  ($results | map({(.id): .}) | add // {}) as $rmap |
  $events[]
  | select(.type=="assistant")
  | (.message.content // []) as $c
  | (if ($c | type)=="array" then $c[] else empty end)
  | select(.type=="tool_use")
  | . as $u
  | ($u.input.file_path // $u.input.pattern // "") as $fp
  | ($rmap[$u.id] // {err:false, text:""}) as $r
  | (
      if ($u.name | test("^(Read|Edit|Write|Grep|Glob)$")) and ($fp | test("\\.(py|go|ts|tsx|js|jsx|rs|cpp|c|h|hpp|rb|java)$"))
        then {kind:"native_code", tool: $u.name}
      elif ($u.name | test("^mcp__serena__(find_symbol|get_symbols_overview|search_for_pattern|read_file|list_dir|find_file)$"))
        then {kind:"serena_read", tool: ($u.name | sub("^mcp__serena__";""))}
      elif ($u.name | test("^mcp__codebase-memory-mcp__"))
        then {kind:"cbm_read",   tool: ($u.name | sub("^mcp__codebase-memory-mcp__";""))}
      else empty end
    ) as $klass
  | (
      if $r.text | test("PreToolUse:[A-Za-z_]+ hook error|BLOCKED[.:]|serena-edit-guard|find_referencing_symbols first|Serena read tools are a FALLBACK|Tool .* not allowed|Action denied|denied permission"; "i")
        then "DENIED"
      elif $r.err
        then "ERROR"
      else "PASS" end
    ) as $verdict
  | [$cwd, $klass.kind, $klass.tool, $verdict] | @tsv
'

process_one() {
  local f="$1"
  local cache="$CACHE_DIR/$(echo "$f" | tr / _).tsv"
  if [ "$NO_CACHE" = "0" ] && [ -f "$cache" ] && [ "$cache" -nt "$f" ]; then
    cat "$cache"
    return
  fi
  jq -s -r "$JQ_PROG" "$f" 2>/dev/null | sed "s|$|	$f|" | tee "$cache"
}
export -f process_one
export JQ_PROG CACHE_DIR NO_CACHE

xargs -P "$JOBS" -I{} bash -c 'process_one "{}"' < "$LIST" > "$TMP"

if [ "$FORMAT" = "tsv" ]; then
  cat "$TMP"
  exit 0
fi
if [ "$FORMAT" = "csv" ]; then
  awk -F'\t' 'BEGIN{print "cwd,kind,tool,verdict,session"} {gsub(/"/,"\"\"",$1); gsub(/"/,"\"\"",$5); printf "\"%s\",%s,%s,%s,\"%s\"\n", $1,$2,$3,$4,$5}' "$TMP"
  exit 0
fi

echo
echo "========== verdict × kind ==========="
awk -F'\t' '$2 != "" { k=$2"|"$4; c[k]++ } END { for (kk in c) printf "%-30s %d\n", kk, c[kk] }' "$TMP" | sort

echo
echo "========== native_code by tool × verdict =========="
awk -F'\t' '$2=="native_code" { k=$3"|"$4; c[k]++ } END { for (kk in c) printf "%-25s %d\n", kk, c[kk] }' "$TMP" | sort

echo
echo "========== serena_read by tool × verdict =========="
awk -F'\t' '$2=="serena_read" { k=$3"|"$4; c[k]++ } END { for (kk in c) printf "%-30s %d\n", kk, c[kk] }' "$TMP" | sort

echo
echo "========== parent vs subagent (only bypass calls) =========="
awk -F'\t' '
  $4=="PASS" && ($2=="native_code" || $2=="serena_read") {
    kind = ($5 ~ /\/subagents\//) ? "subagent" : "parent"
    c[kind"|"$2]++
  }
  END { for (k in c) printf "%-25s %d\n", k, c[k] }
' "$TMP" | sort

echo
echo "========== top-15 cwd by SLIPPED bypass =========="
awk -F'\t' '
  $4=="PASS" && ($2=="native_code" || $2=="serena_read") { c[$1]++ }
  END { for (k in c) printf "%6d\t%s\n", c[k], k }
' "$TMP" | sort -rn | head -15

echo
echo "========== top-15 sessions by SLIPPED bypass =========="
awk -F'\t' '
  $4=="PASS" && ($2=="native_code" || $2=="serena_read") { c[$5]++ }
  END { for (k in c) printf "%6d\t%s\n", c[k], k }
' "$TMP" | sort -rn | head -15 | sed "s|$HOME/.claude/projects/||"
