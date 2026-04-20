# Infinite Regression TDD Loop — Design Spec

## Problem

14 pre-existing test failures. 706-line bash corpus only partially tested. No regression guard against future changes breaking deterministic behavior. RTK rewrite is best-effort — simple commands can silently pass without RTK.

## Goal

Every tool invocation from any historical conversation produces a deterministic, expected result. Continuous `/loop` guard enforces this. Zero unfiltered Bash.

## Architecture

### Data Sources (priority order)

1. **Session transcripts** (`~/.claude/projects/*/session_transcripts/*.jsonl`) — extract every `tool_name` + `tool_input` pair
2. **Existing corpus** (`tests/fixtures/bash-violation-corpus.txt`) — 706 lines, curated violations
3. **Hook logs** (`~/.claude/logs/hooks.jsonl`) — 9730 entries with action/tool/path/reason

### Output Format

`tests/fixtures/regression-corpus.json`:
```json
[
  {"tool_name": "Bash", "tool_input": {"command": "cat ~/src/orca/views.py"}, "expected": "deny-explore"},
  {"tool_name": "Read", "tool_input": {"file_path": "/Users/.../main.go"}, "expected": "deny-explore"},
  {"tool_name": "Bash", "tool_input": {"command": "git status"}, "expected": "allow-rtk"}
]
```

Expected outcomes: `deny-explore`, `deny-edit`, `allow-rtk`, `allow-passthrough` (compound cmds only).

Deduped by `tool_name` + normalized `tool_input`.

## Test Structure

### `tests/regression-deterministic.test.ts`

```
Load regression-corpus.json
Group by expected:
  deny-explore → isDenied + reason contains "codebase-memory-mcp"
  deny-edit → isDenied + reason contains "Serena"
  allow-rtk → !isDenied + json has updatedInput.command
  allow-passthrough → !isDenied + no updatedInput (compound cmds)

test.each(corpus)("toolName: %s | cmd: %s → %s", async (entry) => { ... })
```

### Test count targets

- Existing: 558 pass (fix current 14 failures)
- Corpus: 276 deny + 18 allow (existing bash-allowlist)
- Regression: 500-2000 unique entries from mining
- Total: ~800-2500 tests, all green

## RTK Enforcement (Breaking Change)

### Current flow
```
bashHasSourcePath → deny source
hasShellChars → exit 0 (pass-through)
RTK rewrite → success: rewrite | fail: exit 0 (silent pass-through)
CLAUDE_RAW=1 → exit 0 (full bypass)
```

### New flow
```
bashHasSourcePath → deny source
hasShellChars → exit 0 (compound cmds)
RTK rewrite → success: rewrite | fail: DENY
```

No `CLAUDE_RAW=1` bypass. No `rtk proxy` escape hatch. Every non-compound Bash command goes through RTK or gets denied.

### RTK exit code handling
- `0` + rewrite → allow with rewritten command
- `3` + rewrite → allow with rewritten command
- Any other → **DENY** with message: "All Bash commands must go through RTK rewrite."

### Compound commands (has shell chars)
- Source path detected → denied (bashHasSourcePath runs first)
- No source path → pass through (RTK can't rewrite `&&`, `|`, `;`, etc.)

### New deny constant
```typescript
const DENY_RTK = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"All Bash commands must go through RTK rewrite."}}';
```

## `/loop` Stability Guard

### Config
- Interval: 5 minutes
- Command: `bun test`
- Activates after green baseline achieved

### Failure pipeline
```
/loop 5m bun test
  → failure detected
  → spawn subagent (claude-toolkit:orca-dev)
  → subagent reads failure output
  → subagent diagnoses: test expectation wrong OR source bug?
  → subagent TDD-fixes (source + tests)
  → subagent calls mcp__pal__consensus for review
  → consensus approves → commit
  → consensus rejects → alert user, stop loop
```

### Subagent guardrails
1. Never weaken assertions — update expected only if behavior change verified via git diff
2. Never delete tests — only add or update
3. Max 3 fix attempts — after 3 consensus rejections, stop loop + alert
4. Scope limit — only `orca-env-plugin/` (src + tests)
5. Commit convention — `fix(regression): <description>` with consensus review in body

### RTK interaction
RTK ships new fallback rules → some cmds change from `allow-passthrough` to `allow-rtk`. Subagent detects, updates regression-corpus.json, consensus confirms.

## Implementation Phases

### Phase 1: Green Baseline
- Fix 14 pre-existing test failures (update expectations to match current behavior)
- Remove `CLAUDE_RAW=1` bypass from handler
- Add RTK-fail deny logic + `DENY_RTK` constant
- Update existing tests for removed bypass + new RTK enforcement
- Target: 558/558 pass

### Phase 2: Mining Pipeline
- Script: `scripts/mine-regression-corpus.ts`
- Read session transcripts → extract tool calls
- Read existing corpus → already loaded
- Read hook logs → parse jsonl
- Dedup by tool_name + normalized input
- Run each through binary → record expected outcome
- Output: `tests/fixtures/regression-corpus.json`

### Phase 3: Regression Test Suite
- `tests/regression-deterministic.test.ts`
- Load corpus.json, test.each → assert expected outcome
- 100% green required

### Phase 4: `/loop` Stability Guard
- `/loop 5m bun test`
- On failure: spawn subagent → TDD fix → consensus → commit or halt

### Execution order
```
Phase 1 → Phase 2 → Phase 3 → Phase 4
  green     corpus    all new    loop
 baseline   mined     tests     active
                      green
```

## Success Criteria

- [ ] 0 test failures (all existing + new regression)
- [ ] No `CLAUDE_RAW=1` bypass in handler
- [ ] Every simple Bash cmd → RTK rewrite or deny
- [ ] Regression corpus covers all historical tool invocations
- [ ] `/loop` running, auto-fixes with consensus gate
- [ ] No cmd-specific blocklists in source

## Files

| File | Change |
|------|--------|
| `src/hot/pre-tool-use.ts` | Remove CLAUDE_RAW bypass, add RTK-fail deny |
| `scripts/mine-regression-corpus.ts` | New — mining pipeline |
| `tests/fixtures/regression-corpus.json` | New — mined corpus |
| `tests/regression-deterministic.test.ts` | New — deterministic regression suite |
| `tests/*.test.ts` (existing) | Fix 14 failures, update expectations |
