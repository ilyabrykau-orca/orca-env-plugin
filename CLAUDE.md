# orca-env-plugin

Claude Code plugin: workspace detection, advisory tool routing, session analytics. TypeScript + Bun.

<tool_routing>
## Tool routing — advisory

| Intent | Use | Avoid |
|---|---|---|
| Find callers / call chain | `codebase-memory-mcp.trace_path` | manual grep |
| Find functions by name | `codebase-memory-mcp.search_graph` | Glob on source |
| Read a symbol body | `codebase-memory-mcp.get_code_snippet` | Read on large source files |
| Grep-like text search | `codebase-memory-mcp.search_code` | native Grep when CBM is indexed |
| Check impact before edit | `serena.find_referencing_symbols` | editing without checking callers |
| Edit source code | native `Edit` after reference check | blind writes without context |
| Non-source files (.json, .yaml, .md) | native `Read` / `Edit` / `Write` | — |
| Shell commands | `Bash` | — |
| Architecture overview | `codebase-memory-mcp.get_architecture` | reading files one by one |

Native Read, Edit, Grep, Glob always work. CBM is preferred for structural queries because it uses ~120x fewer tokens.
</tool_routing>

## Execution contract

- No clarifying turns. State assumption, proceed, verify with `bun test`.
- Batch independent tool calls in one message.
- Responses under 500 words. Write artifacts to files.

## Commands

- Build: `bash build.sh`
- Test: `bun test`
- Typecheck: `bun run --bun tsc --noEmit`

## Project structure

- `src/` — plugin source (index.ts, session-start.ts, stop.ts)
- `hooks/` — hook configuration (hooks.json)
- `skills/` — orca-dev skill
- `agents/` — orca-dev agent
- `dist/` — compiled Bun binary
- `tests/` — Bun test suite
