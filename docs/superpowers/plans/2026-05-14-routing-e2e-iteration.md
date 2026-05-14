# Plan: e2e-driven routing iteration

**Hand-off prompt for a fresh Claude Code session. Paste from `## START PROMPT` onward.**

---

## START PROMPT

You are picking up routing work on `orca-env-plugin` from a previous session. The plugin is currently **disabled** in user settings on purpose. The goal is **NOT** to re-enable it — the goal is to make Claude pick the right tools *intrinsically* via instructions, with zero hook dependency. Denies are a sign of failure (model already decided wrong); 0 denies + 0 native-on-code = success.

### Repo

- Cwd: `~/src/orca-env-plugin`
- Branch: `feat/skills-refinement-2026-05` (3 commits ahead of main: `82a36bd`, `d1e53dc`, `3c30ba1`)
- Do not commit on `main`. Stay on the feature branch. Ask before any destructive git op.

### Current state

- `~/.claude/settings.json.enabledPlugins["orca-env-plugin@Orca-Env-Plugin-Marketplace"] = false` (user decision, leave it).
- `~/.claude/CLAUDE.md` includes `@~/.claude/ROUTING.md` (43-line routing rules).
- `~/.claude/ROUTING.md` lives at user level. Template copy in repo: `docs/examples-ROUTING.md`.
- Subagent sanity check (no caveman, fresh context) on task "find UpdatePaths + callers in orca-runtime-sensor": VERDICT PASS, 9 MCP tool calls, 0 native on code.

That sanity check is NOT enough — subagents inherit the parent session's CLAUDE.md auto-load, share the same MCP servers, and don't pay the cold-context cost a real `claude` CLI invocation pays. You need real e2e.

### Goal (success criteria — all must hold)

Across a representative task suite run via the real `claude` CLI, in fresh sessions, with the plugin still disabled:

1. native_code on `.py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java` PASS count = **0**.
2. cbm_read PASS count > 0 on every code-related task.
3. No deny markers in transcripts (because deny = retry waste; the model should not get blocked at all).
4. Task answer quality remains intact — model still completes the task, just with MCP tools.
5. Friction is low: median ≤ 3 tool calls before the model returns the answer for simple questions like "show me function X" or "who calls Y".

### What "complete" looks like

A markdown report at `docs/notes/routing-e2e-report-<date>.md` with:
- A table: task × tool-choice trace × verdict (PASS / FAIL).
- For each FAIL: a specific ROUTING.md patch hypothesis.
- After the final iteration: all rows PASS, friction metric reported.

### Tooling already in place

| path | purpose |
|---|---|
| `tests/e2e/run-e2e.sh` | matrix runner, gated by `E2E=1`; runs files under `tests/e2e/matrix/` |
| `tests/e2e/lib/launch-session.sh` | invokes the real `claude` CLI (`launch_session prompt cwd turns timeout`) |
| `tests/e2e/lib/assert-routing.sh` | the 4 routing assertions (`assert_no_native_on_code`, `assert_cbm_dominates_reads`, `assert_serena_only_for_edits`, `assert_cbm_retries_on_empty`) |
| `tests/e2e/matrix/*.sh` | existing matrix tasks (best-of-3 scoring) — use as a template |
| `tests/e2e/replay-deep.sh` | offline transcript classifier (DENIED/SLIPPED/ERROR/PASS) — verify each new e2e run with this |
| `tests/e2e/replay-fixtures.sh` | offline replay against `tests/e2e/fixtures/*.json` |

Run real e2e with `E2E=1 bash tests/e2e/run-e2e.sh`. Each matrix script invokes one or more live `claude` runs and produces a transcript under `tests/e2e/results/`.

### Suggested task suite (extract from real failure data)

The top W20 native-bypass sessions in orca cwds (from `/tmp/deep-all.tsv` if still present, else re-generate via `bash tests/e2e/replay-deep.sh --tsv > /tmp/deep-all.tsv`):

1. `66d800bd…` — 74 native bypasses
2. `7e3d095e…` — 47
3. `7a2867ae…` — 43
4. `0eff2b68…` — 34
5. `e78bcf80…` — 23

For each, extract the actual user prompt from the jsonl (first non-system message) and the first native-on-code tool call. Build a matrix test that re-issues that prompt and asserts MCP-only tool use. Six to eight task patterns will cover the common cases:

- "Read function X in file Y" → expect `mcp__codebase-memory-mcp__get_code_snippet` or `mcp__serena__find_symbol`.
- "Find all callers of X" → expect `mcp__serena__find_referencing_symbols` or `mcp__codebase-memory-mcp__trace_path`.
- "Edit function X to do Y" → expect `mcp__serena__find_referencing_symbols` first, then `mcp__serena__replace_symbol_body`.
- "Search the repo for pattern P" → expect `mcp__codebase-memory-mcp__search_code`.
- "Show me the architecture / layout" → expect `mcp__codebase-memory-mcp__get_architecture`.
- "List Go files in pkg/" → expect `mcp__serena__find_file` or `Glob` on the directory level (acceptable; Glob is only banned on code suffix).
- "Refactor / rename symbol S" → expect `mcp__serena__rename_symbol`.

### Iteration loop

```
for iter in 1..N:
  E2E=1 bash tests/e2e/matrix/routing-suite.sh   # new file you write
  bash tests/e2e/replay-fixtures.sh              # offline regression
  if all PASS: break
  identify failure modes, patch ~/.claude/ROUTING.md
  optionally patch tests/e2e/fixtures/*.json with the new trace as a regression fixture
  commit each patch with a clear message
```

The iteration ends when every task PASSes without ROUTING.md being patched further.

### Constraints

- Do **not** re-enable the plugin to "make tests pass". The whole point is plugin-off.
- Do **not** edit per-repo `CLAUDE.md` / `AGENTS.md` in the orca-* repos — those are team-shared. Routing rules live in `~/.claude/ROUTING.md` only.
- Do **not** add deny-style hooks. If the model needs hand-holding, it goes in `~/.claude/ROUTING.md`, not in a blocking hook.
- Commit each ROUTING.md change in `docs/examples-ROUTING.md` separately so changes are reviewable.
- `~/.claude/ROUTING.md` and `~/.claude/CLAUDE.md` are user-personal — copy the *content* into `docs/examples-ROUTING.md` for the repo, do not commit the user-personal file paths themselves.
- If you reach 5 iterations without convergence, stop and write a report explaining why.

### Where to start

1. `git log --oneline -5` on `feat/skills-refinement-2026-05` to confirm state.
2. `cat ~/.claude/ROUTING.md` — internalize current rules.
3. Read `tests/e2e/matrix/cbm-empty-fallback.sh` to understand the pattern.
4. Re-generate `/tmp/deep-all.tsv` if not present.
5. Extract real prompts from the 5 sessions listed above.
6. Write `tests/e2e/matrix/routing-suite.sh` (one matrix entry per task, best-of-3 like the others).
7. Run, score, patch, repeat.

### Tools you should default to in your own work this session

When you yourself need to read repo code while doing this work: CBM > Serena > native (last resort). The same rules apply to you that you're testing on simulated Claude.

## END PROMPT
