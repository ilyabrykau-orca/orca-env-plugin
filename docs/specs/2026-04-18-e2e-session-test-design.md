# E2E Session Test

## Problem

Unit tests validate individual hooks. Nothing validates full session: SessionStart → UserPromptSubmit → PreToolUse → PostToolUse → Stop.

Gap proved: `cat file.ts` bypassed source enforcement — Bash handler lacked source-path checks. Existed despite 56 unit tests passing.

## Design

### Scenario: "Fix bug in orca/sensors/base.py"

15-step session exercising every hook + guard:

| Step | Hook | Tool/Action | Expected |
|------|------|-------------|----------|
| 1 | SessionStart | cwd=~/src | orca-unified, routing table |
| 2 | UserPromptSubmit | "explore the codebase to find the bug" | suggests codebase-explorer |
| 3 | PreToolUse | Read ~/src/orca/sensors/base.py | DENY → CBM |
| 4 | PreToolUse | Glob **/*.py under ~/src | DENY → CBM |
| 5 | PreToolUse | Grep type=py under ~/src | DENY → CBM |
| 6 | PreToolUse | Bash: cat ~/src/orca/sensors/base.py | DENY → CBM |
| 7 | PreToolUse | Bash: sed -i on ~/src/orca/views.py | DENY → Serena |
| 8 | PreToolUse | mcp__cbm__search_graph | ALLOW |
| 9 | PreToolUse | Read ~/src/orca/README.md | ALLOW (non-code) |
| 10 | PreToolUse | Bash: git log --oneline | ALLOW + RTK |
| 11 | UserPromptSubmit | "edit the function to fix the bug" | suggests serena-editor |
| 12 | PreToolUse | serena replace_symbol_body (no refs) | WARN exit 1 |
| 13 | PostToolUse | serena find_referencing_symbols | records state |
| 14 | PreToolUse | serena replace_symbol_body (refs traced) | ALLOW |
| 15 | Stop | transcript_path | stats written |

### Architecture

Single `tests/e2e-session.test.ts`:
- `SessionSimulator` tracks state (dir, session id)
- Each step = named test in `describe("session: fix-bug-workflow")`
- Sequential, shared `simulator` instance

### Non-Goals

No LLM calls, no real MCP, no real filesystem — hook binary I/O only.

### Validation

All 15 steps deterministic. Wrong allow/deny/warn → test fails w/ descriptive msg.
