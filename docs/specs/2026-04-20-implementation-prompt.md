# Implementation Prompt — Infinite Regression TDD Loop

Copy everything below the `---` into a fresh Claude Code session at `~/src/orca-env-plugin`.

---

ultrathink

## Execute: Infinite Regression TDD — v2.4.0

Use `superpowers:subagent-driven-development` to execute plan at `docs/specs/2026-04-20-infinite-regression-tdd-plan.md`. Read it fully before starting.

### Context

`orca-env-plugin` = Claude Code plugin. Compiled Bun binary at `dist/claude-toolkit`. PreToolUse hook intercepts Bash/Read/Edit/Write/Grep/Glob → enforces CBM + Serena for source code under `~/src/`.

Current state:
- 544 pass, 14 pre-existing fail
- v2.3.0 just shipped: blocklist → universal path scan (`bashHasSourcePath`)
- `CLAUDE_RAW=1` bypass still exists (to be removed)
- RTK rewrite is best-effort (to become mandatory for simple cmds)

### Tool Routing (CRITICAL)

- **Code search/read**: `mcp__codebase-memory-mcp__search_code`, `get_code_snippet` (project = `Users-ilyabrykau-src-orca-env-plugin`)
- **Code edit**: Serena (`replace_symbol_body`, `replace_content`, `insert_after_symbol`)
- **Patching .ts files**: `bun -e '...'` via Bash (hooks block native Read/Edit on source under `~/src/`)
- **Docs/config/fixtures**: native Read/Edit/Write (allowed — non-source extensions)
- **Build**: `bun run build`
- **Test**: `bun test` or `bun test tests/<file>.test.ts`
- **NEVER**: native Read/Edit/Grep on `.ts`/`.go`/`.py` files under `~/src/`

### Plan Summary (6 tasks)

1. **Remove `CLAUDE_RAW=1` bypass + RTK-fail deny** — patch `src/hot/pre-tool-use.ts`, add `DENY_RTK` constant, RTK exit non-0 → deny. Write tests first (TDD).
2. **Fix 14 pre-existing test failures** — update `tests/plugin-structure.test.ts` (hooks.json events, agents), gut `tests/prompt-submit.test.ts` (no handler exists), fix routing strings in `tests/integration-sequences.test.ts` + `tests/e2e-session.test.ts` + `tests/lifecycle.test.ts`.
3. **Mining pipeline** — create `scripts/mine-regression-corpus.ts`. Read `~/.claude/projects/*/*.jsonl` (transcripts), `tests/fixtures/bash-violation-corpus.txt`, `~/.claude/logs/hooks.jsonl`. Extract tool calls, dedup, classify via binary, output `tests/fixtures/regression-corpus.json`.
4. **Regression test suite** — create `tests/regression-deterministic.test.ts`. Load corpus.json, `test.each` by expected outcome (deny-explore, deny-edit, deny-rtk, allow-rtk, allow-passthrough).
5. **`/loop` stability guard** — `/loop 5m bun test` with subagent auto-fix + `mcp__pal__consensus` gate.
6. **Final verify + v2.4.0 commit**.

### Subagent Rules

- One subagent per task
- TDD: write failing test → verify fail → implement → verify pass → commit
- All `.ts` patches via `bun -e '...'` (hooks block direct file access)
- `bun run build` after every source change
- `bun test` after every step — 0 regressions
- Commit after each task with conventional commits
- Review subagent output between tasks before proceeding

### Success Criteria

- [ ] 0 test failures (`bun test`)
- [ ] No `CLAUDE_RAW=1` bypass in handler
- [ ] Every simple Bash cmd → RTK rewrite or deny
- [ ] `regression-corpus.json` with 100+ entries from mined history
- [ ] All corpus entries → deterministic pass
- [ ] `/loop 5m bun test` active
