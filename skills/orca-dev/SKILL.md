---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd | Serena project | Path style |
|-----|---------------|------------|
| `~/src` (unified) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate: `mcp__serena__activate_project(project=<name>)` when switching repos.

## Tool routing

| Intent | Use | Never |
|--------|-----|-------|
| Search / grep code | `mcp__codebase-memory-mcp__search_code` | native `Grep`, `Glob` |
| Find symbol / list symbols | `mcp__codebase-memory-mcp__search_graph` | `mcp__serena__find_symbol` for exploration |
| Read symbol body | `mcp__codebase-memory-mcp__get_code_snippet` | native `Read` on source |
| Trace call chain | `mcp__codebase-memory-mcp__trace_path` | manual grep |
| Architecture overview | `mcp__codebase-memory-mcp__get_architecture` | — |
| Find callers (pre-edit) | `mcp__serena__find_referencing_symbols` | — |
| Edit a symbol | `mcp__serena__replace_symbol_body`, `replace_content` | native `Edit`, `Write` |
| Delete a symbol | `mcp__serena__safe_delete_symbol` | native `Edit` |
| Non-code files | native `Read` / `Edit` / `Write` | — |
| Web search | `mcp__exa__web_search_exa` | — |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any edit/delete.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content`: backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file`: 0-based lines, `end_line` inclusive.

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
