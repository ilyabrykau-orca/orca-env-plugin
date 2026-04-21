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

| Intent              | Use                                                                     | Never                       |
|---------------------|-------------------------------------------------------------------------|-----------------------------|
| Search code         | `mcp__codebase-memory-mcp__search_code`, `search_graph`                 | native `Grep`, `Glob`       |
| Read a symbol body  | `mcp__codebase-memory-mcp__get_code_snippet`                            | native `Read` on `.go/.ts`  |
| Trace call chain    | `mcp__codebase-memory-mcp__trace_path`                                  | manual grep                 |
| Edit a symbol       | `mcp__serena__replace_symbol_body`, `replace_content`                   | native `Edit`, `Write`      |
| Find callers        | `mcp__serena__find_referencing_symbols`                                 | manual grep                 |
| External docs       | `mcp__docs__search_docs`, `mcp__docs__fetch_url`                        | —                           |
| Web                 | `mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`                   | —                           |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any symbol edit.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content` backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file` offsets are 0-based.

## CBM patterns

- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Project names (CBM index)

See reference memory `codebase_memory_projects.md` for exact project strings.
