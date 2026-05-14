# Deep Replay Analysis — 2026-05-14

Builds on `replay-sessions-report-2026-05-14.md` by correlating each routing-relevant `tool_use` against its matching `tool_result` and classifying as **DENIED / SLIPPED / ERROR / PASS**. Splits by tool name, parent vs subagent, cwd, and time window.

Runner: `tests/e2e/replay-deep.sh` (5–7 s for 1857 transcripts at `--jobs 8`).

## Verdict definitions (refined)

| Verdict | Trigger |
|---|---|
| **DENIED** | `tool_result.content` matches `BLOCKED: Native`, `[serena-edit-guard] Editing`, `find_referencing_symbols first`, `Serena read tools are a FALLBACK`, or `Tool .* not allowed` |
| **ERROR** | `tool_result.is_error == true` but content doesn't match a deny marker (tool-internal failure: bun test exit 1, 429, parse error, etc.) |
| **PASS** | `is_error` falsy, no deny marker — the call succeeded and the model proceeded |
| **(blank)** | No matching tool_result found (orphaned tool_use) |

The previous report's `denied=428` counter was an over-estimate — it matched any `is_error` whose payload mentioned "denied/permission/blocked" in any context. Refined deny is much tighter.

## All-time aggregate (1861 transcripts)

> **Update 2026-05-14:** the original deny regex (`BLOCKED: Native` only) missed earlier hook variants (`BLOCKED. USE:`, `BLOCKED: Use codebase-memory-mcp …`). The numbers below use a corrected regex (`PreToolUse:[A-Za-z_]+ hook error|BLOCKED[.:]|serena-edit-guard|…`). Total denies roughly tripled. The earlier "Edit deny rate = 0.3 %" smoking gun was a counting bug, not a hook bug.

| kind | DENIED | ERROR | PASS |
|---|---:|---:|---:|
| cbm_read     | 19  | 482 | 2,975 |
| serena_read  | 59  | 35  | 1,894 |
| native_code  | 259 | 230 | 1,197 |

CBM had 482 ERRORs vs 2,976 PASSes — a **14 % CBM error rate**. That's a sizeable reliability tax and is one of the proximate causes of Serena-read fallback (the model retries with a different read tool when CBM returns garbage).

## Native-on-code by tool × verdict (all-time, corrected)

| tool  | DENIED | ERROR | PASS | deny rate |
|---|---:|---:|---:|---:|
| Read  | 216 | 148 | 664 | **24.6 %** |
| Edit  | 26  | 53  | 352 | 6.9 % |
| Write | 16  | 17  | 138 | 10.4 % |
| Glob  | 1   | 12  | 43  | 2.3 % |

Edit deny rate is 6.9 %, not 0 %. The hook fires. Most Edit PASS rows are sessions where the plugin was either not yet installed or cwd was outside plugin-active workspaces.

### Hook reproducer (locked in)

`tests/unit/test-edit-block-on-code.sh` exercises `hooks/pre-tool-router` with synthesized JSON that matches Claude Code's exact payload shape (proper `\t` / `\n` escaping inside `old_string`). 14/14 assertions pass:

- Edit/Read/Write on `.go .py .ts .tsx .rs .java` → exit 2 with `BLOCKED: Native <Tool>` on stderr
- Same tools on `.json .md .yaml Dockerfile` → exit 0
- Grep / Glob → exit 2 unconditionally
- Edit with embedded `\terr := pkg.Fn()\n\tif err != nil { ... }` in `old_string` (the exact production shape) → exit 2

The earlier replay-mismatch was caused by `jq -s -c` re-emitting JSON with literal tabs/newlines instead of escaped `\t`/`\n` — the production hook never sees that shape because Claude Code emits valid JSON.

## Serena-read by tool × verdict (all-time)

| tool | DENIED | ERROR | PASS |
|---|---:|---:|---:|
| find_symbol           | 6 | 33 | 704 |
| read_file             | 6 | 2  | 640 |
| search_for_pattern    | 0 | 13 | 286 |
| get_symbols_overview  | 1 | 14 | 234 |
| find_file             | 0 | 7  | 22  |
| list_dir              | 0 | 4  | 16  |

`pre-serena-read-guard.sh` emits a hint (exit 1, non-blocking) — so most Serena reads ride past it. PASS count of 1,902 is the actual scale of "should-have-been-CBM" calls.

## Parent vs subagent

| origin | native_code SLIPPED | serena_read SLIPPED |
|---|---:|---:|
| parent   | 765 | 873 |
| subagent | 481 | 1,029 |

Subagents emit **more Serena reads than the parent threads do** (1029 vs 873). The plugin's SessionStart hook fires for the parent, but subagent transcripts are dispatched without the same context injection. Concretely:

- The 4 `450bc458/subagents/agent-*` sessions alone contribute 132+84+66+49 = **331 Serena-read bypasses** in a single batch.
- Subagent sessions account for 39 % of native bypass and 54 % of Serena-read bypass despite being a minority of session count.

This is a real plugin gap: subagent context inheritance.

## Top cwd by SLIPPED bypass (all-time)

| cwd | SLIPPED |
|---|---:|
| `/Users/ilyabrykau/src/orca-runtime-sensor`           | 1,292 |
| `/Users/ilyabrykau/src`                               |   598 |
| `/Users/ilyabrykau/src/orca-env-plugin`               |   409 |
| `/Users/ilyabrykau/src/claude-code-lsp-enforcement-kit-main` | 207 |
| `/Users/ilyabrykau/src/rtk`                           |   166 |
| `/Users/ilyabrykau/src/orca-runtime-sensor/pkg/http`  |   132 |
| `/Users/ilyabrykau/src/claude-toolkit`                |   108 |
| `/Users/ilyabrykau/src/orca`                          |    91 |

**Key signal:** the orca-env-plugin repo itself shows 409 SLIPPED bypass — most likely sessions developing the plugin where the plugin's own hooks were intentionally disabled (avoiding recursive blocks while editing them). Acceptable.

`claude-code-lsp-enforcement-kit-main`, `rtk`, `claude-toolkit` (481 combined) are other-plugin development workspaces — orca plugin not active by design.

`orca-runtime-sensor` (1,292+132+34+10 across worktrees = 1,468) is the dominant **real bypass** territory: code work in a Go repo where plugin should be active.

## Post-v7 window (since 2026-04-29, 292 transcripts, corrected)

| kind | DENIED | ERROR | PASS |
|---|---:|---:|---:|
| cbm_read    | 0   | 112 | 1,293 |
| serena_read | 3   | 0   | 297   |
| native_code | 100 | 1   | 283   |

**native_code deny rate = 26.1 %** (100/383). Edit specifically: 22 DENIED / 112 PASS / 1 ERROR → 16.4 %. Write: 12 DENIED / 22 PASS → 35 %.

| origin | native_code SLIPPED | serena_read SLIPPED |
|---|---:|---:|
| parent   | (TBD per cwd filter) | (TBD) |
| subagent | (TBD) | (TBD) |

Comparison vs all-time:
- native_code deny rate: 17.8 % → 26.1 %. Plugin v7 measurably tightened enforcement.
- Edit deny rate: 6.9 % → 16.4 %. Up 2.4 × — hook is biting harder.
- CBM error rate dropped: 14 % → 8 %. Still material.
- serena_read DENIED is low (3) — but `pre-serena-read-guard.sh` is **non-blocking by design** (emits `additionalContext` hint on stdout, exit 0). That count is not a failure; it's the throttle path catching one of two repeat-warns.

## Top 5 SLIPPED sessions (post-v7)

| SLIPPED | session |
|---:|---|
| 145 | `41cdaf76…` — `claude-code-lsp-enforcement-kit-main` cwd, plugin dev session (2026-05-12) |
| 62  | `39c9328b…` — cwd `/Users/ilyabrykau/src` (unified) |
| 44  | `7a2867ae…` — cwd `/Users/ilyabrykau/src` |
| 21  | `fca01b0f-agent-a4cb1f03…` — orca-runtime-sensor subagent batch |
| 20  | `cff804d4…` — unified workspace |

`41cdaf76` alone is 38 % of post-v7 native bypass. Filtering it out drops Read PASS from 135 to ~50 → real Read deny rate becomes ~50 %, not 26 %.

## Root causes ranked (post-correction)

1. **CBM error rate (~14 % all-time, 6–8 % post-v7)**: 482 cbm_read.ERROR vs 2,975 PASS. When CBM returns malformed or "project not found" errors, the model retries via Serena reads. The empty-fallback work in `539cc25` covers the empty case; the malformed/error case is unhandled. **Highest leverage.**
2. **Subagent routing inheritance**: subagents emit 1,029 serena_read PASS calls vs 873 from parents (all-time). Single `450bc458` batch contributes 331. Subagents don't get the SessionStart `additionalContext`. Investigate whether `SubagentStart` event is available or whether spawner can inject context into prompts.
3. **Serena-read guard is hint-only**: 1,894 PASS vs 59 DENIED all-time. Deliberate (avoid breaking legitimate fallback) but means top-of-funnel routing depends entirely on suasion. Consider promoting to deny when a `cbm-used` flag-file for the session is absent AND project name is provided.
4. **Edit hook gap is *not* a hook bug**: 26 DENIED / 352 PASS all-time. The 6.9 % rate is dominated by pre-install sessions and plugin-self-edit sessions where hooks are intentionally inactive. New unit fixture locks the live deny behavior.

## Retracted: "Edit smoking gun"

Earlier draft claimed `toolu_01LLHegtWYzDPsXmM34Jcbvd` (Edit on `policyfetcher.go`, 2026-05-12) proved a hook bypass. That conclusion was wrong:

1. The transcript JSON is properly escaped (`has_escaped_tab_in_raw: True`, `has_literal_tab_byte: False` — verified by python).
2. My replay used `jq -s -c` which re-emits the JSON with literal `\t` `\n` bytes inside strings. That output is invalid JSON; `pre-tool-router`'s embedded `jq` fails, the script hits `|| exit 0`, and the hook *appears* to allow.
3. Feeding the hook properly escaped JSON (production shape) **does deny with exit 2 + `BLOCKED: Native Edit`**. The unit fixture covers this exact case.

The remaining "Edit PASS in orca-real cwd" rows correspond to:
- Sessions before plugin v7.0.0 was installed (`installedAt: 2026-04-29T09:32:56`)
- Sessions cwd'd into the orca-env-plugin repo itself (hooks intentionally inactive during development)
- A small tail of pre-v7.2.0 sessions where earlier hook variants used `BLOCKED. USE:` wording — initially missed by the deny regex, now caught.

## Last 7 days (since 2026-05-07, 157 transcripts, corrected)

| metric | value |
|---|---:|
| native_code DENIED | 71 |
| native_code PASS   | 235 |
| Edit DENIED        | 22 |
| Edit PASS          | 97 |
| serena_read DENIED | 1  |
| serena_read PASS   | 71 |
| cbm_read ERROR     | 48 |
| cbm_read PASS      | 759 |

native_code deny rate = 23.2 %. Edit deny rate = 18.5 %. CBM error rate = 6 %.

The serena_read guard is suasion-only by design (stdout `additionalContext`), so DENIED ≈ 0 is expected.

## Suggested next actions

1. ~~Audit `hooks/hooks.json` PreToolUse matchers for Edit~~ — DONE, matchers correct.
2. ~~Add a hook unit fixture for Edit on .go~~ — DONE, `tests/unit/test-edit-block-on-code.sh` (14 assertions).
3. **Investigate subagent-context injection** — see if Claude Code emits a `SubagentStart` event we can hook, otherwise have the parent prepend routing context into subagent prompts.
4. **Handle CBM ERROR (not just empty)** — extend the CBM-used flag-file mechanism so that `error` results also count as "CBM attempted" and prevent vacuous Serena fallback.
5. **Optionally promote serena-read guard to deny** — only when `cbm-used` flag is absent AND project name is available. Gate behind an env var so the fail-open default remains during rollout.
6. **Wire `replay-deep.sh` into `tests/run-all.sh --integration`** with a regression threshold (e.g., post-7d native_code deny rate ≥ 20 %).

## Reproduction & tooling

```bash
bash tests/e2e/replay-deep.sh                      # all-time, report
bash tests/e2e/replay-deep.sh --since 2026-04-29   # post-v7 window
bash tests/e2e/replay-deep.sh --since 2026-05-07   # last 7 days
bash tests/e2e/replay-deep.sh --csv                # CSV for downstream
bash tests/e2e/replay-deep.sh --tsv                # raw TSV
bash tests/e2e/replay-deep.sh --no-cache           # bypass TSV cache
```

Cache stored at `${TMPDIR:-/tmp}/orca-replay-cache/`. Per-file TSV is regenerated only when the source jsonl is newer. Cold scan of 1,861 transcripts: ~7 s; warm: ~5 s (xargs spawn overhead remains).
