---
name: orca-dev
description: Source code work in orca repos. CBM for search, native Edit for writes, find_referencing_symbols before editing exported symbols.
---

# orca-dev

## Workspace routing

| cwd pattern | serena project | path style |
|---|---|---|
| `~/src` (unified workspace) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate via `mcp__serena__activate_project(project=<name>)` when switching.

## Tool routing (advisory)

| Intent | Use | Avoid |
|---|---|---|
| Search / grep code | `codebase-memory-mcp.search_code` | native Grep when CBM is indexed |
| Find symbol / list symbols | `codebase-memory-mcp.search_graph` | — |
| Read a symbol body | `codebase-memory-mcp.get_code_snippet` | Read on large source files |
| Trace call chain | `codebase-memory-mcp.trace_path` | manual grep |
| Check callers before edit | `serena.find_referencing_symbols` | editing without checking |
| Edit source code | native `Edit` after reference check | blind writes |
| Non-source files | native `Read` / `Edit` / `Write` | — |
| External docs | `mcp__docs__search_docs` | — |
| Web search | `mcp__exa__web_search_exa` | — |

Native tools always work. CBM is preferred for structural queries (~120x fewer tokens).

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before editing exported symbols.
2. Use native `Edit` for the actual change.
3. Run `bun test` (or project test command) after edits.

## CBM patterns

- Start with `get_architecture(project=...)` for multi-symbol exploration.
- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
