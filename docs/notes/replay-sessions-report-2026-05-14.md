# Session Replay Stats — 2026-05-14

Scans every Claude Code session transcript under `~/.claude/projects/**/*.jsonl` and counts routing policy outcomes per session. Companion to `replay-fixtures-report-2026-05-14.md` (which is fixture-driven).

Runner: `tests/e2e/replay-sessions.sh`

## Definitions

For every `tool_use` recorded in a transcript:

| Bucket | Meaning |
|---|---|
| **cbm_reads (PASS)** | `mcp__codebase-memory-mcp__*` — correct routing for code reads |
| **serena_reads (BYPASS)** | `mcp__serena__{find_symbol,get_symbols_overview,search_for_pattern,read_file,list_dir,find_file}` — should have been CBM |
| **serena_edits (OK)** | `mcp__serena__{replace_*,insert_*,rename,safe_delete,find_referencing,activate,*_memory,initial_instructions}` — allowed |
| **native_on_code (BYPASS)** | `Read/Edit/Write/Grep/Glob` against `.py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java` — should be hard-blocked |
| **denied** | Matching `tool_result.is_error == true` whose text matches `denied/blocked/permission/not allowed` — hook stopped the call |

`pass_rate = cbm / (cbm + serena_reads + native_on_code)`
`bypass_rate = (serena_reads + native_on_code) / same denominator`

## Aggregate (all-time, 1857 transcripts scanned)

| metric | value |
|---|---|
| transcripts scanned | 1857 |
| active sessions (≥1 tool_use) | 903 |
| total tool_uses | 28,729 |
| cbm_reads (PASS) | 3,476 |
| serena_reads (BYPASS) | 1,988 |
| serena_edits (OK) | 1,237 |
| native_on_code (BYPASS) | 1,686 |
| denied | 428 |
| **pass_rate** | **48.62 %** |
| **bypass_rate** | **51.38 %** |

Half of all code-read traffic across the historical corpus took a non-CBM path. ~6 % of attempted tool calls were hook-denied.

## Per-project rollup

| project (path under `~/.claude/projects/`) | sess | cbm | serena_R | serena_E | native_C | deny |
|---|---:|---:|---:|---:|---:|---:|
| `-Users-ilyabrykau-src`                              | 777 | 3385 | 1988 | 1237 | 1595 | 414 |
| `-Users-ilyabrykau--claude-mem-observer-sessions`     | 94  | 0    | 0    | 0    | 0    | 7   |
| `-Users-ilyabrykau-src-orca-env-plugin`               | 14  | 8    | 0    | 0    | 9    | 0   |
| `-Users-ilyabrykau-src-orca-runtime-sensor`           | 7   | 83   | 0    | 0    | 72   | 3   |
| `-Users-ilyabrykau`                                   | 5   | 0    | 0    | 0    | 9    | 1   |
| `-Users-ilyabrykau--claude-plugins-cache-…-compress`  | 3   | 0    | 0    | 0    | 0    | 3   |
| `-Users-ilyabrykau-Downloads`                         | 1   | 0    | 0    | 0    | 0    | 0   |
| `-Users-ilyabrykau--claude`                           | 1   | 0    | 0    | 0    | 0    | 0   |
| `-private-tmp-claude-toolkit-test`                    | 1   | 0    | 0    | 0    | 1    | 0   |

The unified workspace `~/src` dominates (84 % of active sessions). All Serena-read bypasses (1988) come from it — expected, since per-repo workspaces don't activate the `cbm-workflow` skill with the same project routing.

`orca-runtime-sensor` shows the per-repo pattern: high CBM use (83) but also 72 native-on-code calls — likely Read of `.go` files for context lookup before plugin guardrails were tight.

## Top-25 bypass sessions

(see full output of `bash tests/e2e/replay-sessions.sh --top 25 --jobs 8` — sorted by `serena_R + native_C` desc)

| total | cbm | ser_R | ser_E | nat_C | deny | session |
|---:|---:|---:|---:|---:|---:|---|
| 411 | 0   | 0   | 0   | 145 | 0 | `-Users-ilyabrykau-src/41cdaf76…` |
| 208 | 1   | 132 | 75  | 0   | 0 | `…/450bc458/subagents/ab7acd34…` |
| 443 | 54  | 119 | 27  | 4   | 0 | `…/b69a6130-4219-4a4c-a110…` |
| 120 | 3   | 84  | 28  | 0   | 0 | `…/450bc458/subagents/a9e50842…` |
| 157 | 1   | 0   | 1   | 74  | 1 | `…/66d800bd-4e25-43c2-aa3e…` |
| 81  | 2   | 66  | 13  | 0   | 0 | `…/450bc458/subagents/a12098…` |
| 98  | 0   | 52  | 0   | 12  | 0 | `…/5cb1612e/subagents/a18aabf4…` |
| 234 | 0   | 0   | 0   | 63  | 1 | `…/39c9328b-bfff-42c5-86bb…` |
| 263 | 0   | 0   | 0   | 53  | 3 | `…/7e3d095e-d061-495a-b84f…` |
| 199 | 2   | 43  | 15  | 6   | 1 | `…/bb4a2de5-2041-4fce-af5f…` |
| 150 | 45  | 16  | 11  | 31  | 7 | `…/e78bcf80-db76-4e3c-bacb…` |
| 141 | 14  | 24  | 11  | 12  | 8 | `…/ca55254c-ba10-4e3f-8e64…` |

The top entries fall into two shapes:
1. **Subagent sessions under `450bc458`** — Serena-read heavy (132/84/66), zero native — looks like an agent batch that never invoked CBM at all. Worth investigating whether the spawner injected the routing context.
2. **Standalone sessions** with 50–145 native-on-code calls — pre-plugin era or sessions launched outside the plugin's `SessionStart` hook.

## How to reproduce

```bash
# all sessions
bash tests/e2e/replay-sessions.sh --jobs 8

# only sessions since a date
bash tests/e2e/replay-sessions.sh --since 2026-05-01 --jobs 8

# top-N offenders only
bash tests/e2e/replay-sessions.sh --top 25 --jobs 8
```

Runtime: ~5 seconds for 1857 transcripts at `--jobs 8` on this machine.

## Caveats

- `denied` counter matches any `is_error` tool_result whose payload mentions deny/block/permission — includes both hook-injected denies and unrelated tool errors. Likely overcounts. To tighten, parse the specific stderr format from `pre-tool-router` / `pre-serena-edit-guard.sh`.
- Per-session subagent files are counted separately — a parent + 5 subagents = 6 rows. The unified `-Users-ilyabrykau-src` total already reflects this.
- `bypass_rate` excludes denies from the denominator. A denied Serena call counts neither as PASS nor BYPASS — it's a third outcome. Adding `denied` to the denominator drops bypass_rate to ~50.5 %.

## Time-window comparison

Plugin v7.0.0 shipped 2026-04-29 (`1709289 feat: orca-env-plugin v7.0.0 — v1 pedagogy + v6 safety net`). CBM empty-fallback prevention shipped 2026-04-30 (`539cc25`).

| window | sess | tool_uses | cbm | ser_R | nat_C | denied | pass_rate | bypass_rate |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all-time | 903 | 28,729 | 3,476 | 1,988 | 1,686 | 428 | 48.62 % | 51.38 % |
| since 2026-04-29 (post-v7) | 225 | 7,597 | 1,405 | 300 | 383 | 109 | **67.29 %** | 32.71 % |
| since 2026-05-07 (7d) | 139 | 4,091 | 807 | 72 | 306 | 63 | **68.10 %** | 31.90 % |

**Serena-read bypass collapsed**: 1,988 → 300 → 72 across the three windows. The `pre-serena-read-guard.sh` + slim `cbm-workflow` skill is doing its job.

**Native-on-code remains the dominant residual bypass**: 306 of 378 bypasses in the last week. Next investigation target: are these calls reaching the `pre-tool-router` guard and being denied (counted in `denied=63`), or slipping past it? Correlating `native_on_code` `tool_use` IDs against `is_error` tool_results would answer this.

## Suggested follow-ups

1. Correlate native_on_code tool_use IDs to tool_results to split into `native_DENIED` vs `native_SLIPPED`.
2. Tighten the denied detector to match exact hook stderr strings.
3. Add a `--csv` flag for downstream analysis.
4. Wire the runner into `tests/run-all.sh --integration` as a baseline drift check (warn if 7-day pass_rate drops below 65 %).
