# v7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild orca-env-plugin v7 on the v1 branch, replacing codanna with CBM, adding compact re-injection and RTK bash rewriting, with strict TDD using behavioral contract tests.

**Architecture:** v1 bash hooks + 4 rich skills (~455 lines pedagogy). No permissions.deny, no compiled binary. Hooks enforce routing with contextual suggestions (exit 2 + redirect message). Two new hooks from v6: compact SessionStart handler and RTK bash rewriter.

**Tech Stack:** Bash hooks, bash unit tests, Node.js (stop analytics only), jq for JSON processing.

**Spec:** `docs/superpowers/specs/2026-04-28-v7-pedagogy-design.md`

---

## File Map

### Created (new files)
- `skills/cbm-workflow/SKILL.md` — CBM code intelligence skill (~130 lines)
- `skills/orca-dev/SKILL.md` — compact routing contract (~65 lines)
- `hooks/session-start-compact` — slim routing re-injection for resume/compact
- `hooks/rtk-rewrite-bash` — RTK bash command rewriter
- `tests/unit/test-session-compact.sh` — compact handler behavioral tests
- `tests/unit/test-rtk-rewrite.sh` — RTK rewrite behavioral tests
- `tests/unit/test-skill-activation.sh` — keyword matching behavioral tests
- `tests/e2e/run-e2e.sh` — parallel E2E launcher
- `tests/e2e/lib/launch-session.sh` — claude session launcher
- `tests/e2e/lib/verify-transcript.sh` — stream-json transcript parser
- `tests/e2e/lib/assert-routing.sh` — routing assertion helpers
- `tests/e2e/matrix/orca-python-feature.sh` — Python feature E2E
- `tests/e2e/matrix/sensor-go-feature.sh` — Go feature E2E
- `tests/e2e/matrix/runtime-go-feature.sh` — Go+eBPF feature E2E
- `tests/e2e/matrix/helm-yaml-feature.sh` — YAML control case E2E

### Modified (existing v1 files)
- `.claude-plugin/plugin.json` — bump version to 7.0.0
- `hooks/hooks.json` — add compact + RTK entries, update SessionStart matcher
- `hooks/session-start` — update injected skill (codanna → CBM refs)
- `hooks/pre-tool-router` — update suggestion messages (codanna → CBM)
- `skills/serena-workflow/SKILL.md` — replace codanna reading refs with CBM
- `skills/orca-setup/SKILL.md` — replace codanna with CBM throughout
- `skills/skill-rules.json` — replace codanna/docs triggers with cbm/serena
- `tests/unit/test-pre-tool-use.sh` — update expected suggestion messages
- `tests/unit/test-session-output.sh` — expect CBM refs, not codanna
- `tests/unit/test-plugin-structure.sh` — expect 4 skill dirs + new hooks
- `tests/unit/test-skills-lint.sh` — add no-codanna assertion, add CBM checks
- `tests/unit/test-hooks-smoke.sh` — add compact + RTK smoke tests
- `tests/unit/test-hook-properties.sh` — validate new hooks.json entries

### Unchanged (carry from v1 as-is)
- `hooks/skill-activation-prompt` — script unchanged (reads updated skill-rules.json)
- `hooks/post-serena-refs` — unchanged
- `hooks/stop.js` — unchanged
- `hooks/subagent-stop.js` — unchanged
- `hooks/utils/transcript-parser.js` — unchanged
- `tests/helpers.sh` — unchanged
- `tests/run-all.sh` — unchanged
- `tests/unit/test-serena-guard.sh` — unchanged (Serena tools unchanged)
- `tests/unit/test-project-detection.sh` — unchanged
- `tests/unit/test-json-escaping.sh` — unchanged
- `tests/unit/test-failure-modes.sh` — unchanged

---

## Task 1: Plugin manifest + hooks.json

Update the plugin manifest and hook registry to v7 structure.

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `hooks/hooks.json`
- Test: `tests/unit/test-plugin-structure.sh`
- Test: `tests/unit/test-hook-properties.sh`

- [ ] **Step 1: Write failing test — plugin structure expects v7 layout**

Update `tests/unit/test-plugin-structure.sh` to expect the v7 structure: 4 skill dirs (cbm-workflow, serena-workflow, orca-setup, orca-dev), session-start-compact hook, rtk-rewrite-bash hook. Replace the file completely:

```bash
#!/usr/bin/env bash
# Unit test: plugin structure validation — v7
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: plugin structure validation ==="
echo ""

# --- 1. plugin.json ---
echo "--- .claude-plugin/plugin.json ---"

PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

if [ -f "$PLUGIN_JSON" ]; then
    echo "  [PASS] plugin.json exists"
    passed=$((passed+1))
else
    echo "  [FAIL] plugin.json missing at $PLUGIN_JSON"
    failed=$((failed+1))
fi

if [ -f "$PLUGIN_JSON" ]; then
    plugin_content=$(cat "$PLUGIN_JSON")

    if assert_valid_json "$plugin_content" "plugin.json is valid JSON"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi
    if assert_json_field "$plugin_content" '.name' "plugin.json has 'name' field"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi

    version=$(echo "$plugin_content" | jq -r '.version // "missing"')
    if [[ "$version" == 7.* ]]; then
        echo "  [PASS] plugin.json version is 7.x ($version)"
        passed=$((passed+1))
    else
        echo "  [FAIL] plugin.json version should be 7.x, got: $version"
        failed=$((failed+1))
    fi
fi

# --- 2. hooks.json ---
echo ""
echo "--- hooks/hooks.json ---"

HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"

if [ -f "$HOOKS_JSON" ]; then
    echo "  [PASS] hooks.json exists"
    passed=$((passed+1))
else
    echo "  [FAIL] hooks.json missing at $HOOKS_JSON"
    failed=$((failed+1))
fi

if [ -f "$HOOKS_JSON" ]; then
    hooks_content=$(cat "$HOOKS_JSON")

    if assert_valid_json "$hooks_content" "hooks.json is valid JSON"; then
        passed=$((passed+1)); else failed=$((failed+1))
    fi

    for key in SessionStart PreToolUse PostToolUse UserPromptSubmit Stop SubagentStop; do
        has_key=$(echo "$hooks_content" | jq -r ".hooks | has(\"$key\")" 2>/dev/null || echo "false")
        if [ "$has_key" = "true" ]; then
            echo "  [PASS] hooks.json has $key key"
            passed=$((passed+1))
        else
            echo "  [FAIL] hooks.json missing $key key"
            failed=$((failed+1))
        fi
    done
fi

# --- 3. All hook scripts exist and are executable ---
echo ""
echo "--- Hook scripts ---"

for hook in session-start session-start-compact skill-activation-prompt pre-tool-router rtk-rewrite-bash post-serena-refs; do
    path="${PLUGIN_ROOT}/hooks/${hook}"
    if [ -f "$path" ]; then
        echo "  [PASS] ${hook} exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${hook} missing at $path"
        failed=$((failed+1))
    fi
    if [ -x "$path" ]; then
        echo "  [PASS] ${hook} is executable"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${hook} is not executable"
        failed=$((failed+1))
    fi
done

for hook in stop.js subagent-stop.js; do
    path="${PLUGIN_ROOT}/hooks/${hook}"
    if [ -f "$path" ]; then
        echo "  [PASS] ${hook} exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${hook} missing at $path"
        failed=$((failed+1))
    fi
done

# --- 4. All 4 skill dirs exist ---
echo ""
echo "--- Skill directories ---"

for skill in cbm-workflow serena-workflow orca-setup orca-dev; do
    path="${PLUGIN_ROOT}/skills/${skill}/SKILL.md"
    if [ -f "$path" ]; then
        echo "  [PASS] skills/${skill}/SKILL.md exists"
        passed=$((passed+1))
    else
        echo "  [FAIL] skills/${skill}/SKILL.md missing"
        failed=$((failed+1))
    fi
done

# --- 5. No settings.json (no permissions.deny) ---
echo ""
echo "--- No permissions.deny ---"

if [ ! -f "${PLUGIN_ROOT}/.claude-plugin/settings.json" ]; then
    echo "  [PASS] No settings.json (no permissions.deny)"
    passed=$((passed+1))
else
    echo "  [FAIL] settings.json exists — v7 should have no permissions.deny"
    failed=$((failed+1))
fi

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-plugin-structure.sh`
Expected: FAIL — v1 is missing cbm-workflow, orca-dev, session-start-compact, rtk-rewrite-bash, version is 1.0.0

- [ ] **Step 3: Update plugin.json**

Replace `.claude-plugin/plugin.json`:

```json
{
  "name": "orca-env-plugin",
  "version": "7.0.0",
  "description": "MCP tool routing, skill pedagogy, and session analytics for Claude Code in orca repos",
  "author": {
    "name": "Ilya Brykau"
  },
  "homepage": "https://github.com/ilyabrykau-orca/orca-env-plugin",
  "repository": "https://github.com/ilyabrykau-orca/orca-env-plugin"
}
```

- [ ] **Step 4: Update hooks.json**

Replace `hooks/hooks.json` with the spec-defined structure:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/session-start'", "async": false }]
      },
      {
        "matcher": "resume|compact",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/session-start-compact'", "async": false }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/skill-activation-prompt'" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|Grep|Glob|mcp__serena__(replace_symbol_body|replace_content|insert_after_symbol|insert_before_symbol|rename_symbol|safe_delete_symbol)",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-router'", "timeout": 5 }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/rtk-rewrite-bash'", "timeout": 5 }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__serena__find_referencing_symbols",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/post-serena-refs'", "timeout": 5 }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "node '${CLAUDE_PLUGIN_ROOT}/hooks/stop.js'", "timeout": 30 }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "node '${CLAUDE_PLUGIN_ROOT}/hooks/subagent-stop.js'", "timeout": 30 }]
      }
    ]
  }
}
```

- [ ] **Step 5: Create stub files for new hooks so structure test can pass**

```bash
touch hooks/session-start-compact hooks/rtk-rewrite-bash
chmod +x hooks/session-start-compact hooks/rtk-rewrite-bash
```

- [ ] **Step 6: Create stub skill dirs so structure test can pass**

```bash
mkdir -p skills/cbm-workflow skills/orca-dev
echo -e '---\nname: cbm-workflow\ndescription: stub\n---\n' > skills/cbm-workflow/SKILL.md
echo -e '---\nname: orca-dev\ndescription: stub\n---\n' > skills/orca-dev/SKILL.md
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bash tests/unit/test-plugin-structure.sh`
Expected: PASS — all structure checks pass

- [ ] **Step 8: Commit**

```bash
git add .claude-plugin/plugin.json hooks/hooks.json hooks/session-start-compact hooks/rtk-rewrite-bash skills/cbm-workflow/SKILL.md skills/orca-dev/SKILL.md tests/unit/test-plugin-structure.sh
git commit -m "feat: v7 plugin manifest, hooks.json, stub hooks/skills"
```

---

## Task 2: cbm-workflow skill (replaces codanna)

**Files:**
- Create: `skills/cbm-workflow/SKILL.md`
- Delete: `skills/codanna/SKILL.md` (and dir)
- Test: `tests/unit/test-skills-lint.sh`

- [ ] **Step 1: Write failing test — skills lint expects CBM, rejects codanna**

Update `tests/unit/test-skills-lint.sh`. Replace the file completely:

```bash
#!/usr/bin/env bash
# Unit test: skills lint — v7
# Validates frontmatter, correct tool names, no codanna references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: skills lint ==="
echo ""

# --- 1. Frontmatter validation for all SKILL.md ---
echo "--- Skill frontmatter ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    if head -1 "$skill_file" | grep -q '^---$'; then
        echo "  [PASS] ${skill_name}: has --- frontmatter delimiter"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing --- frontmatter delimiter"
        failed=$((failed+1))
    fi

    if grep -q '^name:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has name: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing name: field"
        failed=$((failed+1))
    fi

    if grep -q '^description:' "$skill_file"; then
        echo "  [PASS] ${skill_name}: has description: field"
        passed=$((passed+1))
    else
        echo "  [FAIL] ${skill_name}: missing description: field"
        failed=$((failed+1))
    fi
done

# --- 2. No codanna references in any skill ---
echo ""
echo "--- No codanna references ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")

    if grep -qi 'codanna' "$skill_file"; then
        echo "  [FAIL] ${skill_name}: contains codanna reference (must use CBM)"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no codanna references"
        passed=$((passed+1))
    fi
done

# --- 3. No codanna skill directory ---
echo ""
echo "--- No codanna skill dir ---"

if [ -d "${PLUGIN_ROOT}/skills/codanna" ]; then
    echo "  [FAIL] skills/codanna/ still exists (should be removed in v7)"
    failed=$((failed+1))
else
    echo "  [PASS] skills/codanna/ does not exist"
    passed=$((passed+1))
fi

# --- 4. CBM tool names in cbm-workflow ---
echo ""
echo "--- CBM tool names in cbm-workflow ---"

CBM_SKILL="${PLUGIN_ROOT}/skills/cbm-workflow/SKILL.md"
if [ -f "$CBM_SKILL" ]; then
    for tool in search_code search_graph get_code_snippet get_architecture trace_path; do
        if grep -q "$tool" "$CBM_SKILL"; then
            echo "  [PASS] cbm-workflow references $tool"
            passed=$((passed+1))
        else
            echo "  [FAIL] cbm-workflow missing $tool reference"
            failed=$((failed+1))
        fi
    done

    if grep -q 'query_graph' "$CBM_SKILL"; then
        echo "  [PASS] cbm-workflow has progressive disclosure (query_graph)"
        passed=$((passed+1))
    else
        echo "  [FAIL] cbm-workflow missing query_graph progressive disclosure"
        failed=$((failed+1))
    fi

    if grep -q 'Wrong.*Right\|Wrong|Right' "$CBM_SKILL"; then
        echo "  [PASS] cbm-workflow has Wrong vs Right table"
        passed=$((passed+1))
    else
        echo "  [FAIL] cbm-workflow missing Wrong vs Right table"
        failed=$((failed+1))
    fi
else
    echo "  [FAIL] cbm-workflow/SKILL.md does not exist"
    failed=$((failed+1))
fi

# --- 5. Serena tool names in serena-workflow ---
echo ""
echo "--- Serena tool names in serena-workflow ---"

SERENA_SKILL="${PLUGIN_ROOT}/skills/serena-workflow/SKILL.md"
if [ -f "$SERENA_SKILL" ]; then
    for tool in replace_symbol_body replace_content insert_after_symbol find_referencing_symbols; do
        if grep -q "$tool" "$SERENA_SKILL"; then
            echo "  [PASS] serena-workflow references $tool"
            passed=$((passed+1))
        else
            echo "  [FAIL] serena-workflow missing $tool reference"
            failed=$((failed+1))
        fi
    done

    if grep -q '\$!1' "$SERENA_SKILL"; then
        echo "  [PASS] serena-workflow has backrefs \$!1 guidance"
        passed=$((passed+1))
    else
        echo "  [FAIL] serena-workflow missing backrefs guidance"
        failed=$((failed+1))
    fi
else
    echo "  [FAIL] serena-workflow/SKILL.md does not exist"
    failed=$((failed+1))
fi

# --- 6. replace_content param validation ---
echo ""
echo "--- replace_content param names ---"

for skill_file in "${PLUGIN_ROOT}"/skills/*/SKILL.md; do
    skill_name=$(basename "$(dirname "$skill_file")")
    if ! grep -q 'replace_content(' "$skill_file"; then
        continue
    fi

    context=$(grep -A5 'replace_content(' "$skill_file")

    if echo "$context" | grep -q 'pattern='; then
        echo "  [FAIL] ${skill_name}: replace_content uses 'pattern=' (should be 'needle=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'pattern=' param"
        passed=$((passed+1))
    fi

    if echo "$context" | grep -q 'replacement='; then
        echo "  [FAIL] ${skill_name}: uses 'replacement=' (should be 'repl=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'replacement=' param"
        passed=$((passed+1))
    fi

    if echo "$context" | grep -q 'is_regex='; then
        echo "  [FAIL] ${skill_name}: uses 'is_regex=' (should be 'mode=')"
        failed=$((failed+1))
    else
        echo "  [PASS] ${skill_name}: no wrong 'is_regex=' param"
        passed=$((passed+1))
    fi
done

# --- 7. orca-setup references CBM not codanna ---
echo ""
echo "--- orca-setup uses CBM tools ---"

SETUP_SKILL="${PLUGIN_ROOT}/skills/orca-setup/SKILL.md"
if [ -f "$SETUP_SKILL" ]; then
    if grep -q 'mcp__codebase-memory-mcp__' "$SETUP_SKILL"; then
        echo "  [PASS] orca-setup references CBM namespace"
        passed=$((passed+1))
    else
        echo "  [FAIL] orca-setup missing CBM namespace references"
        failed=$((failed+1))
    fi
fi

# --- Summary ---
echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-skills-lint.sh`
Expected: FAIL — codanna dir exists, cbm-workflow is a stub, orca-setup references codanna not CBM

- [ ] **Step 3: Delete codanna skill**

```bash
rm -rf skills/codanna
rm -rf skills/docs
```

- [ ] **Step 4: Write cbm-workflow/SKILL.md**

Replace the stub `skills/cbm-workflow/SKILL.md` with the full skill content (~130 lines):

```markdown
---
name: cbm-workflow
description: CBM code intelligence — search, symbol lookup, call graphs, architecture. Use for ALL code search and understanding tasks in orca repos.
---

# CBM Code Intelligence

Native Grep/Glob are HARD-BLOCKED on code files. Use CBM for all code search.

## Quick Start — Pick Your Intent

| "I want to..." | Tool | Key Params |
|---|---|---|
| Search code by text | `search_code` | `pattern`, `project` |
| Find a symbol by name | `search_graph` | query with symbol name |
| Read a symbol's source | `get_code_snippet` | `qualified_name` |
| Trace a call chain | `trace_path` | `source`, `target`, `project` |
| Get architecture overview | `get_architecture` | `project` |
| Find all references | `search_graph` | query for edges |

## Common Patterns

### "How does authentication work?"

```python
mcp__codebase-memory-mcp__search_code(
    pattern="authentication",
    project="orca"
)
```

### "Where is class SensorBase?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'SensorBase' RETURN n",
    project="orca"
)
```

### "Read the source of process_event"

```python
# Step 1: find qualified name
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'process_event' RETURN n.qualified_name",
    project="orca"
)

# Step 2: read source by qualified name
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="orca.sensors.base::process_event"
)
```

### "Who calls handle_request?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (caller)-[:CALLS]->(n) WHERE n.name = 'handle_request' RETURN caller.name, caller.file",
    project="orca"
)
```

### "What does process_event call?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n)-[:CALLS]->(callee) WHERE n.name = 'process_event' RETURN callee.name, callee.file",
    project="orca"
)
```

### "Show me the full architecture"

```python
mcp__codebase-memory-mcp__get_architecture(project="orca")
```

### "Trace from ingest to storage"

```python
mcp__codebase-memory-mcp__trace_path(
    source="ingest_event",
    target="store_result",
    project="orca"
)
```

## Progressive Disclosure — Power Queries

For complex queries beyond the recipes above, use `query_graph` with Cypher:

### Multi-hop: "What does X call that also calls Y?"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (a)-[:CALLS]->(b)-[:CALLS]->(c) WHERE a.name='X' AND c.name='Y' RETURN b",
    project="orca"
)
```

### Impact radius: "Everything within 2 hops of SensorBase"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n)-[*1..2]-(m) WHERE n.name='SensorBase' RETURN m",
    project="orca"
)
```

### Unused exports: "Functions defined but never called"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n:Function) WHERE NOT ()-[:CALLS]->(n) RETURN n.name, n.file",
    project="orca"
)
```

## Edge Types Reference

| Edge | Meaning |
|---|---|
| CALLS | function/method invocation |
| IMPORTS | module/package import |
| DEFINES | file/module defines symbol |
| INHERITS | class inheritance |
| IMPLEMENTS | interface implementation |

## Tips

- Always start with `get_architecture` for multi-symbol exploration — one call replaces 4-6 round-trips
- `search_code` for text matching, `search_graph` for structural queries
- `get_code_snippet(qualified_name=...)` is direct — never use the `relative_path`+`start_line` form
- `path_filter` regex narrows scope (e.g. `^src/`)
- `project` is required on all CBM calls

## Wrong vs Right

| Wrong | Right |
|---|---|
| `get_code_snippet(relative_path="x.py", start_line=10)` | `get_code_snippet(qualified_name="module::func")` |
| `search_code(query="foo")` | `search_code(pattern="foo", project="orca")` |
| Using native Grep for code search | `search_code(pattern=..., project=...)` |
| Manual grep for callers | `search_graph` with CALLS edge query |
| CBM call without `project` param | Always include `project="orca"` (or correct project) |
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/unit/test-skills-lint.sh`
Expected: FAIL — orca-setup still references codanna (will be fixed in Task 4)

Note: This test will fully pass after Task 4. At this point, verify that the cbm-workflow-specific assertions pass (sections 2, 3, 4) and that the codanna dir check passes (section 3). The orca-setup CBM check (section 7) will fail until Task 4.

- [ ] **Step 6: Commit**

```bash
git add skills/cbm-workflow/SKILL.md tests/unit/test-skills-lint.sh
git rm -rf skills/codanna skills/docs
git commit -m "feat: cbm-workflow skill replaces codanna, update skills lint"
```

---

## Task 3: serena-workflow skill update

**Files:**
- Modify: `skills/serena-workflow/SKILL.md`

- [ ] **Step 1: Update serena-workflow to reference CBM instead of codanna**

In `skills/serena-workflow/SKILL.md`, replace the "Reading Code" section. The codanna references are in the `find_symbol` and `search_for_pattern` examples. Replace lines 96-125 (the "Reading Code" section) with CBM-first reading:

```markdown
## Reading Code

```python
# Read symbol source by qualified name (preferred — token efficient)
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="MyClass/my_method"
)

# Pre-edit read via Serena (when you need the symbol for editing next)
mcp__serena__find_symbol(
    name_path_pattern="MyClass/my_method",
    include_body=True,
    relative_path="orca/sensors/"
)

# File overview — what symbols exist
mcp__serena__get_symbols_overview(
    relative_path="orca/sensors/base.py",
    depth=1
)

# Read file range (0-based lines, end_line inclusive)
mcp__serena__read_file(
    relative_path="orca/sensors/base.py",
    start_line=0,
    end_line=49
)
```
```

All other sections remain unchanged.

- [ ] **Step 2: Verify no codanna references remain**

Run: `grep -i codanna skills/serena-workflow/SKILL.md`
Expected: No output (no matches)

- [ ] **Step 3: Commit**

```bash
git add skills/serena-workflow/SKILL.md
git commit -m "feat: update serena-workflow to reference CBM for reads"
```

---

## Task 4: orca-setup skill update

**Files:**
- Modify: `skills/orca-setup/SKILL.md`

- [ ] **Step 1: Rewrite orca-setup for CBM**

Replace `skills/orca-setup/SKILL.md` entirely. This is the skill injected at SessionStart (~120 lines):

```markdown
---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## TOOL ENFORCEMENT ACTIVE

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` are **HARD-BLOCKED** on code files (.py, .go, .ts, .tsx, .js, .jsx, .rs, .cpp, .c, .h, .hpp, .rb, .java).
A PreToolUse hook returns exit 2 if you attempt to use them. Use MCP tools instead.

Non-code files (.json, .yaml, .md, .toml, .cfg, .sh, Makefile, Dockerfile) → native tools allowed.

---

## Step 1: Activate Project

Execute immediately:

```
mcp__serena__activate_project(project=<detected-project>)
```

Then load memories:

```
mcp__serena__list_memories()
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Step 2: Tool Routing

### Search Code

```python
# Text search ranked by structural importance
mcp__codebase-memory-mcp__search_code(pattern="kafka offset commit", project="orca")

# Find symbol by name (structural query)
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'AbstractSensor' RETURN n",
    project="orca"
)

# Full architecture overview — start here for multi-symbol exploration
mcp__codebase-memory-mcp__get_architecture(project="orca")
```

### Read Code

```python
# Read symbol source by qualified name (preferred — token efficient)
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="orca.sensors.base::AbstractSensor"
)

# Pre-edit read via Serena (when you need the symbol for editing next)
mcp__serena__find_symbol(name_path_pattern="AbstractSensor", include_body=True, relative_path="orca/sensors/")
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codebase-memory-mcp__search_code(pattern="...")`
2. **Locate**: `mcp__codebase-memory-mcp__search_graph(query="MATCH (n) WHERE n.name = '...' RETURN n")`
3. **Trace**: `mcp__serena__find_referencing_symbols(name_path="TargetFunc", relative_path="orca/module/file.py")` — **FILE path, not directory. MANDATORY before any edit.**
4. **Plan**: TaskCreate with research → implement → verify
5. **Edit**: Serena tools (see below)
6. **Verify**: `pytest` / `go test`

### Edit Tools

```python
# Replace entire function/class (safest)
mcp__serena__replace_symbol_body(
    name_path="MyClass/process_data",
    relative_path="orca/sensors/processor.py",
    body="def process_data(self, event):\n    return self.transform(event)"
)

# Targeted literal edit
mcp__serena__replace_content(
    relative_path="orca/config.py",
    needle="TIMEOUT = 30",
    repl="TIMEOUT = 60",
    mode="literal"
)

# Regex edit — backreferences use $!1, $!2 (NOT \1, \2)
mcp__serena__replace_content(
    relative_path="orca/sensors/base.py",
    needle="log\\(\"(.*?)\"\\)",
    repl="logger.info(\"$!1\")",
    mode="regex"
)

# Insert after existing symbol
mcp__serena__insert_after_symbol(
    name_path="existing_function",
    relative_path="orca/utils.py",
    body="\ndef new_function():\n    pass"
)
```

### Call Graph

```python
# Who calls this? (use before modifying shared code)
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (caller)-[:CALLS]->(n) WHERE n.name = 'process_event' RETURN caller",
    project="orca"
)

# What does this call?
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n)-[:CALLS]->(callee) WHERE n.name = 'handle_request' RETURN callee",
    project="orca"
)

# Full impact before risky refactor
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n)-[*1..3]-(m) WHERE n.name='SensorBase' RETURN m",
    project="orca"
)
```

---

## Step 3: Memory Protocol

At session start: `mcp__serena__list_memories()` → read relevant ones.

```python
mcp__serena__write_memory(
    memory_file_name="kafka_migration",
    content="# Kafka Migration\n\nDecision: use confluent-kafka..."
)
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Projects

| Project | Path | Language |
|---------|------|----------|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

---

## Params Cheat Sheet

| Tool | Param | Correct | WRONG (do not use) |
|------|-------|---------|---------------------|
| `search_code` (CBM) | text | `pattern` | `query` |
| `search_code` (CBM) | scope | `project` | (omitting it) |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `relative_path` + `start_line` |
| `search_graph` (CBM) | scope | `project` | (omitting it) |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement`, `is_regex` |
| `replace_content` | mode values | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| All memory tools | key | `memory_file_name` | `memory_name`, `memory_file`, `name` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |

---

## Verification

Show actual command output before claiming done:
- Python: `pytest <path> -v`
- Go: `go test ./...`
- Lint: `ruff check .` / `golangci-lint run`
```

- [ ] **Step 2: Run skills lint to verify CBM references**

Run: `bash tests/unit/test-skills-lint.sh`
Expected: PASS — all skill checks pass, no codanna references, CBM namespace in orca-setup

- [ ] **Step 3: Commit**

```bash
git add skills/orca-setup/SKILL.md
git commit -m "feat: update orca-setup skill for CBM"
```

---

## Task 5: orca-dev skill + skill-rules.json

**Files:**
- Create: `skills/orca-dev/SKILL.md` (replace stub)
- Modify: `skills/skill-rules.json`

- [ ] **Step 1: Write orca-dev skill**

Replace the stub `skills/orca-dev/SKILL.md` (~65 lines):

```markdown
---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd pattern | Serena project | path style |
|---|---|---|
| `~/src` (unified workspace) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate via `mcp__serena__activate_project(project=<name>)` when switching.

## Tool routing

| Intent | Use | Never |
|---|---|---|
| Search / grep code | `mcp__codebase-memory-mcp__search_code` | native `Grep`, `Glob` |
| Find symbol / list symbols | `mcp__codebase-memory-mcp__search_graph` | `mcp__serena__find_symbol` for exploration |
| Read a symbol body | `mcp__codebase-memory-mcp__get_code_snippet` | native `Read` on source |
| Trace call chain | `mcp__codebase-memory-mcp__trace_path` | manual grep |
| Architecture overview | `mcp__codebase-memory-mcp__get_architecture` | — |
| Find callers (pre-edit) | `mcp__serena__find_referencing_symbols` | — |
| Edit a symbol | `mcp__serena__replace_symbol_body`, `replace_content` | native `Edit`, `Write` |
| Delete a symbol | `mcp__serena__safe_delete_symbol` | native `Edit` |
| Non-code files | native `Read` / `Edit` / `Write` | — |
| Web search | `mcp__exa__web_search_exa` | — |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any symbol edit/delete.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content` backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file` offsets are 0-based.

## CBM patterns

- Start with `get_architecture(project=...)` for multi-symbol exploration.
- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Project names (CBM index)

| Project | Path | Language |
|---|---|---|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
```

- [ ] **Step 2: Write skill-rules.json**

Replace `skills/skill-rules.json`:

```json
{
  "skills": {
    "cbm-workflow": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "description": "CBM code intelligence for searching and understanding code",
      "promptTriggers": {
        "keywords": ["search code", "find symbol", "find function", "find class",
                     "who calls", "what calls", "callers", "call graph",
                     "trace callers", "trace path", "architecture", "explore code",
                     "investigate", "understand code", "how does", "impact", "use cbm"]
      }
    },
    "serena-workflow": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "description": "Serena editing workflow for modifying code",
      "promptTriggers": {
        "keywords": ["edit code", "refactor", "rename", "replace", "insert",
                     "modify function", "change method", "fix bug", "add method",
                     "use serena", "edit symbol", "replace content"]
      }
    }
  }
}
```

- [ ] **Step 3: Run full skills lint**

Run: `bash tests/unit/test-skills-lint.sh`
Expected: PASS — all 4 skills valid, no codanna, CBM references correct

- [ ] **Step 4: Commit**

```bash
git add skills/orca-dev/SKILL.md skills/skill-rules.json
git commit -m "feat: orca-dev skill + updated skill-rules.json for CBM/Serena"
```

---

## Task 6: pre-tool-router update (codanna → CBM suggestions)

**Files:**
- Modify: `hooks/pre-tool-router`
- Test: `tests/unit/test-pre-tool-use.sh`

- [ ] **Step 1: Write failing test — expects CBM suggestions, not codanna**

Replace `tests/unit/test-pre-tool-use.sh`:

```bash
#!/usr/bin/env bash
# Unit test: PreToolUse enforcement — v7
# Tests behavioral contracts: denied + correct alternative offered
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

HOOK="${PLUGIN_ROOT}/hooks/pre-tool-router"
passed=0; failed=0

echo "=== Unit: PreToolUse enforcement ==="
echo ""

# Helper: run hook, capture exit code and stderr (the suggestion message)
run_enforcement() {
    local json="$1"
    local stderr_file
    stderr_file=$(mktemp)
    local exit_code=0
    echo "$json" | bash "$HOOK" 2>"$stderr_file" || exit_code=$?
    local stderr_out
    stderr_out=$(cat "$stderr_file")
    rm -f "$stderr_file"
    echo "${exit_code}|${stderr_out}"
}

# Assert: tool is denied and correct alternative is suggested
test_denied_with_alternative() {
    local json="$1"
    local expected_alternative="$2"
    local test_name="$3"
    local result
    result=$(run_enforcement "$json")
    local exit_code="${result%%|*}"
    local stderr="${result#*|}"

    if [ "$exit_code" = "2" ]; then
        echo "  [PASS] $test_name — denied (exit 2)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — expected denied (exit 2), got exit $exit_code"
        failed=$((failed+1))
    fi

    if echo "$stderr" | grep -q "$expected_alternative"; then
        echo "  [PASS] $test_name — suggests $expected_alternative"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — expected suggestion '$expected_alternative' in: $stderr"
        failed=$((failed+1))
    fi
}

# Assert: tool is allowed through
test_allowed() {
    local json="$1"
    local test_name="$2"
    local result
    result=$(run_enforcement "$json")
    local exit_code="${result%%|*}"
    if [ "$exit_code" = "0" ]; then
        echo "  [PASS] $test_name — allowed (exit 0)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $test_name — expected allowed (exit 0), got exit $exit_code"
        failed=$((failed+1))
    fi
}

echo "--- Layer 1: Grep/Glob unconditionally denied → CBM suggestion ---"
test_denied_with_alternative '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' \
    "mcp__codebase-memory-mcp__search_code" \
    "Grep redirects to CBM search_code"
test_denied_with_alternative '{"tool_name":"Glob","tool_input":{"pattern":"**/*.py"}}' \
    "mcp__codebase-memory-mcp__search_graph" \
    "Glob redirects to CBM search_graph"

echo ""
echo "--- Layer 2: Read/Edit/Write on code files denied ---"
test_denied_with_alternative '{"tool_name":"Read","tool_input":{"file_path":"src/main.py"}}' \
    "mcp__serena__" \
    "Read .py denied → Serena suggestion"
test_denied_with_alternative '{"tool_name":"Read","tool_input":{"file_path":"pkg/agent/agent.go"}}' \
    "mcp__serena__" \
    "Read .go denied → Serena suggestion"
test_denied_with_alternative '{"tool_name":"Edit","tool_input":{"file_path":"src/index.ts"}}' \
    "mcp__serena__replace" \
    "Edit .ts denied → Serena replace suggestion"
test_denied_with_alternative '{"tool_name":"Write","tool_input":{"file_path":"lib/utils.rs"}}' \
    "mcp__serena__replace" \
    "Write .rs denied → Serena replace suggestion"
test_denied_with_alternative '{"tool_name":"Read","tool_input":{"file_path":"test/test_main.java"}}' \
    "mcp__serena__" \
    "Read .java denied"

echo ""
echo "--- Layer 2: Non-code files allowed through ---"
test_allowed '{"tool_name":"Read","tool_input":{"file_path":"config.yaml"}}' \
    "Read .yaml allowed"
test_allowed '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
    "Read .md allowed"
test_allowed '{"tool_name":"Edit","tool_input":{"file_path":"settings.json"}}' \
    "Edit .json allowed"
test_allowed '{"tool_name":"Read","tool_input":{"file_path":".gitignore"}}' \
    "Read .gitignore allowed"
test_allowed '{"tool_name":"Read","tool_input":{"file_path":"Makefile"}}' \
    "Read Makefile allowed"
test_allowed '{"tool_name":"Read","tool_input":{"file_path":"Dockerfile"}}' \
    "Read Dockerfile allowed"

echo ""
echo "--- Edge cases ---"
test_denied_with_alternative '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}' \
    "mcp__serena__" \
    "Read .sh denied (code file)"
test_allowed '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    "Bash always allowed (not matched by this hook)"

echo ""
echo "--- Layer 3: Serena edit guard (warn without refs) ---"
# Serena edit without prior refs → warn (exit 1)
WARN_RESULT=$(run_enforcement '{"tool_name":"mcp__serena__replace_symbol_body","tool_input":{"relative_path":"orca/sensors/base.py"},"session_id":"test-123"}')
WARN_EXIT="${WARN_RESULT%%|*}"
WARN_MSG="${WARN_RESULT#*|}"
if [ "$WARN_EXIT" = "1" ]; then
    echo "  [PASS] Serena edit without refs → warned (exit 1)"
    passed=$((passed+1))
else
    echo "  [FAIL] Serena edit without refs — expected warn (exit 1), got $WARN_EXIT"
    failed=$((failed+1))
fi
if echo "$WARN_MSG" | grep -q "find_referencing_symbols"; then
    echo "  [PASS] Warning suggests find_referencing_symbols"
    passed=$((passed+1))
else
    echo "  [FAIL] Warning missing find_referencing_symbols suggestion"
    failed=$((failed+1))
fi

# safe_delete_symbol without refs → warn
DELETE_RESULT=$(run_enforcement '{"tool_name":"mcp__serena__safe_delete_symbol","tool_input":{"relative_path":"orca/models.py"},"session_id":"test-456"}')
DELETE_EXIT="${DELETE_RESULT%%|*}"
if [ "$DELETE_EXIT" = "1" ]; then
    echo "  [PASS] safe_delete_symbol without refs → warned (exit 1)"
    passed=$((passed+1))
else
    echo "  [FAIL] safe_delete_symbol without refs — expected warn (exit 1), got $DELETE_EXIT"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-pre-tool-use.sh`
Expected: FAIL — v1 hook suggests codanna (not CBM), and doesn't handle safe_delete_symbol

- [ ] **Step 3: Update pre-tool-router**

Edit `hooks/pre-tool-router` — change suggestion messages and add safe_delete_symbol to Layer 3:

Layer 1 changes:
- `Grep` message: change `mcp__codanna__semantic_search_with_context` → `mcp__codebase-memory-mcp__search_code`
- `Glob` message: change `mcp__codanna__search_symbols` → `mcp__codebase-memory-mcp__search_graph`

Layer 2 changes:
- `Read` message: change `mcp__serena__find_symbol(include_body=True) or mcp__serena__read_file` → `mcp__codebase-memory-mcp__get_code_snippet or mcp__serena__find_symbol(include_body=True)`

Layer 3 changes:
- Add `mcp__serena__safe_delete_symbol` to the case pattern

The updated `hooks/pre-tool-router`:

```bash
#!/usr/bin/env bash
# PreToolUse router: native tool blocking + Serena edit guard.
#
# Layer 1: Block Grep/Glob unconditionally → route to CBM
# Layer 2: Block Read/Edit/Write on code files → route to CBM/Serena
# Layer 3: Warn on Serena edits without prior find_referencing_symbols
#
# ~10ms per call. Exit 0=allow, 1=warn, 2=block. Fail-open on errors.

JQ=$(command -v jq 2>/dev/null || command -v jaq 2>/dev/null) || exit 0

input=$(</dev/stdin) 2>/dev/null || exit 0

# Single JSON extraction — newline-delimited (tabs collapse empty fields)
parsed=$(printf '%s' "$input" | "$JQ" -r \
  '[.tool_name // "", (.tool_input.file_path // .tool_input.pattern // .tool_input.path // ""), (.tool_input.relative_path // ""), (.session_id // "")] | .[]' \
  2>/dev/null) || exit 0
{ read -r tool_name; read -r file_path; read -r relative_path; read -r session_id; } <<< "$parsed"

# ═══════════════════════════════════════════════════════════════════════
# LAYER 1: Block Grep/Glob unconditionally
# ═══════════════════════════════════════════════════════════════════════
case "$tool_name" in
  Grep)
    echo "BLOCKED: Native Grep. Use mcp__codebase-memory-mcp__search_code or mcp__serena__search_for_pattern." >&2
    exit 2 ;;
  Glob)
    echo "BLOCKED: Native Glob. Use mcp__codebase-memory-mcp__search_graph or mcp__serena__find_file." >&2
    exit 2 ;;
esac

# ═══════════════════════════════════════════════════════════════════════
# LAYER 2: Block native Read/Edit/Write on code files
# ═══════════════════════════════════════════════════════════════════════
case "$tool_name" in
  Read|Edit|Write)
    if [[ -n "$file_path" ]]; then
      case "$file_path" in
        *.py|*.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.cpp|*.c|*.h|*.hpp|*.rb|*.java|*.kt|*.php|*.scala|*.swift|*.sh|*.bash)
          case "$tool_name" in
            Read)
              echo "BLOCKED: Native Read on '$file_path'. Use mcp__codebase-memory-mcp__get_code_snippet or mcp__serena__find_symbol(include_body=True)." >&2 ;;
            Edit|Write)
              echo "BLOCKED: Native $tool_name on '$file_path'. Use mcp__serena__replace_symbol_body or mcp__serena__replace_content." >&2 ;;
          esac
          exit 2 ;;
      esac
    fi
    ;;
esac

# ═══════════════════════════════════════════════════════════════════════
# LAYER 3: Serena edit guard (find_referencing_symbols before edits)
# ═══════════════════════════════════════════════════════════════════════
case "$tool_name" in
  mcp__serena__replace_symbol_body|\
  mcp__serena__replace_content|\
  mcp__serena__insert_after_symbol|\
  mcp__serena__insert_before_symbol|\
  mcp__serena__rename_symbol|\
  mcp__serena__safe_delete_symbol)
    if [[ -n "$relative_path" ]]; then
      STATE_FILE="${CLAUDE_PLUGIN_ROOT:-/tmp}/state/refs-traced.json"
      if [[ -f "$STATE_FILE" ]]; then
        state_check=$("$JQ" -r --arg p "$relative_path" --arg s "$session_id" \
          'if .session_id == $s and .traced[$p] != null then "ok" else "no" end' \
          "$STATE_FILE" 2>/dev/null) || state_check="no"
        if [[ "$state_check" == "ok" ]]; then
          exit 0
        fi
      fi
      echo "[serena-edit-guard] Editing '${relative_path}' without tracing references." >&2
      echo "Call mcp__serena__find_referencing_symbols first to check downstream impact." >&2
      exit 1
    fi
    ;;
esac

exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/unit/test-pre-tool-use.sh`
Expected: PASS — all assertions pass with CBM suggestions

- [ ] **Step 5: Commit**

```bash
git add hooks/pre-tool-router tests/unit/test-pre-tool-use.sh
git commit -m "feat: pre-tool-router suggests CBM tools, adds safe_delete_symbol guard"
```

---

## Task 7: session-start update (inject updated orca-setup)

**Files:**
- Modify: `hooks/session-start`
- Test: `tests/unit/test-session-output.sh`

- [ ] **Step 1: Write failing test — expects CBM refs in session output**

Replace `tests/unit/test-session-output.sh`:

```bash
#!/usr/bin/env bash
# Unit test: session-start hook JSON output shape — v7
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

setup_sandbox
trap cleanup_sandbox EXIT

passed=0; failed=0

echo "=== Unit: session-start output shape ==="
echo ""

# Test from orca dir (using sandbox)
output=$(run_hook_from "$SANDBOX/src/orca")

if assert_valid_json "$output" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.additionalContext' "hookSpecificOutput.additionalContext present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.hookEventName' "hookSpecificOutput.hookEventName present"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.additional_context' "additional_context present (Cursor compat)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "EXTREMELY_IMPORTANT" "contains EXTREMELY_IMPORTANT wrapper"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "mcp__serena__activate_project" "contains Serena activation call"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# v7: must reference CBM tools, NOT codanna
if assert_contains "$output" "mcp__codebase-memory-mcp__" "contains CBM tool references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output" "mcp__codanna__" "no codanna references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "find_referencing_symbols" "contains find_referencing_symbols mandate"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "search_code" "contains CBM search_code"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "get_code_snippet" "contains CBM get_code_snippet"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# Test from unknown dir -- should still produce valid JSON without activation
echo ""
echo "--- From /tmp (no project) ---"
output2=$(run_hook_from /tmp)

if assert_valid_json "$output2" "output valid JSON (no project)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_not_contains "$output2" "SERENA WORKSPACE DETECTED" "no project-specific activation for unknown dir"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-session-output.sh`
Expected: FAIL — v1 session-start injects codanna references

- [ ] **Step 3: Update session-start hook**

The session-start hook reads `skills/orca-setup/SKILL.md` and injects it. Since we already updated orca-setup in Task 4, the hook script itself only needs one change: update the SessionStart matcher comment. The hook reads the skill file dynamically, so the content change propagates automatically.

Verify: `grep -c codanna hooks/session-start` should be 0 (the hook doesn't hardcode tool names — it reads the skill file).

If there are any hardcoded codanna references in the session-start script, replace them with CBM equivalents.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/unit/test-session-output.sh`
Expected: PASS — output contains CBM refs, no codanna

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start tests/unit/test-session-output.sh
git commit -m "feat: session-start injects CBM-based orca-setup skill"
```

---

## Task 8: session-start-compact hook (NEW)

**Files:**
- Create: `hooks/session-start-compact` (replace stub)
- Create: `tests/unit/test-session-compact.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test-session-compact.sh`:

```bash
#!/usr/bin/env bash
# Unit test: session-start-compact behavioral contract — v7
# Contract: produces valid JSON with slim routing reminder, not full skill content
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: session-start-compact ==="
echo ""

HOOK="${PLUGIN_ROOT}/hooks/session-start-compact"

# Run from ~/src equivalent (sandbox)
setup_sandbox
trap cleanup_sandbox EXIT

output=$(run_hook_from "$SANDBOX/src/orca" "$HOOK")

# --- Valid JSON output ---
if assert_valid_json "$output" "output is valid JSON"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.hookSpecificOutput.additionalContext' "has additionalContext"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_json_field "$output" '.additional_context' "has additional_context (Cursor compat)"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# --- Contains routing reminder ---
if assert_contains "$output" "tool_routing" "contains <tool_routing> block"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# --- Contains CBM tool names ---
if assert_contains "$output" "mcp__codebase-memory-mcp__search_code" "contains CBM search_code"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "get_code_snippet" "contains CBM get_code_snippet"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "get_architecture" "contains CBM get_architecture"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# --- Contains Serena edit tools ---
if assert_contains "$output" "replace_symbol_body" "contains Serena replace_symbol_body"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "find_referencing_symbols" "contains pre-edit mandate"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "safe_delete_symbol" "contains safe_delete_symbol"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# --- Contains key param reminders ---
if assert_contains "$output" '\$!1' "contains backrefs reminder"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "qualified_name" "contains qualified_name param"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

# --- Is slim (not full skill content) ---
ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')
ctx_lines=$(echo "$ctx" | wc -l)
if [ "$ctx_lines" -lt 50 ]; then
    echo "  [PASS] compact content is slim ($ctx_lines lines < 50)"
    passed=$((passed+1))
else
    echo "  [FAIL] compact content is too large ($ctx_lines lines >= 50) — should be ~30 lines"
    failed=$((failed+1))
fi

# --- No codanna ---
if assert_not_contains "$output" "codanna" "no codanna references"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-session-compact.sh`
Expected: FAIL — the stub file produces no output

- [ ] **Step 3: Write session-start-compact hook**

Replace the stub `hooks/session-start-compact`:

```bash
#!/usr/bin/env bash
# SessionStart compact/resume handler: inject slim routing reminder.
# Fires on resume|compact — avoids doubling full skill content on resume.
set -euo pipefail

ROUTING_CONTENT='<tool_routing>
ROUTING RULES (post-compaction reminder):

Source code SEARCH: mcp__codebase-memory-mcp__search_code(pattern=, project=), search_graph(query=, project=), get_code_snippet(qualified_name=), trace_path(source=, target=, project=), get_architecture(project=)
Source code EDIT: mcp__serena__replace_symbol_body(name_path=, relative_path=, body=), replace_content(relative_path=, needle=, repl=, mode=), insert_after_symbol, insert_before_symbol, rename_symbol, safe_delete_symbol
Pre-edit MANDATORY: mcp__serena__find_referencing_symbols(name_path=, relative_path=FILE) before any edit/delete
Non-code files (.json .yaml .md .toml .sh Makefile Dockerfile): native Read/Edit/Write allowed
NEVER: native Read/Edit/Write/Grep/Glob on source files (.py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java)

Key params:
- search_code: pattern (not query), project required
- get_code_snippet: qualified_name (not relative_path+start_line)
- replace_content: needle/repl/mode ("literal"|"regex"), backrefs $!1 (not \1)
- read_file: 0-based lines, end_line inclusive
- find_referencing_symbols: relative_path must be a FILE, not a directory

Start multi-symbol exploration with get_architecture(project=...) — one call replaces 4-6 round-trips.
Batch all independent tool calls in one message.
</tool_routing>'

JQ=$(command -v jq 2>/dev/null || command -v jaq 2>/dev/null) || {
  echo '{"additional_context":"","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":""}}'
  exit 0
}

"$JQ" -n --arg ctx "$ROUTING_CONTENT" \
  '{"additional_context": $ctx,
    "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'

exit 0
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x hooks/session-start-compact
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/unit/test-session-compact.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-compact tests/unit/test-session-compact.sh
git commit -m "feat: session-start-compact hook for resume/compact re-injection"
```

---

## Task 9: rtk-rewrite-bash hook (NEW from v6)

**Files:**
- Create: `hooks/rtk-rewrite-bash` (replace stub)
- Create: `tests/unit/test-rtk-rewrite.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test-rtk-rewrite.sh`:

```bash
#!/usr/bin/env bash
# Unit test: rtk-rewrite-bash behavioral contract — v7
# Contract: rewrites eligible bash commands through RTK, never blocks, fails open
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: rtk-rewrite-bash ==="
echo ""

HOOK="${PLUGIN_ROOT}/hooks/rtk-rewrite-bash"

# Helper: run hook, capture stdout (JSON) and exit code
run_rtk_hook() {
    local json="$1"
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    local exit_code=0
    echo "$json" | bash "$HOOK" >"$stdout_file" 2>"$stderr_file" || exit_code=$?
    local stdout_out
    stdout_out=$(cat "$stdout_file")
    rm -f "$stdout_file" "$stderr_file"
    echo "${exit_code}|${stdout_out}"
}

# --- Always exit 0 (never blocks) ---
echo "--- Never blocks ---"

RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
EXIT="${RESULT%%|*}"
if [ "$EXIT" = "0" ]; then
    echo "  [PASS] exit 0 for git command"
    passed=$((passed+1))
else
    echo "  [FAIL] expected exit 0, got $EXIT"
    failed=$((failed+1))
fi

# --- Non-Bash tool passes through ---
echo ""
echo "--- Non-Bash passthrough ---"

RESULT=$(run_rtk_hook '{"tool_name":"Read","tool_input":{"file_path":"foo.py"}}')
EXIT="${RESULT%%|*}"
STDOUT="${RESULT#*|}"
if [ "$EXIT" = "0" ] && [ -z "$STDOUT" ]; then
    echo "  [PASS] non-Bash tool produces no output, exit 0"
    passed=$((passed+1))
else
    echo "  [FAIL] non-Bash: exit=$EXIT stdout='$STDOUT'"
    failed=$((failed+1))
fi

# --- Shell metacharacters not rewritten ---
echo ""
echo "--- Shell metacharacters skip rewrite ---"

RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"echo foo | grep bar"}}')
EXIT="${RESULT%%|*}"
STDOUT="${RESULT#*|}"
if [ "$EXIT" = "0" ] && [ -z "$STDOUT" ]; then
    echo "  [PASS] pipe command not rewritten (no JSON output)"
    passed=$((passed+1))
else
    echo "  [FAIL] pipe command: exit=$EXIT stdout='$STDOUT'"
    failed=$((failed+1))
fi

RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"cat <<EOF\nhello\nEOF"}}')
EXIT="${RESULT%%|*}"
STDOUT="${RESULT#*|}"
if [ "$EXIT" = "0" ] && [ -z "$STDOUT" ]; then
    echo "  [PASS] heredoc not rewritten"
    passed=$((passed+1))
else
    echo "  [FAIL] heredoc: exit=$EXIT"
    failed=$((failed+1))
fi

# --- Empty command ---
echo ""
echo "--- Empty command ---"

RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":""}}')
EXIT="${RESULT%%|*}"
if [ "$EXIT" = "0" ]; then
    echo "  [PASS] empty command exit 0"
    passed=$((passed+1))
else
    echo "  [FAIL] empty command exit $EXIT"
    failed=$((failed+1))
fi

# --- RTK not installed: graceful fallthrough ---
echo ""
echo "--- RTK not installed ---"

# Temporarily hide rtk from PATH
OLD_PATH="$PATH"
export PATH=$(echo "$PATH" | tr ':' '\n' | grep -v rtk | tr '\n' ':')
RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
EXIT="${RESULT%%|*}"
STDOUT="${RESULT#*|}"
export PATH="$OLD_PATH"
if [ "$EXIT" = "0" ] && [ -z "$STDOUT" ]; then
    echo "  [PASS] no rtk → graceful fallthrough (no output, exit 0)"
    passed=$((passed+1))
else
    echo "  [FAIL] no rtk: exit=$EXIT stdout='$STDOUT'"
    failed=$((failed+1))
fi

# --- If RTK is available, test actual rewrite ---
echo ""
echo "--- RTK rewrite (if available) ---"

if command -v rtk >/dev/null 2>&1; then
    RESULT=$(run_rtk_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
    EXIT="${RESULT%%|*}"
    STDOUT="${RESULT#*|}"
    if [ "$EXIT" = "0" ] && [ -n "$STDOUT" ]; then
        if echo "$STDOUT" | jq -e '.hookSpecificOutput.updatedInput.command' >/dev/null 2>&1; then
            REWRITTEN=$(echo "$STDOUT" | jq -r '.hookSpecificOutput.updatedInput.command')
            echo "  [PASS] git status rewritten to: $REWRITTEN"
            passed=$((passed+1))
        else
            echo "  [FAIL] JSON output missing updatedInput.command"
            failed=$((failed+1))
        fi
    else
        echo "  [SKIP] rtk available but no rewrite produced (may be expected)"
        passed=$((passed+1))
    fi
else
    echo "  [SKIP] rtk not installed — skipping rewrite test"
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-rtk-rewrite.sh`
Expected: FAIL — stub file produces no output / errors

- [ ] **Step 3: Write rtk-rewrite-bash hook**

Replace the stub `hooks/rtk-rewrite-bash` (ported from v6):

```bash
#!/usr/bin/env bash
# PreToolUse: rewrite Bash commands through rtk for token savings.
# Falls through on shell metacharacters, missing rtk, or CLAUDE_RAW=1.
set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -n "$CMD" ]] || exit 0
[[ -z "${CLAUDE_RAW:-}" ]] || exit 0

# Skip commands with shell metacharacters (pipes, redirects, subshells, heredocs)
echo "$CMD" | grep -Eq '[|&;<>$`(){}]|<<' && exit 0

command -v rtk >/dev/null 2>&1 || exit 0

# Run rtk rewrite with timeout
if command -v timeout >/dev/null 2>&1; then
    REWRITTEN=$(timeout 2 rtk rewrite "$CMD" 2>/dev/null || true)
elif command -v gtimeout >/dev/null 2>&1; then
    REWRITTEN=$(gtimeout 2 rtk rewrite "$CMD" 2>/dev/null || true)
else
    REWRITTEN=$(rtk rewrite "$CMD" 2>/dev/null || true)
fi

[[ -n "$REWRITTEN" && "$REWRITTEN" != "$CMD" ]] || exit 0

jq -n --arg cmd "$REWRITTEN" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "rtk auto-rewrite for token economy",
    updatedInput: { command: $cmd }
  }
}'
exit 0
```

- [ ] **Step 4: Make it executable**

```bash
chmod +x hooks/rtk-rewrite-bash
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/unit/test-rtk-rewrite.sh`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add hooks/rtk-rewrite-bash tests/unit/test-rtk-rewrite.sh
git commit -m "feat: rtk-rewrite-bash hook for token-optimized Bash commands"
```

---

## Task 10: skill-activation-prompt test (NEW)

**Files:**
- Create: `tests/unit/test-skill-activation.sh`
- Note: `hooks/skill-activation-prompt` script is unchanged — it reads the updated `skill-rules.json`

- [ ] **Step 1: Write test**

Create `tests/unit/test-skill-activation.sh`:

```bash
#!/usr/bin/env bash
# Unit test: skill-activation-prompt behavioral contract — v7
# Contract: matches keywords → suggests correct skill, no match → no output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../helpers.sh"

passed=0; failed=0

echo "=== Unit: skill-activation-prompt ==="
echo ""

HOOK="${PLUGIN_ROOT}/hooks/skill-activation-prompt"

# Helper: run hook with a prompt, capture stdout
run_prompt() {
    local prompt_text="$1"
    local json
    json=$(jq -n --arg p "$prompt_text" '{"prompt": $p}')
    echo "$json" | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK" 2>/dev/null || true
}

# --- CBM skill suggested for code search keywords ---
echo "--- CBM skill suggestions ---"

OUTPUT=$(run_prompt "search code for authentication")
if echo "$OUTPUT" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'search code' → suggests cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'search code' should suggest cbm-workflow, got: $OUTPUT"
    failed=$((failed+1))
fi

OUTPUT=$(run_prompt "who calls process_event")
if echo "$OUTPUT" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'who calls' → suggests cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'who calls' should suggest cbm-workflow, got: $OUTPUT"
    failed=$((failed+1))
fi

OUTPUT=$(run_prompt "how does the sensor pipeline work")
if echo "$OUTPUT" | grep -qi "cbm-workflow"; then
    echo "  [PASS] 'how does' → suggests cbm-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'how does' should suggest cbm-workflow, got: $OUTPUT"
    failed=$((failed+1))
fi

# --- Serena skill suggested for edit keywords ---
echo ""
echo "--- Serena skill suggestions ---"

OUTPUT=$(run_prompt "refactor the authentication module")
if echo "$OUTPUT" | grep -qi "serena-workflow"; then
    echo "  [PASS] 'refactor' → suggests serena-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'refactor' should suggest serena-workflow, got: $OUTPUT"
    failed=$((failed+1))
fi

OUTPUT=$(run_prompt "fix bug in process_event handler")
if echo "$OUTPUT" | grep -qi "serena-workflow"; then
    echo "  [PASS] 'fix bug' → suggests serena-workflow"
    passed=$((passed+1))
else
    echo "  [FAIL] 'fix bug' should suggest serena-workflow, got: $OUTPUT"
    failed=$((failed+1))
fi

# --- No suggestion for unrelated prompts ---
echo ""
echo "--- No suggestion for unrelated ---"

OUTPUT=$(run_prompt "hello how are you")
if [ -z "$OUTPUT" ]; then
    echo "  [PASS] 'hello' → no suggestion (empty output)"
    passed=$((passed+1))
else
    echo "  [FAIL] 'hello' should produce no output, got: $OUTPUT"
    failed=$((failed+1))
fi

OUTPUT=$(run_prompt "what time is it")
if [ -z "$OUTPUT" ]; then
    echo "  [PASS] 'what time' → no suggestion"
    passed=$((passed+1))
else
    echo "  [FAIL] 'what time' should produce no output, got: $OUTPUT"
    failed=$((failed+1))
fi

# --- Both skills suggested for combined prompt ---
echo ""
echo "--- Both skills for combined prompt ---"

OUTPUT=$(run_prompt "find callers and edit the function")
CBM_MATCH=""
SERENA_MATCH=""
echo "$OUTPUT" | grep -qi "cbm-workflow" && CBM_MATCH="yes"
echo "$OUTPUT" | grep -qi "serena-workflow" && SERENA_MATCH="yes"
if [ "$CBM_MATCH" = "yes" ] && [ "$SERENA_MATCH" = "yes" ]; then
    echo "  [PASS] combined prompt → suggests both skills"
    passed=$((passed+1))
else
    echo "  [FAIL] combined prompt should suggest both, got: $OUTPUT"
    failed=$((failed+1))
fi

echo ""
echo "Passed: $passed  Failed: $failed"
[ $failed -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/unit/test-skill-activation.sh`
Expected: PASS — the skill-activation-prompt hook reads the updated skill-rules.json

If any tests fail, it's because the keyword matching logic in `skill-activation-prompt` needs adjustment for the new skill names. The hook reads skill names from skill-rules.json keys, so "cbm-workflow" and "serena-workflow" should appear in the output.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-skill-activation.sh
git commit -m "test: skill-activation-prompt behavioral contract tests"
```

---

## Task 11: Update remaining carried tests

**Files:**
- Modify: `tests/unit/test-hooks-smoke.sh`
- Modify: `tests/unit/test-hook-properties.sh`

- [ ] **Step 1: Update test-hooks-smoke.sh**

Add smoke tests for the two new hooks (session-start-compact, rtk-rewrite-bash). Find the section that loops through hooks and add entries for the new ones. The new hooks should:
- Accept valid JSON on stdin
- Exit 0
- Not crash

Add these test cases to the existing smoke test file:

```bash
# --- session-start-compact smoke ---
echo "--- session-start-compact ---"
COMPACT_OUT=$(echo '{}' | bash "${PLUGIN_ROOT}/hooks/session-start-compact" 2>/dev/null) && COMPACT_EXIT=0 || COMPACT_EXIT=$?
if [ "$COMPACT_EXIT" = "0" ]; then
    echo "  [PASS] session-start-compact exits 0"
    passed=$((passed+1))
else
    echo "  [FAIL] session-start-compact exits $COMPACT_EXIT"
    failed=$((failed+1))
fi

# --- rtk-rewrite-bash smoke ---
echo "--- rtk-rewrite-bash ---"
RTK_OUT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | bash "${PLUGIN_ROOT}/hooks/rtk-rewrite-bash" 2>/dev/null) && RTK_EXIT=0 || RTK_EXIT=$?
if [ "$RTK_EXIT" = "0" ]; then
    echo "  [PASS] rtk-rewrite-bash exits 0"
    passed=$((passed+1))
else
    echo "  [FAIL] rtk-rewrite-bash exits $RTK_EXIT"
    failed=$((failed+1))
fi
```

- [ ] **Step 2: Update test-hook-properties.sh**

Verify that hooks.json references the new scripts and they have timeouts. Add checks for:
- `session-start-compact` referenced in SessionStart array
- `rtk-rewrite-bash` referenced in PreToolUse array
- Both have valid timeout values

- [ ] **Step 3: Run full unit test suite**

Run: `bash tests/run-all.sh --unit --verbose`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-hooks-smoke.sh tests/unit/test-hook-properties.sh
git commit -m "test: update smoke and properties tests for v7 hooks"
```

---

## Task 12: E2E test infrastructure

**Files:**
- Create: `tests/e2e/lib/launch-session.sh`
- Create: `tests/e2e/lib/verify-transcript.sh`
- Create: `tests/e2e/lib/assert-routing.sh`
- Create: `tests/e2e/run-e2e.sh`

- [ ] **Step 1: Create launch-session.sh**

```bash
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
```

- [ ] **Step 2: Create verify-transcript.sh**

```bash
#!/usr/bin/env bash
# Parse stream-json transcript, extract tool calls
set -euo pipefail

# Extract all tool_use names from stream-json transcript
extract_tool_calls() {
    local transcript="$1"
    echo "$transcript" | jq -r '
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use") |
        .name
    ' 2>/dev/null | sort
}

# Extract unique tool namespaces (e.g., mcp__codebase-memory-mcp__)
extract_tool_namespaces() {
    local transcript="$1"
    extract_tool_calls "$transcript" | sed 's/__[^_]*$//' | sort -u
}

export -f extract_tool_calls
export -f extract_tool_namespaces
```

- [ ] **Step 3: Create assert-routing.sh**

```bash
#!/usr/bin/env bash
# Routing assertion helpers for E2E tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/verify-transcript.sh"

# Assert a tool namespace was used in the transcript
assert_tool_used() {
    local transcript="$1"
    local tool_pattern="$2"
    local test_name="$3"
    local tools
    tools=$(extract_tool_calls "$transcript")
    if echo "$tools" | grep -q "$tool_pattern"; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — expected '$tool_pattern' in tool calls"
        return 1
    fi
}

# Assert a tool was NOT used
assert_tool_not_used() {
    local transcript="$1"
    local tool_pattern="$2"
    local test_name="$3"
    local tools
    tools=$(extract_tool_calls "$transcript")
    if echo "$tools" | grep -q "$tool_pattern"; then
        echo "  [FAIL] $test_name — found forbidden '$tool_pattern' in tool calls"
        return 1
    else
        echo "  [PASS] $test_name"
        return 0
    fi
}

# Assert tool A appears before tool B
assert_tool_before() {
    local transcript="$1"
    local tool_a="$2"
    local tool_b="$3"
    local test_name="$4"
    local tools
    tools=$(extract_tool_calls "$transcript")
    local pos_a pos_b
    pos_a=$(echo "$tools" | grep -n "$tool_a" | head -1 | cut -d: -f1)
    pos_b=$(echo "$tools" | grep -n "$tool_b" | head -1 | cut -d: -f1)
    if [ -n "$pos_a" ] && [ -n "$pos_b" ] && [ "$pos_a" -lt "$pos_b" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — expected '$tool_a' before '$tool_b'"
        return 1
    fi
}

# Assert no native Read/Edit/Write/Grep/Glob on source code files
assert_no_native_on_code() {
    local transcript="$1"
    local test_name="$2"
    # Check for native tool calls with source file extensions
    local violations
    violations=$(echo "$transcript" | jq -r '
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use") |
        select(.name == "Read" or .name == "Edit" or .name == "Write" or .name == "Grep" or .name == "Glob") |
        .input.file_path // .input.pattern // "unknown"
    ' 2>/dev/null | grep -E '\.(py|go|ts|tsx|js|jsx|rs|cpp|c|h|hpp|rb|java)$' || true)

    if [ -z "$violations" ]; then
        echo "  [PASS] $test_name"
        return 0
    else
        echo "  [FAIL] $test_name — native tools used on source: $violations"
        return 1
    fi
}

export -f assert_tool_used
export -f assert_tool_not_used
export -f assert_tool_before
export -f assert_no_native_on_code
```

- [ ] **Step 4: Create run-e2e.sh**

```bash
#!/usr/bin/env bash
# E2E test runner: parallel project matrix
# Usage: E2E=1 bash tests/e2e/run-e2e.sh
set -euo pipefail

if [ "${E2E:-0}" != "1" ]; then
    echo "E2E tests skipped (set E2E=1 to run)"
    exit 0
fi

if ! command -v claude &>/dev/null; then
    echo "ERROR: claude CLI not found"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"
mkdir -p "$RESULTS_DIR"

echo "========================================"
echo " E2E Test Matrix"
echo "========================================"
echo "Date: $(date)"
echo "Results: $RESULTS_DIR"
echo ""

# Launch all 4 matrix tests in parallel
pids=()
tests=()

for test_file in "${SCRIPT_DIR}/matrix"/*.sh; do
    [ -f "$test_file" ] || continue
    test_name=$(basename "$test_file" .sh)
    tests+=("$test_name")
    echo "Launching: $test_name"
    bash "$test_file" > "${RESULTS_DIR}/${test_name}.log" 2>&1 &
    pids+=($!)
done

echo ""
echo "Waiting for ${#pids[@]} parallel tests..."
echo ""

# Wait and collect results
failures=0
for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
        echo "[PASS] ${tests[$i]}"
    else
        echo "[FAIL] ${tests[$i]} (see ${RESULTS_DIR}/${tests[$i]}.log)"
        failures=$((failures+1))
    fi
done

echo ""
echo "========================================"
echo "Matrix: ${#tests[@]} projects, $failures failures"
echo "========================================"

if [ $failures -eq 0 ]; then
    echo "STATUS: PASSED"
    exit 0
else
    echo "STATUS: FAILED"
    exit 1
fi
```

- [ ] **Step 5: Commit**

```bash
mkdir -p tests/e2e/lib tests/e2e/matrix tests/e2e/results
echo '*' > tests/e2e/results/.gitignore
chmod +x tests/e2e/run-e2e.sh tests/e2e/lib/*.sh
git add tests/e2e/
git commit -m "feat: E2E test infrastructure — launcher, transcript parser, routing assertions"
```

---

## Task 13: E2E matrix tests

**Files:**
- Create: `tests/e2e/matrix/orca-python-feature.sh`
- Create: `tests/e2e/matrix/sensor-go-feature.sh`
- Create: `tests/e2e/matrix/runtime-go-feature.sh`
- Create: `tests/e2e/matrix/helm-yaml-feature.sh`

- [ ] **Step 1: Create orca-python-feature.sh**

```bash
#!/usr/bin/env bash
# E2E: Python feature task — add last_seen_at to User model
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

passed=0; failed=0
MAX_RETRIES=3

echo "=== E2E: orca-python-feature ==="

run_segment_with_retry() {
    local segment_name="$1"
    local prompt="$2"
    shift 2
    local attempt
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [$segment_name] attempt $attempt/$MAX_RETRIES"
        local transcript
        transcript=$(launch_session "$prompt" "$HOME/src" 3 120)
        local segment_pass=true
        for assertion in "$@"; do
            eval "$assertion" || segment_pass=false
        done
        if $segment_pass; then
            passed=$((passed+1))
            return 0
        fi
    done
    failed=$((failed+1))
    return 1
}

# Segment 1: Explore
run_segment_with_retry "explore" \
    "Find where the User model is defined in the orca project and show me its fields" \
    'assert_tool_used "$transcript" "mcp__codebase-memory-mcp__" "used CBM for exploration"' \
    'assert_no_native_on_code "$transcript" "no native tools on source"'

# Segment 2: Plan (trace refs)
run_segment_with_retry "plan" \
    "Show me all references to the User model before we modify it" \
    'assert_tool_used "$transcript" "find_referencing_symbols" "traced refs"'

# Segment 3: Edit
run_segment_with_retry "edit" \
    "Add a last_seen_at DateTimeField to the User model" \
    'assert_tool_used "$transcript" "mcp__serena__" "used Serena for edit"' \
    'assert_tool_not_used "$transcript" "^Edit$" "no native Edit"'

# Segment 4: Verify
run_segment_with_retry "verify" \
    "Run the tests for the User model" \
    'assert_tool_used "$transcript" "Bash" "ran tests via Bash"'

echo ""
REQUIRED_PASS=3
echo "Passed: $passed / 4 segments (need $REQUIRED_PASS)"
[ $passed -ge $REQUIRED_PASS ] && exit 0 || exit 1
```

- [ ] **Step 2: Create sensor-go-feature.sh**

```bash
#!/usr/bin/env bash
# E2E: Go feature task — add --dry-run flag to collector CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

passed=0; failed=0
MAX_RETRIES=3

echo "=== E2E: sensor-go-feature ==="

run_segment_with_retry() {
    local segment_name="$1"
    local prompt="$2"
    shift 2
    local attempt
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [$segment_name] attempt $attempt/$MAX_RETRIES"
        local transcript
        transcript=$(launch_session "$prompt" "$HOME/src" 3 120)
        local segment_pass=true
        for assertion in "$@"; do
            eval "$assertion" || segment_pass=false
        done
        if $segment_pass; then
            passed=$((passed+1))
            return 0
        fi
    done
    failed=$((failed+1))
    return 1
}

run_segment_with_retry "explore" \
    "Find the collector CLI entry point in orca-sensor and show me how command-line flags are parsed" \
    'assert_tool_used "$transcript" "mcp__codebase-memory-mcp__" "used CBM"' \
    'assert_no_native_on_code "$transcript" "no native on source"'

run_segment_with_retry "plan" \
    "Show me all references to the collector main function before we add a flag" \
    'assert_tool_used "$transcript" "find_referencing_symbols" "traced refs"'

run_segment_with_retry "edit" \
    "Add a --dry-run boolean flag to the collector CLI that logs what it would send" \
    'assert_tool_used "$transcript" "mcp__serena__" "used Serena"' \
    'assert_tool_not_used "$transcript" "^Edit$" "no native Edit"'

run_segment_with_retry "verify" \
    "Run go test for the collector package" \
    'assert_tool_used "$transcript" "Bash" "ran tests"'

echo ""
REQUIRED_PASS=3
echo "Passed: $passed / 4 (need $REQUIRED_PASS)"
[ $passed -ge $REQUIRED_PASS ] && exit 0 || exit 1
```

- [ ] **Step 3: Create runtime-go-feature.sh**

```bash
#!/usr/bin/env bash
# E2E: Go+eBPF feature task — extract TTL config constant
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

passed=0; failed=0
MAX_RETRIES=3

echo "=== E2E: runtime-go-feature ==="

run_segment_with_retry() {
    local segment_name="$1"
    local prompt="$2"
    shift 2
    local attempt
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [$segment_name] attempt $attempt/$MAX_RETRIES"
        local transcript
        transcript=$(launch_session "$prompt" "$HOME/src" 3 120)
        local segment_pass=true
        for assertion in "$@"; do
            eval "$assertion" || segment_pass=false
        done
        if $segment_pass; then
            passed=$((passed+1))
            return 0
        fi
    done
    failed=$((failed+1))
    return 1
}

run_segment_with_retry "explore" \
    "Find the process cache implementation in orca-runtime-sensor and show me where TTL values are defined" \
    'assert_tool_used "$transcript" "mcp__codebase-memory-mcp__" "used CBM"' \
    'assert_no_native_on_code "$transcript" "no native on source"'

run_segment_with_retry "plan" \
    "Show me all references to the process cache TTL before we refactor it" \
    'assert_tool_used "$transcript" "find_referencing_symbols" "traced refs"'

run_segment_with_retry "edit" \
    "Extract the hardcoded TTL into a named config constant and wire it through the constructor" \
    'assert_tool_used "$transcript" "mcp__serena__" "used Serena"' \
    'assert_tool_not_used "$transcript" "^Edit$" "no native Edit"'

run_segment_with_retry "verify" \
    "Run go test for the process cache package" \
    'assert_tool_used "$transcript" "Bash" "ran tests"'

echo ""
REQUIRED_PASS=3
echo "Passed: $passed / 4 (need $REQUIRED_PASS)"
[ $passed -ge $REQUIRED_PASS ] && exit 0 || exit 1
```

- [ ] **Step 4: Create helm-yaml-feature.sh (control case)**

```bash
#!/usr/bin/env bash
# E2E: YAML control case — add replicaCount to helm chart
# This is the CONTROL CASE: native Read/Edit SHOULD work on .yaml files.
# Proves the plugin doesn't over-block non-code files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/launch-session.sh"
source "${SCRIPT_DIR}/../lib/assert-routing.sh"

passed=0; failed=0
MAX_RETRIES=3

echo "=== E2E: helm-yaml-feature (control case) ==="

run_segment_with_retry() {
    local segment_name="$1"
    local prompt="$2"
    shift 2
    local attempt
    for attempt in $(seq 1 $MAX_RETRIES); do
        echo "  [$segment_name] attempt $attempt/$MAX_RETRIES"
        local transcript
        transcript=$(launch_session "$prompt" "$HOME/src" 3 120)
        local segment_pass=true
        for assertion in "$@"; do
            eval "$assertion" || segment_pass=false
        done
        if $segment_pass; then
            passed=$((passed+1))
            return 0
        fi
    done
    failed=$((failed+1))
    return 1
}

# YAML files should use native tools — this proves no over-blocking
run_segment_with_retry "explore" \
    "Show me the sensor helm chart values.yaml in helm-charts" \
    'assert_tool_used "$transcript" "Read" "used native Read on YAML (correct)"'

run_segment_with_retry "plan" \
    "What would adding a replicaCount value affect in this chart" \
    'true'  # No specific tool requirement for planning on YAML

run_segment_with_retry "edit" \
    "Add a replicaCount value defaulting to 1 in values.yaml and template it in the deployment.yaml" \
    'assert_tool_used "$transcript" "Edit" "used native Edit on YAML (correct)"'

run_segment_with_retry "verify" \
    "Run helm lint on the sensor chart" \
    'assert_tool_used "$transcript" "Bash" "ran helm lint"'

echo ""
REQUIRED_PASS=3
echo "Passed: $passed / 4 (need $REQUIRED_PASS)"
[ $passed -ge $REQUIRED_PASS ] && exit 0 || exit 1
```

- [ ] **Step 5: Make all executable and commit**

```bash
chmod +x tests/e2e/matrix/*.sh
git add tests/e2e/matrix/
git commit -m "feat: E2E matrix tests — 4 projects parallel from ~/src/"
```

---

## Task 14: Final integration — run full suite + version bump

- [ ] **Step 1: Delete settings.json if it exists**

```bash
rm -f .claude-plugin/settings.json
```

- [ ] **Step 2: Run full unit test suite**

Run: `bash tests/run-all.sh --unit --verbose`
Expected: ALL 13 tests PASS

- [ ] **Step 3: Fix any failures**

If any test fails, fix the issue and re-run. Do not skip tests.

- [ ] **Step 4: Verify no codanna references remain anywhere**

```bash
grep -ri codanna skills/ hooks/ tests/ .claude-plugin/ || echo "CLEAN: no codanna references"
```
Expected: "CLEAN: no codanna references"

- [ ] **Step 5: Verify CBM references exist where expected**

```bash
grep -r "mcp__codebase-memory-mcp__" skills/ hooks/ | wc -l
```
Expected: >10 references across skills and hooks

- [ ] **Step 6: Commit final state**

```bash
git add -A
git commit -m "feat: orca-env-plugin v7.0.0 — v1 pedagogy + v6 safety net

4 skills (~455 lines CBM/Serena pedagogy), 8 bash hooks,
no permissions.deny, parallel E2E test matrix.

Replaces codanna with CBM. Adds compact re-injection and RTK
bash rewriting from v6. Strict TDD with behavioral contract tests."
```

- [ ] **Step 7: Run E2E tests (optional, requires claude CLI + repos)**

```bash
E2E=1 bash tests/e2e/run-e2e.sh
```

Review results in `tests/e2e/results/`.
