---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits, docs/exa for external. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd pattern                  | serena project        | path style                  |
|------------------------------|-----------------------|-----------------------------|
| `~/src` (unified workspace)  | `orca-unified`        | repo-prefixed absolute      |
| `~/src/<repo>/**`            | `<repo>`              | relative to repo root       |

Activate via `mcp__serena__activate_project(project=<name>)` when switching.

## Tool boundaries (hard rules)

**Any source code exploration, search, navigation, or read = CBM only.**
Serena is write-only (plus `find_referencing_symbols` immediately before an edit).

| Intent                        | Use                                                            | Never                                                            |
|-------------------------------|----------------------------------------------------------------|------------------------------------------------------------------|
| Search / grep code            | `mcp__codebase-memory-mcp__search_code`                        | native `Grep`, `Glob`, `mcp__serena__search_for_pattern`         |
| Find symbol / list symbols    | `mcp__codebase-memory-mcp__search_graph`                       | `mcp__serena__find_symbol`, `mcp__serena__get_symbols_overview`  |
| Read a symbol body            | `mcp__codebase-memory-mcp__get_code_snippet`                   | `mcp__serena__read_file`, native `Read` on source                |
| Trace call chain              | `mcp__codebase-memory-mcp__trace_path`                         | manual grep                                                      |
| Find callers (pre-edit only)  | `mcp__serena__find_referencing_symbols`                        | —                                                                |
| Edit a symbol                 | `mcp__serena__replace_symbol_body`, `replace_content`          | native `Edit`, `Write`                                           |
| External docs                 | `mcp__docs__search_docs`, `mcp__docs__fetch_url`               | —                                                                |
| Web                           | `mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`          | —                                                                |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any symbol edit.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content` backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file` offsets are 0-based.

## CBM patterns

- **Start with `get_architecture(project=...)`** for any multi-symbol exploration — one call returns the full package/service map, preventing 4–6 exploratory round-trips.
- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`. Never use `get_code_snippet(relative_path=..., start_line=..., end_line=...)` — qualified name lookup is direct.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Parallelism — MANDATORY

Fire **all independent tool calls in one message**. Never serialize calls with no data dependency.

Must be parallel (single message, multiple tool calls):
- Multiple `search_code` / `get_code_snippet` for unrelated symbols
- CBM reads + `ctx_execute` shell commands when neither needs the other's result
- Any mix of CBM / CTX / Bash with no data dependency

## CTX shell execution

`ctx_batch_execute` runs its `commands` array **serially** — no setting changes this.

- **Independent commands** → send multiple `ctx_execute` calls in one message (parallel)
- **Dependent commands** → chain with `&&` in a single `ctx_batch_execute` entry; never use `sleep N` guards
- `ctx_batch_execute` is best when you need FTS5 indexing of sequential output for later `ctx_search`
- **`intent` parameter** — always set on `ctx_execute` for commands that produce large output (pprof, benchmarks, build logs, test output). When output >5KB, `intent` auto-indexes and returns only matched sections; without it the full output floods context. Example: `intent: "allocation sources per function"`

## Project names (CBM index)

See reference memory `codebase_memory_projects.md` for exact project strings.
