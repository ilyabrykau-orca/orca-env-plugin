ultrathink

## Task: Bash source guard blocklist → path scan (v2.3.0)

Read `docs/specs/2026-04-19-allowlist-rewrite-plan.md`. Execute w/ TDD. No questions — decide yourself.

### Context

`src/hot/pre-tool-use.ts` = PreToolUse hook (compiled Bun binary). Intercepts Read/Edit/Write/Grep/Glob/Bash → prevents direct source access under `~/src/`, enforces CBM + Serena.

v2.2.1 uses **blocklist**: `isBashReadCmd` + `isBashEditCmd` + `compoundCmdCheck`. 4 TDD rounds found 23 bypasses. Blocklist = infinite whack-a-mole.

### Rewrite

Replace ALL blocklist logic w/ single **universal path scan**:

```
bashHasSourcePath(cmd) → scan entire command for source paths under ~/src → deny
```

**Delete**: `isBashReadCmd`, `isBashEditCmd`, `bashCmdTargetsSource`, `compoundCmdCheck`, `scanForEmbeddedSourcePaths` (~109 lines)
**Add**: `bashHasSourcePath` (~40 lines)
**Keep**: `isSourceExt`, `isAllowedExt`, `resolve`, `extOf`, `baseOf`, `hasShellChars`, RTK rewrite, Serena edit guard, native tool guard

### Bash Flow (New)

```
CLAUDE_RAW=1 → exit 0
bashHasSourcePath(cmd) → source path? → DENY (read or edit)
hasShellChars(cmd)? → yes: exit 0 | no: RTK rewrite → exit 0
```

### Read vs Edit

Source path found:
- Redirect `>` / `>>` before path, or `tee`/`sed -i`/`mv`/`rm` → "edit" → DENY_EDIT
- Otherwise → "read" → DENY_EXPLORE

### Fuzz Corpus

306 unique Bash cmds from real sessions at `tests/fixtures/bash-violation-corpus.txt`. ALL must deny. `#` lines = comments from multi-line scripts, not separate cmds.

### TDD

1. **Failing tests**: `tests/bash-allowlist.test.ts` w/ 306-cmd corpus → DENIED. Add allow cases.
2. **Implement** `bashHasSourcePath`: Replace blocklist w/ path scan.
3. **Fuzz**: 100% deny on corpus.
4. **Regression**: All 264 existing tests pass.
5. **Verify**: `bun run build && bun test` — 0 failures.

### Read First

```
docs/specs/2026-04-19-allowlist-rewrite-plan.md   # Full plan
src/hot/pre-tool-use.ts                            # Current impl (567 lines)
src/lib/constants.ts                               # Shared constants
tests/helpers.ts                                   # Test helper (runBinary)
tests/bash-file-ops.test.ts                        # Bash tests (34)
tests/integration-sequences.test.ts                # Compound tests (26)
tests/fixtures/bash-violation-corpus.txt            # 306 violation cmds
```

### Success

- [ ] 306 corpus cmds → DENIED
- [ ] Existing tests → PASS
- [ ] Zero false positives: git, build, non-source
- [ ] `bashHasSourcePath` ≤ 40 lines
- [ ] No cmd-specific lists
- [ ] `bun test` — 0 failures
- [ ] Commit as v2.3.0

### Rules

- TDD: tests fail first, then fix
- `bun -e '...'` for patching .ts (hooks block Read/Edit on source)
- Build: `bun run build` | Test: `bun test`
- No questions. Decide + execute.
