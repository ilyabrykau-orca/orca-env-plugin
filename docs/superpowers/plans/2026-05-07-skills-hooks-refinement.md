# Skills + Hooks Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite 4 skill files to be lean and non-overlapping, fix 7 hook bugs including a broken state-path, wrong deny format, orphaned audit hook, and non-JSON reminder output.

**Architecture:** Skills are standalone SKILL.md files each owning one concern. Hooks are bash scripts communicating via stdout JSON (additionalContext for hints, permissionDecision for denies). State lives in `${CLAUDE_PLUGIN_DATA}` not `${CLAUDE_PLUGIN_ROOT}`.

**Tech Stack:** Bash, jq, bun (test runner)

---

## File map

| File | Action |
|------|--------|
| `skills/orca-setup/SKILL.md` | Rewrite — ~40 lines |
| `skills/cbm-workflow/SKILL.md` | Rewrite — ~70 lines |
| `skills/serena-workflow/SKILL.md` | Rewrite — ~90 lines |
| `skills/orca-dev/SKILL.md` | Rewrite — ~40 lines |
| `hooks/session-start` | Remove memory instructions |
| `hooks/post-cbm-read-record.sh` | Replace JSON log → flag file |
| `hooks/pre-serena-read-guard.sh` | Fix output (stderr→stdout JSON) + throttle + flag file |
| `hooks/post-serena-refs` | Fix STATE_DIR → PLUGIN_DATA |
| `hooks/pre-serena-edit-guard.sh` | Fix state path + deny format |
| `hooks/skill-activation-prompt` | Wrap output in additionalContext JSON |
| `hooks/hooks.json` | Add PostToolBatch entry |
| `tests/unit/test-session-output.sh` | Remove stale CBM assertion, add no-memory assertion |
| `tests/unit/test-serena-guard.sh` | Fix hook paths + exit-code expectations + env var |
| `tests/unit/test-skill-activation.sh` | Add valid-JSON assertion |

---

### Task 1: Rewrite orca-setup/SKILL.md

**Files:**
- Modify: `skills/orca-setup/SKILL.md`
- Modify: `tests/unit/test-session-output.sh`

- [ ] **Step 1: Update test — remove stale assertion, add no-memory assertion**

Replace in `tests/unit/test-session-output.sh` the block that checks `mcp__codebase-memory-mcp__` (orca-setup no longer contains inline CBM calls) and add a no-memory check:

```bash
# REMOVE this line:
if assert_contains "$output" "mcp__codebase-memory-mcp__" "contains CBM tool references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# ADD these lines after the activate_project assertion:
if assert_not_contains "$output" "list_memories" "does not contain list_memories call"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output" "read_memory" "does not contain read_memory call"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "Params cheat sheet" "contains params cheat sheet"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
```

- [ ] **Step 2: Run test — verify it fails on the new assertions**

```bash
cd ~/src/orca-env-plugin
bash tests/unit/test-session-output.sh
```

Expected: FAIL on `does not contain list_memories call` and `contains params cheat sheet`

- [ ] **Step 3: Rewrite `skills/orca-setup/SKILL.md`**

Full replacement content:

```markdown
---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## Enforcement

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` HARD-BLOCKED on `.py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java`.  
Non-code files (`.json .yaml .md .toml .cfg .sh Makefile Dockerfile`) → native tools allowed.

## Session init

```
mcp__serena__activate_project(project=<detected-project>)
```

## Projects

| Short | CBM project | Path | Lang |
|-------|-------------|------|------|
| orca | `Users-ilyabrykau-src-orca` | ~/src/orca | Python/Django |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` | ~/src/orca-sensor | Go |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | `orca-unified` | ~/src | Python+Go |
| helm-charts | `Users-ilyabrykau-src-helm-charts` | ~/src/helm-charts | YAML |

## Params cheat sheet

| Tool | Param | Correct | Wrong |
|------|-------|---------|-------|
| `search_code` (CBM) | text | `pattern` | `query` |
| `search_code` (CBM) | scope | `project` (required) | omitting it |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `relative_path` + `start_line` |
| `search_graph` (CBM) | scope | `project` (required) | omitting it |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement`, `is_regex` |
| `replace_content` | mode | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |
```

- [ ] **Step 4: Run test — verify passes**

```bash
bash tests/unit/test-session-output.sh
```

Expected: all assertions PASS

- [ ] **Step 5: Run skills lint**

```bash
bash tests/unit/test-skills-lint.sh
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add skills/orca-setup/SKILL.md tests/unit/test-session-output.sh
git commit -m "feat: slim orca-setup to session init + params cheat sheet only"
```

---

### Task 2: Rewrite cbm-workflow/SKILL.md

**Files:**
- Modify: `skills/cbm-workflow/SKILL.md`

- [ ] **Step 1: Run lint as baseline**

```bash
bash tests/unit/test-skills-lint.sh
```

Expected: PASS (confirms baseline before change)

- [ ] **Step 2: Rewrite `skills/cbm-workflow/SKILL.md`**

Full replacement content:

```markdown
---
name: cbm-workflow
description: CBM code intelligence — search, symbol lookup, call graphs, architecture, performance analysis, memory optimization, allocation patterns. Use for ALL code search, understanding, and exploration tasks in orca repos. Triggers on explore, understand, find, analyze, performance, memory, allocation, hot path, benchmark, optimize, inefficiency, dead code, unused, refactor.
---

# CBM Workflow

## Quick-start

| Intent | Tool | Key params |
|--------|------|-----------|
| Text search | `search_code` | `pattern`, `project` (required) |
| Find symbol by name | `search_graph` | `MATCH (n) WHERE n.name='X' RETURN n`, `project` |
| Read symbol body | `get_code_snippet` | `qualified_name` |
| Architecture overview | `get_architecture` | `project` — start here for multi-symbol tasks |
| Trace call chain | `trace_path` | `source`, `target`, `project` |
| Who calls X | `search_graph` | `MATCH (c)-[:CALLS]->(n) WHERE n.name='X' RETURN c`, `project` |
| Impact radius | `query_graph` | `MATCH (n)-[*1..2]-(m) WHERE n.name='X' RETURN m`, `project` |

## Empty-result escalation (mandatory)

Before reaching for Serena, exhaust CBM in order:

1. **Verify project name** — `mcp__codebase-memory-mcp__list_projects()`. Wrong name = empty results every time.
2. **Broaden pattern** — drop `path_filter`; use concrete symbol names not file paths.
3. **Switch tool** — `search_code` empty? Try `search_graph` with a file filter. Still empty? Try `get_architecture(project=...)` to orient.
4. **Last resort only** (all 3 steps exhausted):
   - `mcp__serena__get_symbols_overview(relative_path="dir/")`
   - `mcp__serena__find_symbol(name_path_pattern="X", include_body=True, relative_path="dir/")`

   Reaching for Serena without trying steps 1–3 violates the routing contract.

## CBM project names

| Short | Pass to `project=` |
|-------|-------------------|
| orca | `Users-ilyabrykau-src-orca` |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` |
| orca-unified | `orca-unified` |
| helm-charts | `Users-ilyabrykau-src-helm-charts` |

## Wrong / right

| Wrong | Right |
|-------|-------|
| `search_code(query="kafka")` | `search_code(pattern="kafka", project="...")` |
| `get_code_snippet(relative_path="x.py", start_line=10)` | `get_code_snippet(qualified_name="module::Class/method")` |
| `search_graph(query="...", ...)` (no `project`) | `search_graph(query="...", project="Users-ilyabrykau-src-orca")` |
| Serena `find_symbol` as first step | `search_code` or `search_graph` first; Serena only after escalation |
```

- [ ] **Step 3: Run lint**

```bash
bash tests/unit/test-skills-lint.sh
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add skills/cbm-workflow/SKILL.md
git commit -m "feat: slim cbm-workflow to quick-start table and escalation ladder"
```

---

### Task 3: Rewrite serena-workflow/SKILL.md

**Files:**
- Modify: `skills/serena-workflow/SKILL.md`

- [ ] **Step 1: Rewrite `skills/serena-workflow/SKILL.md`**

Full replacement content (cuts: Reading Code section, Memory section):

```markdown
---
name: serena-workflow
description: Serena editing workflow — symbol-level editing, replace_content, memory management. Use for ALL code editing tasks in orca repos.
---

# Serena Editing Workflow

Native `Edit`/`Write` HARD-BLOCKED on code files. Use Serena for all edits.

## Pre-edit checklist (mandatory)

Before ANY code edit:
1. `mcp__serena__find_referencing_symbols(name_path="target", relative_path="path/to/file.py")` — `relative_path` must be a FILE, not a directory
2. Review references — understand impact scope
3. Plan with TaskCreate

## Edit tool selector

| Situation | Tool |
|-----------|------|
| Replace entire function/class/method | `replace_symbol_body` |
| Edit lines within a symbol | `replace_content` |
| Add code after existing symbol | `insert_after_symbol` |
| Add code before first symbol | `insert_before_symbol` |
| Rename across codebase | `rename_symbol` |
| Delete a symbol | `safe_delete_symbol` |

## A. replace_symbol_body

```python
mcp__serena__replace_symbol_body(
    name_path="MyClass/process_data",
    relative_path="orca/sensors/processor.py",
    body="def process_data(self, event):\n    return self.transform(event)"
)
```

`body` is implementation only — no docstrings or leading comments.

## B. replace_content

```python
# Literal
mcp__serena__replace_content(
    relative_path="orca/config.py",
    needle="TIMEOUT = 30",
    repl="TIMEOUT = 60",
    mode="literal"
)

# Regex — backrefs use $!1 not \1
mcp__serena__replace_content(
    relative_path="orca/sensors/base.py",
    needle="log\\(\"(.*?)\"\\)",
    repl="logger.info(\"$!1\")",
    mode="regex"
)
```

## C. Insert

```python
mcp__serena__insert_after_symbol(
    name_path="existing_function",
    relative_path="orca/utils.py",
    body="\ndef new_function():\n    pass"
)

mcp__serena__insert_before_symbol(
    name_path="first_class",
    relative_path="orca/models.py",
    body="import logging\n\nlogger = logging.getLogger(__name__)\n"
)
```

## D. Rename

```python
mcp__serena__rename_symbol(
    name_path="OldClassName",
    relative_path="orca/models.py",
    new_name="NewClassName"
)
```

## Gotchas

| Gotcha | Rule |
|--------|------|
| `find_referencing_symbols` path | Must be a FILE, not a directory |
| `replace_content` backrefs | `$!1`, `$!2` — NOT `\1`, `\2` |
| `replace_symbol_body` body | Implementation only — no docstrings/comments |
| `read_file` lines | 0-based; `end_line` inclusive |
| `mode` values | Exactly `"literal"` or `"regex"` (lowercase) |
| `find_symbol` param | `name_path_pattern` — NOT `name` or `symbol_name` |

## Wrong / right

| Wrong | Right |
|-------|-------|
| `find_referencing_symbols(symbol_name="Foo")` | `find_referencing_symbols(name_path="Foo", relative_path="orca/file.py")` |
| `replace_content(... mode="regexp")` | `replace_content(... mode="regex")` |
| `find_symbol(name="Foo", include_body=True)` | `find_symbol(name_path_pattern="Foo", include_body=True)` |
```

- [ ] **Step 2: Run lint**

```bash
bash tests/unit/test-skills-lint.sh
```

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/serena-workflow/SKILL.md
git commit -m "feat: slim serena-workflow — cut Reading Code + Memory sections"
```

---

### Task 4: Rewrite orca-dev/SKILL.md

**Files:**
- Modify: `skills/orca-dev/SKILL.md`

- [ ] **Step 1: Rewrite `skills/orca-dev/SKILL.md`**

Full replacement content (cuts: CBM patterns prose, duplicate project names table):

```markdown
---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd | Serena project | Path style |
|-----|---------------|------------|
| `~/src` (unified) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate: `mcp__serena__activate_project(project=<name>)` when switching repos.

## Tool routing

| Intent | Use | Never |
|--------|-----|-------|
| Search / grep code | `mcp__codebase-memory-mcp__search_code` | native `Grep`, `Glob` |
| Find symbol / list symbols | `mcp__codebase-memory-mcp__search_graph` | `mcp__serena__find_symbol` for exploration |
| Read symbol body | `mcp__codebase-memory-mcp__get_code_snippet` | native `Read` on source |
| Trace call chain | `mcp__codebase-memory-mcp__trace_path` | manual grep |
| Architecture overview | `mcp__codebase-memory-mcp__get_architecture` | — |
| Find callers (pre-edit) | `mcp__serena__find_referencing_symbols` | — |
| Edit a symbol | `mcp__serena__replace_symbol_body`, `replace_content` | native `Edit`, `Write` |
| Delete a symbol | `mcp__serena__safe_delete_symbol` | native `Edit` |
| Non-code files | native `Read` / `Edit` / `Write` | — |
| Web search | `mcp__exa__web_search_exa` | — |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any edit/delete.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content`: backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file`: 0-based lines, `end_line` inclusive.

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
```

- [ ] **Step 2: Run lint**

```bash
bash tests/unit/test-skills-lint.sh
```

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/orca-dev/SKILL.md
git commit -m "feat: slim orca-dev — cut CBM patterns prose and duplicate project table"
```

---

### Task 5: session-start — remove memory instructions

**Files:**
- Modify: `hooks/session-start`

- [ ] **Step 1: Remove memory instructions from `hooks/session-start`**

Find and replace the `project_ctx` block. Current:

```bash
    project_ctx="SERENA WORKSPACE DETECTED: project='${project}' at ${PWD}

IMMEDIATELY call: mcp__serena__activate_project(project=${project})
Then: mcp__serena__list_memories() and read relevant memories."
```

Replace with:

```bash
    project_ctx="SERENA WORKSPACE DETECTED: project='${project}' at ${PWD}

IMMEDIATELY call: mcp__serena__activate_project(project=${project})"
```

- [ ] **Step 2: Run session-start output test**

```bash
bash tests/unit/test-session-output.sh
```

Expected: PASS (including the new no-memory assertions from Task 1)

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start
git commit -m "fix: remove list_memories/read_memory instructions from session-start hook"
```

---

### Task 6: Fix serena guard — state dir, path mismatch, deny format

**Files:**
- Modify: `hooks/post-serena-refs`
- Modify: `hooks/pre-serena-edit-guard.sh`
- Modify: `tests/unit/test-serena-guard.sh`

- [ ] **Step 1: Update test — fix hook paths, exit-code expectations, env var**

In `tests/unit/test-serena-guard.sh`, make these changes:

```bash
# Line 13-14: fix hook paths
HOOK_EDIT="${PLUGIN_ROOT}/hooks/pre-serena-edit-guard.sh"   # was: pre-serena-edit
HOOK_REFS="${PLUGIN_ROOT}/hooks/post-serena-refs"            # unchanged

# Line 17-20: fix skip condition
if [ ! -f "$HOOK_EDIT" ] || [ ! -f "$HOOK_REFS" ]; then
    echo "=== Unit: serena-guard — SKIPPED (hooks not yet created) ==="
    [ ! -f "$HOOK_EDIT" ] && echo "  Missing: $HOOK_EDIT"
    [ ! -f "$HOOK_REFS" ] && echo "  Missing: $HOOK_REFS"
    exit 0
fi
```

Replace all `CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT"` and `CLAUDE_PLUGIN_ROOT="$FRESH_TMPROOT"` etc. with `CLAUDE_PLUGIN_DATA=`:

```bash
# Every hook invocation that passes state env:
# BEFORE:  CLAUDE_PLUGIN_ROOT="$GUARD_TMPROOT" bash "$HOOK_REFS"
# AFTER:   CLAUDE_PLUGIN_DATA="$GUARD_TMPROOT" bash "$HOOK_REFS"
```

Fix the deny exit-code expectation (exit 2, not 1):

```bash
# Section 3 "warns without refs":
# BEFORE: if [ "$rc" -eq 1 ]; then echo "  [PASS] warns without refs (exit 1)"
# AFTER:  if [ "$rc" -eq 2 ]; then echo "  [PASS] denies without refs (exit 2)"
```

Fix state file path assertion (now under PLUGIN_DATA, not PLUGIN_ROOT):

```bash
# Section 1: state file check
# BEFORE: STATE_FILE="$GUARD_TMPROOT/state/refs-traced.json"
# AFTER:  STATE_FILE="$GUARD_TMPROOT/state/refs-traced.json"  ← same path, just env var changes
```

Also: add a deny-output format test in section 3:

```bash
# After the exit-code check in section 3, add:
deny_out=$(echo "{\"tool_name\":\"mcp__serena__replace_symbol_body\",\"tool_input\":{\"name_path\":\"Foo\",\"relative_path\":\"bar.py\",\"body\":\"pass\"},\"session_id\":\"$FRESH_SESSION\"}" \
    | CLAUDE_PLUGIN_DATA="$FRESH_TMPROOT" bash "$HOOK_EDIT" 2>/dev/null || true)

if echo "$deny_out" | jq -e '.permissionDecision == "deny"' >/dev/null 2>&1; then
    echo "  [PASS] deny output has top-level permissionDecision"
    passed=$((passed+1))
else
    echo "  [FAIL] deny output missing top-level permissionDecision"
    echo "  Got: ${deny_out:0:200}"
    failed=$((failed+1))
fi

if echo "$deny_out" | jq -e '.permissionDecisionReason | length > 0' >/dev/null 2>&1; then
    echo "  [PASS] deny output has permissionDecisionReason"
    passed=$((passed+1))
else
    echo "  [FAIL] deny output missing permissionDecisionReason"
    failed=$((failed+1))
fi
```

- [ ] **Step 2: Run test — verify it now fails (hook paths exist but bugs present)**

```bash
bash tests/unit/test-serena-guard.sh
```

Expected: FAIL on deny-format assertions and potentially state-file assertions

- [ ] **Step 3: Fix `hooks/post-serena-refs` — change STATE_DIR to PLUGIN_DATA**

Find the line:
```bash
STATE_DIR="${CLAUDE_PLUGIN_ROOT:-/tmp}/state"
```

Replace with:
```bash
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/state"
```

- [ ] **Step 4: Fix `hooks/pre-serena-edit-guard.sh` — path, session check, deny format**

Change STATE_DIR (already uses PLUGIN_DATA but needs aligning):
```bash
# BEFORE:
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${CLAUDE_PLUGIN_ROOT}/state}"
STATE_FILE="$STATE_DIR/refs-traced.${SESSION_ID}.json"

# AFTER:
STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/state"
STATE_FILE="$STATE_DIR/refs-traced.json"
```

Fix jq query to check session_id inside the JSON:
```bash
# BEFORE:
DENY=1
if [[ -f "$STATE_FILE" ]]; then
  HAS=$(jq --arg p "$REL_PATH" '.traced[$p] // null' "$STATE_FILE" 2>/dev/null)
  [[ "$HAS" != "null" ]] && DENY=0
fi

# AFTER:
DENY=1
if [[ -f "$STATE_FILE" ]]; then
  HAS=$(jq --arg p "$REL_PATH" --arg sid "$SESSION_ID" \
    'if .session_id == $sid then (.traced[$p] // null) else null end' \
    "$STATE_FILE" 2>/dev/null)
  [[ "$HAS" != "null" ]] && DENY=0
fi
```

Fix deny output format (remove hookSpecificOutput wrapper):
```bash
# BEFORE:
jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

# AFTER:
jq -n --arg r "$REASON" '{"permissionDecision": "deny", "permissionDecisionReason": $r}'
```

- [ ] **Step 5: Run test — verify passes**

```bash
bash tests/unit/test-serena-guard.sh
```

Expected: all assertions PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/post-serena-refs hooks/pre-serena-edit-guard.sh tests/unit/test-serena-guard.sh
git commit -m "fix: serena guard state dir (PLUGIN_DATA), path mismatch, deny format (AP-55, AP-16)"
```

---

### Task 7: CBM flag file + pre-serena-read-guard output

**Files:**
- Modify: `hooks/post-cbm-read-record.sh`
- Modify: `hooks/pre-serena-read-guard.sh`

- [ ] **Step 1: Replace `hooks/post-cbm-read-record.sh` with flag-file writer**

Full file replacement:

```bash
#!/usr/bin/env bash
# PostToolUse: mark that CBM was used this session (flag file).
# pre-serena-read-guard reads this flag to suppress the "try CBM first" hint.
trap 'exit 0' EXIT

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null) || exit 0

case "$TOOL_NAME" in
  mcp__codebase-memory-mcp__search_code|\
  mcp__codebase-memory-mcp__search_graph|\
  mcp__codebase-memory-mcp__get_code_snippet|\
  mcp__codebase-memory-mcp__trace_path|\
  mcp__codebase-memory-mcp__query_graph|\
  mcp__codebase-memory-mcp__get_architecture|\
  mcp__codebase-memory-mcp__get_graph_schema|\
  mcp__codebase-memory-mcp__detect_changes)
    ;;
  *)
    exit 0
    ;;
esac

SESSION_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/${CLAUDE_SESSION_ID:-default}"
mkdir -p "$SESSION_DIR"
touch "${SESSION_DIR}/cbm-used"
exit 0
```

- [ ] **Step 2: Replace `hooks/pre-serena-read-guard.sh` with stdout JSON + throttle version**

Full file replacement:

```bash
#!/usr/bin/env bash
# PreToolUse guard: hint (non-blocking) when Serena read tools used without prior CBM.
# Outputs additionalContext JSON to stdout. Throttled to once per 300s per session.
trap 'exit 0' EXIT

JQ=$(command -v jq 2>/dev/null || command -v jaq 2>/dev/null) || exit 0

INPUT=$(cat)
TOOL_NAME=$("$JQ" -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null) || exit 0

case "$TOOL_NAME" in
  mcp__serena__find_symbol|\
  mcp__serena__get_symbols_overview|\
  mcp__serena__search_for_pattern|\
  mcp__serena__read_file|\
  mcp__serena__list_dir|\
  mcp__serena__find_file)
    ;;
  *)
    exit 0
    ;;
esac

SESSION_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/${CLAUDE_SESSION_ID:-default}"

# CBM used this session — hint not needed
[[ -f "${SESSION_DIR}/cbm-used" ]] && exit 0

# Throttle: suppress if warned within last 300s
WARN_TS_FILE="${SESSION_DIR}/serena-read-warned-ts"
if [[ -f "$WARN_TS_FILE" ]]; then
    last_ts=$(cat "$WARN_TS_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if (( now - last_ts < 300 )); then
        exit 0
    fi
fi

mkdir -p "$SESSION_DIR"
date +%s > "$WARN_TS_FILE"

MSG="Serena read tools are a FALLBACK. Try CBM first:
  mcp__codebase-memory-mcp__search_code(pattern=..., project=\"...\")
  mcp__codebase-memory-mcp__get_architecture(project=\"...\")
If CBM returns empty: (1) verify project name with list_projects() (2) broaden pattern (3) try search_graph.
This hint is non-blocking — proceed if CBM truly cannot help."

"$JQ" -n --arg msg "$MSG" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
exit 0
```

- [ ] **Step 3: Test output format manually**

```bash
cd ~/src/orca-env-plugin
echo '{"tool_name":"mcp__serena__find_symbol","tool_input":{"name_path_pattern":"Foo"}}' \
  | CLAUDE_PLUGIN_DATA=/tmp/test-cbm-guard CLAUDE_SESSION_ID=test-sess \
    bash hooks/pre-serena-read-guard.sh | jq .
```

Expected: valid JSON with `.hookSpecificOutput.additionalContext` containing the hint text

- [ ] **Step 4: Test throttle — second call within 300s produces no output**

```bash
# First call (should emit hint)
echo '{"tool_name":"mcp__serena__find_symbol","tool_input":{"name_path_pattern":"Foo"}}' \
  | CLAUDE_PLUGIN_DATA=/tmp/test-cbm-throttle CLAUDE_SESSION_ID=throttle-sess \
    bash hooks/pre-serena-read-guard.sh | jq -r '.hookSpecificOutput.additionalContext' | head -1
# Expected: "Serena read tools are a FALLBACK..."

# Second call immediately after (should be empty — throttled)
echo '{"tool_name":"mcp__serena__find_symbol","tool_input":{"name_path_pattern":"Bar"}}' \
  | CLAUDE_PLUGIN_DATA=/tmp/test-cbm-throttle CLAUDE_SESSION_ID=throttle-sess \
    bash hooks/pre-serena-read-guard.sh
# Expected: empty output (exit 0, no JSON)
```

- [ ] **Step 5: Test CBM-used suppression**

```bash
mkdir -p /tmp/test-cbm-suppressed/suppressed-sess
touch /tmp/test-cbm-suppressed/suppressed-sess/cbm-used

echo '{"tool_name":"mcp__serena__find_symbol","tool_input":{"name_path_pattern":"Foo"}}' \
  | CLAUDE_PLUGIN_DATA=/tmp/test-cbm-suppressed CLAUDE_SESSION_ID=suppressed-sess \
    bash hooks/pre-serena-read-guard.sh
# Expected: empty output (CBM was used, no hint needed)
```

- [ ] **Step 6: Clean up temp dirs**

```bash
rm -rf /tmp/test-cbm-guard /tmp/test-cbm-throttle /tmp/test-cbm-suppressed
```

- [ ] **Step 7: Run full unit suite**

```bash
bash tests/run-all.sh --unit
```

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add hooks/post-cbm-read-record.sh hooks/pre-serena-read-guard.sh
git commit -m "fix: replace CBM JSON log with flag file; pre-serena-read-guard stdout JSON + throttle"
```

---

### Task 8: skill-activation-prompt — wrap output in additionalContext JSON

**Files:**
- Modify: `hooks/skill-activation-prompt`
- Modify: `tests/unit/test-skill-activation.sh`

- [ ] **Step 1: Add valid-JSON assertion to `tests/unit/test-skill-activation.sh`**

After the existing "cbm-workflow triggers" section, add a JSON shape test:

```bash
# ── JSON output shape ────────────────────────────────────────────────────────
echo ""
echo "--- JSON output shape ---"

out=$(run_prompt "search code for authentication")
if assert_valid_json "$out" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if echo "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    echo "  [PASS] hookSpecificOutput.additionalContext present and non-empty"
    passed=$((passed+1))
else
    echo "  [FAIL] hookSpecificOutput.additionalContext missing or empty"
    echo "  Output: ${out:0:300}"
    failed=$((failed+1))
fi
```

- [ ] **Step 2: Run test — verify JSON shape assertions fail**

```bash
bash tests/unit/test-skill-activation.sh
```

Expected: existing keyword assertions still PASS, new JSON assertions FAIL

- [ ] **Step 3: Fix `hooks/skill-activation-prompt` — wrap output in JSON**

Find the final output block (last few lines of the hook):

```bash
printf "%b\n" "$output"
```

Replace with:

```bash
# Wrap in additionalContext JSON so Claude Code receives it as structured context
"$JQ" -n --arg ctx "$(printf "%b" "$output")" \
    '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":$ctx}}'
```

Also ensure `JQ` variable is set earlier in the hook (it already is — the hook sets `JQ=$(command -v jq ...)`).

- [ ] **Step 4: Run test — verify passes**

```bash
bash tests/unit/test-skill-activation.sh
```

Expected: all assertions PASS (keyword greps still work because the skill names appear inside the JSON string value)

- [ ] **Step 5: Verify no-match case still produces empty output**

```bash
echo '{"prompt":"hello how are you"}' | CLAUDE_PLUGIN_ROOT=~/src/orca-env-plugin bash ~/src/orca-env-plugin/hooks/skill-activation-prompt
```

Expected: empty output (early `exit 0` fires before JSON wrapping when no matches)

- [ ] **Step 6: Commit**

```bash
git add hooks/skill-activation-prompt tests/unit/test-skill-activation.sh
git commit -m "fix: skill-activation-prompt output wrapped in additionalContext JSON"
```

---

### Task 9: hooks.json — wire PostToolBatch audit

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Add PostToolBatch entry to `hooks/hooks.json`**

In `hooks/hooks.json`, add the `PostToolBatch` key alongside existing hook events. Final hooks.json structure with addition:

```json
{
  "hooks": {
    "SessionStart": [ ... ],
    "UserPromptSubmit": [ ... ],
    "PreToolUse": [ ... ],
    "PostToolUse": [ ... ],
    "PostToolBatch": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/post-batch-audit.sh'",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [ ... ],
    "SubagentStop": [ ... ]
  }
}
```

Add only the `PostToolBatch` key — leave all other keys unchanged.

- [ ] **Step 2: Validate hooks.json is valid JSON**

```bash
jq . ~/src/orca-env-plugin/hooks/hooks.json >/dev/null && echo "valid JSON"
```

Expected: `valid JSON` (no error)

- [ ] **Step 3: Confirm PostToolBatch is now present**

```bash
jq '.hooks | keys' ~/src/orca-env-plugin/hooks/hooks.json
```

Expected output includes `"PostToolBatch"`

- [ ] **Step 4: Run hook structure test**

```bash
bash tests/unit/test-hook-properties.sh
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add hooks/hooks.json
git commit -m "fix: wire PostToolBatch in hooks.json — post-batch-audit.sh was orphaned (AP-51)"
```

---

### Task 10: Verify session-start-compact + full suite

**Files:**
- Possibly modify: `hooks/session-start-compact` (only if memory refs found)

- [ ] **Step 1: Audit session-start-compact for memory refs**

```bash
grep -i "list_memories\|read_memory\|write_memory" ~/src/orca-env-plugin/hooks/session-start-compact || echo "clean"
```

Expected: `clean` (spec audit found none)

If any refs found, remove them — the compact hook should only re-inject the `<tool_routing>` block.

- [ ] **Step 2: Run full unit suite**

```bash
cd ~/src/orca-env-plugin
bash tests/run-all.sh --unit
```

Expected: all tests PASS, 0 failures

- [ ] **Step 3: Verify session-start injects slim orca-setup (spot check)**

```bash
cd ~/src/orca
bash ~/src/orca-env-plugin/hooks/session-start | jq -r '.hookSpecificOutput.additionalContext' | wc -l
```

Expected: ≤ 60 lines (was ~200+ with old orca-setup content)

- [ ] **Step 4: Commit session-start-compact if changed, or just tag the work**

```bash
# If session-start-compact was changed:
git add hooks/session-start-compact
git commit -m "fix: remove stale memory refs from session-start-compact"

# If it was already clean, just note it and skip the commit.
```

- [ ] **Step 5: Final summary**

```bash
cd ~/src/orca-env-plugin && git log --oneline -10
```

Expected: 10 commits showing the tasks above.
