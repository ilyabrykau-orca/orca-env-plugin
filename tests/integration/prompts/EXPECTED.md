# Expected Behavior for Integration Test Prompts

| # | Prompt | Expected Tool | Must NOT Use |
|---|--------|---------------|-------------|
| 01 | Python class search | `mcp__codebase-memory-mcp__search_graph` or `mcp__codebase-memory-mcp__search_code` | `Read`, `Grep` |
| 02 | Go interface search | `mcp__codebase-memory-mcp__search_graph` or `mcp__codebase-memory-mcp__search_code` | `Read`, `Grep` |
| 03 | Config file read | Native `Read` (allowed — .yaml) | — |
| 04 | Edit request | `mcp__serena__find_referencing_symbols` first, then `replace_content` | Native `Edit` |
| 05 | Find callers | `mcp__codebase-memory-mcp__trace_call_path(function_name="process_event")` or `search_graph` | `Grep` |
| 06 | Broad concept | `mcp__codebase-memory-mcp__search_code` or `mcp__codebase-memory-mcp__get_architecture` | `Read`, `Grep` |
| 07 | Symbol source | `mcp__codebase-memory-mcp__search_graph` then `get_code_snippet`, or `mcp__serena__find_symbol(include_body=True)` | `Read` |
| 08 | Doc search | Native `Read` / docs skill / web docs tools, not CBM doc-search aliases | `Grep` |
| 09 | Native block | Hook blocks `Grep` on .py -> Claude retries with `mcp__codebase-memory-mcp__` | `Grep` (blocked by hook) |
| 10 | Mixed files | Native `Read` for .toml (allowed), then `mcp__codebase-memory-mcp__` for .py | `Read` on .py |

## What to Check in Each Test

- **01, 02**: Claude uses graph/search tools, not raw `Read`/`Grep` on code
- **04**: `find_referencing_symbols` called with `name_path=` + FILE `relative_path=`, not `symbol_name=`
- **05**: `trace_call_path` or equivalent graph query is used for callers
- **07**: Serena `find_symbol` called with `name_path_pattern=` not `name=`
- **Memory**: `read_memory` called with `memory_name=` not `memory_file=`
- **Any edit**: No `\1` backrefs — must be `$!1`
