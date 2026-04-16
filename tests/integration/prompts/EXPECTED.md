# Expected Behavior for Integration Test Prompts

| # | Prompt | Expected Tool | Must NOT Use |
|---|--------|---------------|-------------|
| 01 | Python class search | `mcp__codanna__find_symbol` or `semantic_search_with_context` | `Read`, `Grep` |
| 02 | Go interface search | `mcp__codanna__find_symbol` or `search_symbols` | `Read`, `Grep` |
| 03 | Config file read | Native `Read` (allowed — .yaml) | — |
| 04 | Edit request | `mcp__serena__find_referencing_symbols` first, then `replace_content` | Native `Edit` |
| 05 | Find callers | `mcp__codanna__find_callers(function_name="process_event")` | `Grep` |
| 06 | Broad concept | `mcp__codanna__semantic_search_with_context` | `Read`, `Grep` |
| 07 | Symbol source | `mcp__codanna__find_symbol` or `mcp__serena__find_symbol(include_body=True)` | `Read` |
| 08 | Doc search | `mcp__codanna__semantic_search_docs` or `search_documents` | `Grep` |
| 09 | Native block | Hook blocks `Grep` on .py → Claude retries with `mcp__codanna__` | `Grep` (blocked by hook) |
| 10 | Mixed files | Native `Read` for .toml (allowed), then `mcp__codanna__` for .py | `Read` on .py |

## What to Check in Each Test

- **01, 02**: Claude uses `lang=` not `language=`
- **04**: `find_referencing_symbols` called with `name_path=` + FILE `relative_path=`, not `symbol_name=`
- **05**: `find_callers` called with `function_name=` not `symbol_id=`
- **07**: Serena `find_symbol` called with `name_path_pattern=` not `name=`
- **Memory**: `read_memory` called with `memory_name=` not `memory_file=`
- **Any edit**: No `\1` backrefs — must be `$!1`
