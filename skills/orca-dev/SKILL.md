---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd pattern | Serena project | path style |
|---|---|---|
| `~/src` (unified workspace) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate via `mcp__serena__activate_project(project=<name>)` when switching.

## Tool routing

| Intent | Use | Never |
|---|---|---|
| Search / grep code | `mcp__codebase-memory-mcp__search_code` | native `Grep`, `Glob` |
| Find symbol / list symbols | `mcp__codebase-memory-mcp__search_graph` | `mcp__serena__find_symbol` for exploration |
| Read a symbol body | `mcp__codebase-memory-mcp__get_code_snippet` | native `Read` on source |
| Trace call chain | `mcp__codebase-memory-mcp__trace_path` | manual grep |
| Architecture overview | `mcp__codebase-memory-mcp__get_architecture` | — |
| Find callers (pre-edit) | `mcp__serena__find_referencing_symbols` | — |
| Edit a symbol | `mcp__serena__replace_symbol_body`, `replace_content` | native `Edit`, `Write` |
| Delete a symbol | `mcp__serena__safe_delete_symbol` | native `Edit` |
| Non-code files | native `Read` / `Edit` / `Write` | — |
| Web search | `mcp__exa__web_search_exa` | — |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any symbol edit/delete.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content` backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file` offsets are 0-based.

## CBM patterns

- Start with `get_architecture(project=...)` for multi-symbol exploration.
- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Project names (CBM index)

| Project | Path | Language |
|---|---|---|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
