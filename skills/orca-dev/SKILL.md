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

- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Parallelism — MANDATORY

Fire **all independent CBM reads in one message** (multiple tool calls). Never serialize round-trips that have no data dependency.

Must be parallel in a single message:
- Multiple `search_code` / `get_code_snippet` for different symbols
- `search_code` + `trace_path` when neither depends on the other's result
- Any combination of CBM reads that don't feed each other

## Project names (CBM index)

See reference memory `codebase_memory_projects.md` for exact project strings.
