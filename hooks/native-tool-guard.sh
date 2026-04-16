#!/usr/bin/env bash
# native-tool-guard.sh — PreToolUse hook for Read/Grep/Glob/Search/Edit/Write.
# Blocks native tools on source-code files under ~/src.
# Allows native tools on docs/config/logs/diffs/generated output/~/.claude/.
# Fails open on ambiguous or unrecognized cases.

set -u

LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/hooks.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

JQ=$(command -v jq 2>/dev/null) || { exit 0; }

log_json() {
  local action="$1" tool="$2" path="$3" reason="$4"
  "$JQ" -cn \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg hook "native-tool-guard" \
    --arg action "$action" \
    --arg tool "$tool" \
    --arg path "$path" \
    --arg reason "$reason" \
    '{ts:$ts,hook:$hook,action:$action,tool:$tool,path:$path,reason:$reason}' >> "$LOG_FILE" 2>/dev/null || true
}

INPUT=$(cat)
TOOL_NAME=$("$JQ" -r '.tool_name // ""' <<< "$INPUT" 2>/dev/null) || exit 0
FILE_PATH=$("$JQ" -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' <<< "$INPUT" 2>/dev/null) || exit 0
GLOB_PATTERN=$("$JQ" -r '.tool_input.pattern // ""' <<< "$INPUT" 2>/dev/null) || GLOB_PATTERN=""
GREP_TYPE=$("$JQ" -r '.tool_input.type // ""' <<< "$INPUT" 2>/dev/null) || GREP_TYPE=""
GREP_GLOB=$("$JQ" -r '.tool_input.glob // ""' <<< "$INPUT" 2>/dev/null) || GREP_GLOB=""

# No file path -> fail open
if [[ -z "$FILE_PATH" ]]; then
  log_json "skip" "$TOOL_NAME" "(no path)" "no_file_path"
  exit 0
fi

# Resolve to absolute. Handle ~ prefix.
case "$FILE_PATH" in
  /*)  ABS_PATH="$FILE_PATH" ;;
  '~'/*) ABS_PATH="${HOME}/${FILE_PATH#\~/}" ;;
  *)   ABS_PATH="$(pwd)/$FILE_PATH" ;;
esac

# Allow anything under ~/.claude/
case "$ABS_PATH" in
  "${HOME}/.claude"*|"${HOME}/.claude/"*)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "dotclaude_path"
    exit 0
    ;;
esac

# Allow anything outside ~/src
SRC_DIR="${HOME}/src"
case "$ABS_PATH" in
  "${SRC_DIR}"/*) ;; # continue to check
  *)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "outside_src"
    exit 0
    ;;
esac

# Inside ~/src — check extension
BASENAME="${ABS_PATH##*/}"
EXT=""
case "$BASENAME" in
  *.*) EXT="${BASENAME##*.}" ;;
esac

# Allowed extensions/names — docs, config, logs, generated output
case "$EXT" in
  md|txt|rst|json|yaml|yml|toml|ini|cfg|conf|env|lock|sum|mod|csv|svg|png|jpg|gif|ico|html|css|scss|less|xml|xsd|proto|tmpl|tpl|hcl|tf|tfvars|sql|graphql|gql|log|out|pid|sock|patch|diff)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "allowed_ext"
    exit 0
    ;;
esac

# Allowed by filename pattern
case "$BASENAME" in
  README*|LICENSE*|CHANGELOG*|CONTRIBUTING*|Makefile|Dockerfile*|docker-compose*|Taskfile*|Justfile*|Vagrantfile*|Brewfile*|Gemfile*|Procfile*|.gitignore|.gitattributes|.dockerignore|.editorconfig|.prettierrc*|.eslintrc*|.golangci*|.goreleaser*|go.mod|go.sum|package.json|package-lock.json|yarn.lock|pnpm-lock.yaml|Cargo.toml|Cargo.lock|pyproject.toml|setup.py|setup.cfg|requirements*.txt|Pipfile*|poetry.lock|tsconfig*|jest.config*|vite.config*|webpack.config*|rollup.config*|babel.config*|*.d.ts)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "allowed_filename"
    exit 0
    ;;
esac

# Allowed by path component — docs, generated, vendor, testdata, etc.
case "$ABS_PATH" in
  */docs/*|*/doc/*|*/documentation/*|*/generated/*|*/gen/*|*/vendor/*|*/node_modules/*|*/testdata/*|*/test_data/*|*/fixtures/*|*/.github/*|*/.vscode/*|*/.idea/*|*/scripts/*|*/hack/*|*/deploy/*|*/chart/*|*/charts/*|*/templates/*)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "allowed_path_component"
    exit 0
    ;;
esac

# Shell scripts — allowed for native tools (RTK, hook scripts, etc.)
case "$EXT" in
  sh|bash|zsh|fish)
    log_json "allow" "$TOOL_NAME" "$FILE_PATH" "shell_script"
    exit 0
    ;;
esac

# Source-code extensions — DENY
case "$EXT" in
  go|ts|tsx|js|jsx|rs|py|c|cc|cpp|h|hpp|rb|java|kt|php|scala|swift)
    case "$TOOL_NAME" in
      Read|Grep|Glob|Search)
        log_json "deny" "$TOOL_NAME" "$FILE_PATH" "source_code_exploration"
        echo "BLOCKED: Use codebase-memory-mcp for source-code exploration. Tool: ${TOOL_NAME}, File: ${FILE_PATH}" >&2
        "$JQ" -n --arg reason "Use codebase-memory-mcp for source-code exploration (${FILE_PATH})" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
        exit 0
        ;;
      Edit|Write)
        log_json "deny" "$TOOL_NAME" "$FILE_PATH" "source_code_edit"
        echo "BLOCKED: Use Serena for source-code edits. Tool: ${TOOL_NAME}, File: ${FILE_PATH}" >&2
        "$JQ" -n --arg reason "Use Serena for source-code edits (${FILE_PATH})" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
        exit 0
        ;;
    esac
    ;;
esac

# Grep special case: path is a directory, type/glob filter indicates source code.
if [[ "$TOOL_NAME" == "Grep" || "$TOOL_NAME" == "Search" ]]; then
  case "$ABS_PATH" in
    "${SRC_DIR}"/*)
      SRC_TYPE_MATCH=""
      case "$GREP_TYPE" in
        go|ts|tsx|js|jsx|rust|py|python|c|cpp|h|rb|ruby|java|kt|kotlin|php|scala|swift) SRC_TYPE_MATCH=1 ;;
      esac
      case "$GREP_GLOB" in
        *.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.py|*.c|*.cc|*.cpp|*.h|*.hpp|*.rb|*.java|*.kt|*.php|*.scala|*.swift) SRC_TYPE_MATCH=1 ;;
      esac
      if [[ -n "$SRC_TYPE_MATCH" ]]; then
        log_json "deny" "$TOOL_NAME" "$FILE_PATH" "grep_source_type"
        echo "BLOCKED: Use codebase-memory-mcp for source-code exploration. Tool: ${TOOL_NAME}, type/glob: ${GREP_TYPE}${GREP_GLOB}" >&2
        "$JQ" -n --arg reason "Use codebase-memory-mcp for source-code exploration (${TOOL_NAME} type/glob: ${GREP_TYPE}${GREP_GLOB})" \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
        exit 0
      fi
      ;;
  esac
fi

# Glob special case: path is a directory, pattern has the extension info.
# Deny if Glob targets source-code extensions under ~/src.
if [[ "$TOOL_NAME" == "Glob" && -n "$GLOB_PATTERN" ]]; then
  case "$ABS_PATH" in
    "${SRC_DIR}"/*)
      case "$GLOB_PATTERN" in
        *.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.py|*.c|*.cc|*.cpp|*.h|*.hpp|*.rb|*.java|*.kt|*.php|*.scala|*.swift)
          log_json "deny" "$TOOL_NAME" "$FILE_PATH" "glob_source_pattern"
          echo "BLOCKED: Use codebase-memory-mcp for source-code exploration. Tool: Glob, Pattern: ${GLOB_PATTERN}" >&2
          "$JQ" -n --arg reason "Use codebase-memory-mcp for source-code exploration (Glob pattern: ${GLOB_PATTERN})" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
          exit 0
          ;;
      esac
      ;;
  esac
fi

# Anything else — fail open
log_json "skip" "$TOOL_NAME" "$FILE_PATH" "unrecognized_extension"
exit 0
