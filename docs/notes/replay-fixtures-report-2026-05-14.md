# E2E Replay Report — 2026-05-14

Replays the 4 routing assertions in `tests/e2e/lib/assert-routing.sh` against the 7 recorded transcript fixtures under `tests/e2e/fixtures/`. Measures deny/bypass classification of each replayed transcript without launching the live `claude` CLI.

Runner: `tests/e2e/replay-fixtures.sh`

## Results matrix

| fixture | no-native-on-code | cbm-dominates | serena-edits-only | cbm-retries-on-empty | expectation |
|---|---|---|---|---|---|
| `cbm-dominates-transcript.json`     | PASS ✓ | PASS ✓ | PASS ✓ | PASS ✓ | pass pass pass pass |
| `cbm-empty-fallback-bad.json`       | PASS ✓ | FAIL ✓ | FAIL ✓ | FAIL ✓ | pass fail fail fail |
| `cbm-empty-fallback-live.json`      | PASS   | FAIL   | FAIL   | PASS   | any (last live capture) |
| `cbm-empty-pivots-good.json`        | PASS ✓ | PASS ✓ | PASS ✓ | PASS ✓ | pass pass pass pass |
| `cbm-empty-retries-good.json`       | PASS ✓ | PASS ✓ | PASS ✓ | PASS ✓ | pass pass pass pass |
| `cbm-empty-terminates-good.json`    | PASS ✓ | PASS ✓ | PASS ✓ | PASS ✓ | pass pass pass pass |
| `serena-dominates-transcript.json`  | PASS ✓ | FAIL ✓ | FAIL ✓ | **PASS ✗** | pass fail fail fail |

**Totals:** 28 runs · 21 PASS · 7 FAIL · 1 expectation mismatch

Legend: ✓ matches expectation · ✗ does NOT match · blank = no expectation set.

## Per-assertion behavior

- **`assert_no_native_on_code`** — 7/7 PASS. No fixture contains native `Read/Edit/Write/Grep/Glob` against source files. Native deny is fully held in recorded transcripts.
- **`assert_cbm_dominates_reads`** — 4 PASS / 3 FAIL. Production-failure fixtures (`*-bad.json`, `serena-dominates`, last live capture) correctly classified as Serena-dominant.
- **`assert_serena_only_for_edits`** — 4 PASS / 3 FAIL. Same three transcripts flagged for using Serena read tools (`find_symbol`, `get_symbols_overview`, etc.).
- **`assert_cbm_retries_on_empty`** — 5 PASS / 1 FAIL / 1 mismatch. The bad fixture is caught, but `serena-dominates-transcript.json` slips through.

## Mismatch analysis: `serena-dominates-transcript.json`

`assert_cbm_retries_on_empty` returned PASS where FAIL was expected.

Root cause: fixture contains **0 `tool_result` entries** (assistant-side only — recorded from API output without the matching user-side tool_result frames). The assertion classifies CBM calls as EMPTY by inspecting the `tool_result.content[].text` field against patterns like `"results":[]`, `"No symbols found"`, etc. With no results to inspect, no CBM call is classified as empty, so the assertion has nothing to flag and returns PASS vacuously.

This is a **fixture defect**, not an assertion bug. The `cbm-empty-fallback-bad.json` fixture (which DOES include matching tool_results) correctly triggers FAIL.

### Fixes (pick one)

1. **Augment fixture** — synthesize matching `tool_result` user-turn entries with empty-content payloads (`{"results":[]}`) after each CBM `search_code` call in the existing transcript. Lowest-risk, preserves the original failure narrative.
2. **Make assertion stricter** — when a CBM read call has *no* matching tool_result and is immediately followed by a Serena read, treat that as `FAIL_FALLBACK` (orphan-tool-use heuristic). Catches more variants but risks false positives on partial transcripts.
3. **Drop the fixture** — `serena-dominates-transcript.json` is superseded by `cbm-empty-fallback-bad.json` (synthetic, controlled) and `cbm-empty-fallback-live.json` (live capture). Keeping a non-actionable fixture adds noise.

Recommended: option 1, then re-run.

## `cbm-empty-fallback-live.json` notes

Last live capture from a recent matrix run. Flagged FAIL on `cbm-dominates` and `serena-edits-only`. Expectations left as `any` since this fixture rotates each live run. Promote to a tracked baseline only when intentional.

## How to run

```bash
bash tests/e2e/replay-fixtures.sh
```

No `E2E=1` gate, no `claude` CLI required. Pure offline replay. Exit 0 when all fixtures match their expectations; exit 1 when any mismatch (currently 1 — the fixture defect above).

## Next actions

1. Repair `serena-dominates-transcript.json` per option 1, re-run.
2. Wire `replay-fixtures.sh` into `tests/run-all.sh --unit` so the replay is part of the default suite.
3. Once the fixture is repaired and the runner is wired, this exact report becomes the artifact `run-all.sh` emits on each invocation.
