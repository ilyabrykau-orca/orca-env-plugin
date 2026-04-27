---
name: orca-dev
description: "Source-code routing for orca repos under ~/src. Routes ALL reads/searches/navigation through mcp__codebase-memory-mcp__* (search_code, get_code_snippet, search_graph, trace_path, get_architecture) and ALL writes through mcp__serena__* (replace_symbol_body, replace_content, insert_after_symbol, rename_symbol). Use this skill PROACTIVELY whenever the user works in ~/src/orca* repos or with .go .ts .tsx .py .rs source files. Triggers on: find function, look at code, trace callers, find references, rename, refactor, edit symbol, add method, fix bug, or any cwd under ~/src. Do NOT wait for the user to name CBM or Serena explicitly. Do NOT use for .md .json .yaml configs — those use native Read/Write/Edit."
---

# orca-dev

## Workspace routing

| cwd pattern | Serena project | path style |
|---|---|---|
| `~/src` (unified) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate: `mcp__serena__activate_project(project=<name>)` when switching repos.

## Tool routing

| Intent | Use |
|---|---|
| Search / grep code | `mcp__codebase-memory-mcp__search_code` |
| Find symbol / list symbols | `mcp__codebase-memory-mcp__search_graph` |
| Read symbol body | `mcp__codebase-memory-mcp__get_code_snippet` |
| Trace call chain | `mcp__codebase-memory-mcp__trace_path` |
| Architecture overview | `mcp__codebase-memory-mcp__get_architecture` |
| Impact / callers before edit | `mcp__serena__find_referencing_symbols` |
| Edit source code | `mcp__serena__replace_symbol_body` / `replace_content` |
| Non-source files | native `Read` / `Edit` / `Write` |
| Web search | `mcp__exa__web_search_exa` |
| External docs | `mcp__docs__search_docs` |

Never use native Read, Edit, Grep, or Glob on source files (.go .ts .tsx .py .rs).

## Edit protocol

1. `find_referencing_symbols(name_path=<symbol>, relative_path=<file>)` — a hook rejects edits without it.
2. `mcp__serena__replace_symbol_body` or `replace_content` for the actual change.
3. Run `bun test` / `go test ./...` after edits.

## CBM patterns

- Start with `get_architecture(project=...)` for multi-symbol exploration.
- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.

## Direct invocation

This skill is also a slash command: `/orca-dev`.
Use `/orca-dev` to force-load the routing rules before a source-code task.

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
