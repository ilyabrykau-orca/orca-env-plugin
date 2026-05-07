# Skills + Hooks Refinement — Design

**Date:** 2026-05-07  
**Scope:** 4 skill rewrites + 7 hook fixes  
**Constraints:** No Python rewrite. Lean. Modelled on pilot-shell patterns.

---

## Goals

1. Reduce tokens injected at session start (orca-setup is always loaded)
2. Eliminate skill content overlap — one purpose per file
3. Remove all Serena memory tool calls from skills and hooks
4. Fix hook output format so reminders actually reach Claude (additionalContext JSON)
5. Fix state file path bug that causes pre-serena-edit-guard to always fire
6. Replace growing JSON call-log with a simple flag file

---

## Skills

### Ownership map (after)

| Skill | Owns | Cuts |
|-------|------|------|
| `orca-setup` | Session init: `activate_project` only. Projects table. Params cheat sheet. | Steps 2+3 (tool routing, call graphs, memory protocol). Verification section. |
| `cbm-workflow` | Quick-start table. Empty-result escalation ladder. CBM project names. | "Common Patterns" code block (~30 lines). Power Queries section. Edge Types reference. |
| `serena-workflow` | Pre-edit checklist. Edit tool selector table. Code examples A–D. Gotchas. | "Reading Code" CBM section. Entire Memory section. |
| `orca-dev` | Workspace routing table. Master tool-routing table. 4-rule edit protocol. Parallelism note. | CBM patterns prose. Duplicate project names table. |

### orca-setup (~40 lines target)

```
## Enforcement
Native Read/Edit/Write/Grep/Glob HARD-BLOCKED on .py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java
Non-code files (.json .yaml .md .toml .sh Makefile Dockerfile) → native ok.

## Session init
mcp__serena__activate_project(project=<detected>)
[NO memory calls]

## Projects
| short | CBM project | path | lang |
...

## Params cheat sheet
| tool | param | correct | wrong |
...
```

Rationale for keeping params cheat sheet in orca-setup: it's the most-referenced correction table and it's available from the first turn since orca-setup is always injected.

### cbm-workflow (~70 lines target)

Structure:
1. Quick-start table (keep as-is)
2. Empty-result escalation ladder (unique — keep)
3. CBM project names table (keep — uses full CBM project IDs unlike orca-setup's short names)
4. Wrong/right table (keep)

Cuts: "Common Patterns" code block (the quick-start table already covers this), Power Queries (rarely needed mid-session), Edge Types reference.

### serena-workflow (~90 lines target)

Structure:
1. Pre-edit checklist (mandatory, keep)
2. Edit tool selector table (keep)
3. Code examples A–D: replace_symbol_body, replace_content (literal+regex), insert, rename (keep, trim comments)
4. Gotchas table (keep)
5. Wrong/Right table (keep)

Cuts: "Reading Code" section — CBM is the right tool for reads; having it in serena-workflow is the primary source of overlap confusion. Entire Memory section — no Serena memory usage anywhere after this change.

### orca-dev (~40 lines target)

Structure:
1. Workspace routing table (unique, keep)
2. Tool routing table (master decision table, keep)
3. Edit protocol: 4 rules (keep)
4. Parallelism note (keep)

Cuts: "CBM patterns" prose (lives in cbm-workflow), project names table (lives in cbm-workflow and orca-setup).

### Line count delta

| Skill | Before | After | Δ |
|-------|--------|-------|---|
| orca-setup (always loaded) | 181 | ~40 | −141 |
| cbm-workflow | 211 | ~70 | −141 |
| serena-workflow | 169 | ~90 | −79 |
| orca-dev | 59 | ~40 | −19 |
| **Total** | **620** | **~240** | **−380** |

---

## Hooks

### 1. `session-start` — remove memory instructions

**Problem:** Injects `Then: mcp__serena__list_memories() and read relevant memories.` after the activate_project line.  
**Fix:** Remove that block. Keep project detection and activate_project instruction only.

### 2. `post-cbm-read-record.sh` — replace JSON log with flag file

**Problem:** Read-modify-write on a growing JSON array on every CBM call. Memory leak. Unnecessary complexity.  
**Fix:** Replace with `touch "${SESSION_DIR}/cbm-used"`. File existence = CBM was used this session. No content needed.

Session dir: `${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/${CLAUDE_SESSION_ID:-default}/`

### 3. `pre-serena-read-guard.sh` — fix output format + add throttle

**Problem 1:** Warning goes to stderr. Pilot pattern: hints go to stdout as `additionalContext` JSON so Claude actually receives them as context.  
**Problem 2:** No throttle — can spam every Serena read call in a session.  
**Problem 3:** Reads full JSON log (replaced by flag file in fix #2).

**Fix:**
- Output to stdout: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"<msg>"}}`; exit 0 (non-blocking)
- Add timestamp throttle: write `${SESSION_DIR}/serena-read-warned-ts` on first warn; skip if file exists and is < 300s old
- Check `${SESSION_DIR}/cbm-used` flag file instead of JSON log

### 4. `post-serena-refs` + `pre-serena-edit-guard.sh` — fix state dir + path bug (AP-55)

**Problem A (AP-55):** `post-serena-refs` writes state to `${CLAUDE_PLUGIN_ROOT}/state/` — this directory is wiped on every plugin update. All traced-refs state is lost on upgrade.  
**Problem B:** `post-serena-refs` writes `refs-traced.json` but `pre-serena-edit-guard.sh` reads `refs-traced.${SESSION_ID}.json` — paths never match → guard always fires.  
**Problem C:** `pre-serena-edit-guard.sh` wraps its deny in `hookSpecificOutput` — deny must be top-level `{"permissionDecision":"deny","permissionDecisionReason":"..."}` per hook-patterns.md (AP-16).

**Fix:**
- Both hooks: use `STATE_DIR="${CLAUDE_PLUGIN_DATA:-${HOME}/.claude/plugin-data/orca-env-plugin}/state"`
- `post-serena-refs`: write `refs-traced.json` (no session ID — already correct filename)
- `pre-serena-edit-guard.sh`: read `refs-traced.json` (drop `${SESSION_ID}` suffix)
- `pre-serena-edit-guard.sh`: return `{"permissionDecision":"deny","permissionDecisionReason":"..."}` + exit 2 at top level (no `hookSpecificOutput` wrapper)

### 5. `skill-activation-prompt` — wrap output in additionalContext JSON

**Problem:** Outputs plain text to stdout. Claude Code expects `additionalContext` JSON for UserPromptSubmit hooks.  
**Fix:** Wrap final output in `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<msg>"}}`.

### 6. `hooks.json` — wire PostToolBatch audit (AP-51)

**Problem:** `post-batch-audit.sh` exists and catches routing escapes, but `PostToolBatch` is not in `hooks.json` anywhere. The audit is silently not running (AP-51: no PostToolBatch audit = escapes invisible).  
**Fix:** Add `PostToolBatch` entry to `hooks.json`:
```json
"PostToolBatch": [
  { "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/post-batch-audit.sh'", "timeout": 10 }] }
]
```

### 7. `session-start-compact` — remove any memory refs, align with new skill content

**Problem:** Minor — check for stale memory-related content.  
**Fix:** Audit and remove any `list_memories` / `read_memory` references. Content already uses compact `<tool_routing>` format — keep that pattern.

---

## Out of scope

- Hook logic (routing decisions, edit guard protocol) — not changing
- `pre-tool-router`, `rtk-rewrite-bash`, `post-batch-audit.sh`, `stop.js`, `subagent-stop.js` — working, untouched
- Python rewrite of any hook
- New hooks or new skills
- `rules/` directory (would require hook changes to load)

---

## Verification

After implementation:

```bash
cd ~/src/orca-env-plugin
bun run tests/run-all.sh           # all unit tests pass
bash tests/unit/test-hooks-smoke.sh  # hooks smoke
bash tests/unit/test-serena-guard.sh  # edit guard fix verified
```

Manual checks:
- `pre-serena-edit-guard.sh`: call `post-serena-refs` with a fixture, then confirm guard allows the same path
- `pre-serena-read-guard.sh`: confirm hint appears in stdout as valid JSON with `additionalContext` key
- `skill-activation-prompt`: confirm stdout is valid JSON with `additionalContext` key
