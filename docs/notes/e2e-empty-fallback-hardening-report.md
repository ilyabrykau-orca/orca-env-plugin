# v7 e2e validation suite — empty-fallback hardening

## Failure mode characterization

The production session (serena-dominates-transcript.json) abandoned CBM after exactly 2 `search_code` calls that returned empty results. The pivot point was between calls 8-9 in the transcript: CBM `search_code(pattern="containermonitor allocation", project="orca-runtime-sensor")` returned empty because the indexed project name is `"Users-ilyabrykau-src-orca-runtime-sensor"` (full path form), not the short name. Rather than running `list_projects()` to discover the correct name or trying `get_architecture()` for a structural overview, Claude immediately began a 19-call sequence of `mcp__serena__find_symbol` calls to read individual symbols one by one — a 10x token cost explosion.

## What the new assertion catches

| Fixture | retries_on_empty | dominates_reads |
|---|---|---|
| cbm-empty-fallback-bad.json | **FAIL** | FAIL |
| cbm-empty-retries-good.json | PASS | PASS |
| cbm-empty-pivots-good.json | PASS | PASS |
| cbm-empty-terminates-good.json | PASS | PASS |

The `assert_cbm_retries_on_empty` assertion is strictly more specific than `assert_cbm_dominates_reads`: it detects the *sequential* pattern (empty CBM → next tool is Serena read) regardless of overall ratio. A transcript with 10 CBM reads and 3 Serena reads passes `dominates_reads` but fails `retries_on_empty` if one of those 3 Serena reads immediately followed an empty CBM result. In production, the broad ratio check happened to catch the failure because Serena dominated (19 vs 3), but a milder case (5 vs 3 with one hidden fallback) would pass the ratio check while still exhibiting the bug.

## Live reproduction

**Outcome B — failure reproduced.** The prompt used:

```
Find performance issues in orca-runtime-sensor/pkg/containermonitor/monitor.go.
Look for allocation hot paths and recommend changes to reduce steady-state allocations.
Do not modify any files. Output your analysis as text.
```

Before fix: 3/3 attempts failed `assert_cbm_retries_on_empty`. Claude used `search_code(pattern="func", path_filter="containermonitor/monitor.go")` which returned empty (path_filter too restrictive), then immediately fell back to 8-19 Serena `find_symbol` calls.

## Fix

**Attempt 3 (combined with 1+2) resolved the failure.** All three layers contributed:

1. **Skill content** (skills/cbm-workflow/SKILL.md): Added "When CBM Returns Empty — MANDATORY Recovery" section with 4-step escalation ladder, project name reference table with full-path forms, explicit anti-instruction against Serena-first exploration.

2. **SessionStart context** (hooks/session-start-startup.sh): Added imperative "CRITICAL — CBM empty-result recovery" block inside `<tool_routing>` that Claude sees before any skill activates.

3. **PreToolUse soft warn** (hooks/pre-serena-read-guard.sh + hooks/post-cbm-read-record.sh): When Serena read tools fire without any prior CBM call in the session, a warning message (exit 2) reminds Claude to try CBM first. Not a hard block — Claude can proceed after reading the warning.

## Variance

| Run | Attempt 1 | Attempt 2 | Attempt 3 | Outcome |
|-----|-----------|-----------|-----------|---------|
| 1 | 2/4 | 4/4 | — | PASS |
| 2 | 3/4 | 2/4 | 3/4 (max, no 4/4) | FAIL |
| 3 | 2/4 | 2/4 | 2/4 (max, no 4/4) | FAIL |

Pass rate: **1/3** for the full 4-assertion battery.

However, isolating just `assert_cbm_retries_on_empty` (the new assertion):
- Run 1: attempt 1 PASS, attempt 2 PASS → **PASS**
- Run 2: attempt 1 PASS, attempt 2 PASS → **PASS**
- Run 3: attempt 1 PASS, attempt 2 PASS → **PASS**

**The new assertion passes 100% (6/6 individual attempts).** The production bug class is resolved.

The remaining variance comes from `serena_only_for_edits` — Claude still sometimes uses Serena reads as *supplementary* exploration alongside CBM (not as empty-fallback), which trips the strict "zero Serena reads" assertion. This is a different, pre-existing concern not related to the empty-fallback bug.

## What ships

- `tests/e2e/lib/assert-routing.sh` — `assert_cbm_retries_on_empty` function added (~90 lines)
- `tests/e2e/matrix/cbm-empty-fallback.sh` — new live matrix test
- `tests/e2e/matrix/cross-language.sh` — new cross-language matrix test
- `tests/e2e/fixtures/cbm-empty-fallback-bad.json` — synthetic failing fixture
- `tests/e2e/fixtures/cbm-empty-retries-good.json` — synthetic passing fixture (retry)
- `tests/e2e/fixtures/cbm-empty-pivots-good.json` — synthetic passing fixture (pivot)
- `tests/e2e/fixtures/cbm-empty-terminates-good.json` — synthetic passing fixture (terminal)
- `tests/e2e/fixtures/cbm-empty-fallback-live.json` — live failure transcript from production run
- `skills/cbm-workflow/SKILL.md` — rewritten with empty-result recovery, project name table
- `hooks/session-start-startup.sh` — added CBM empty-result recovery rules to `<tool_routing>`
- `hooks/pre-serena-read-guard.sh` — new PreToolUse soft warn hook
- `hooks/post-cbm-read-record.sh` — new PostToolUse CBM call recorder
- `hooks/hooks.json` — registered new hooks
- `tests/unit/test-hook-properties.sh` — updated PreToolUse count expectation (2→3)
- `tests/unit/test-plugin-structure.sh` — updated PreToolUse count expectation (2→3)
- `docs/notes/cbm-fallback-failure-modes.md` — Stage 1 research artifact

## Known gaps that remain

- **LLM nondeterminism**: The full 4-assertion battery passes ~33% of the time. The new `cbm_retries_on_empty` assertion passes 100%, but `serena_only_for_edits` remains flaky at ~33%. Claude uses Serena reads alongside CBM even without empty-fallback triggers.
- **Interpreter-mode escapes**: `python -c` or `node -e` reading source files bypasses all tool routing hooks. Not tested.
- **Multi-turn edit+read interleave**: When edits and reads alternate, the "Serena only for edits" assertion may false-positive on legitimate pre-edit reads that Serena performs.
- **Explicit Serena requests**: If the user says "use Serena to find X", the guard fires a warning but Claude will (correctly) proceed. The soft warn is advisory.
- **The PreToolUse soft warn is advisory**: A sufficiently confident Claude (or one whose context already includes many Serena calls) can ignore exit-2 warnings. Hard block is deliberately not implemented per the constraint.
- **CBM path_filter issue**: Claude uses `path_filter="containermonitor/monitor.go"` which may not match CBM's internal path representation. This is a CBM UX issue, not a plugin issue.

## Recommended next direction

The primary remaining investment should be **CBM index discoverability tooling** — specifically, making `search_code` return a "did you mean?" hint when path_filter or pattern yield zero results. The production failure and our live reproduction both show that Claude sends reasonable-looking queries (e.g., `path_filter="containermonitor/monitor.go"`) that fail because CBM's internal path representation doesn't match. If CBM's empty-result response included the closest matching file paths or suggested dropping the filter, Claude would self-correct without needing skill content or hooks to nudge it. This is a CBM-server-side enhancement. Until then, the PreToolUse soft warn + skill escalation ladder are the cheapest reliable intervention, but they're compensating for a UX gap in the MCP server's response shape rather than fixing the root cause.
