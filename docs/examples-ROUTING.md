# Code Tool Routing (always-on, plugin-independent)

For source files (`.py .go .ts .tsx .js .jsx .rs .cpp .c .h .rb .java`):

## Reads / discovery

- PREFER: `mcp__codebase-memory-mcp__{search_code, search_graph, get_code_snippet, trace_path, get_architecture, query_graph}` with `project=<repo-name>` (required).
- FALLBACK if CBM empty/error: `mcp__serena__{find_symbol, get_symbols_overview, search_for_pattern, read_file}`.
- AVOID native `Read`/`Grep`/`Glob` on code files. Non-code (`.json .yaml .md .toml .sh Makefile Dockerfile`) → native tools fine.

## Edits

- PREFER: `mcp__serena__{replace_symbol_body, replace_content, insert_after_symbol, insert_before_symbol, rename_symbol}`.
- BEFORE editing: call `mcp__serena__find_referencing_symbols(name_path=..., relative_path=FILE)` to trace impact.
- AVOID native `Edit`/`Write` on code files.

## Params traps (frequent mis-call sources)

| Tool | Correct | Wrong |
|---|---|---|
| `search_code` | `pattern=...`, `project=...` (required) | `query=`, no project |
| `get_code_snippet` | `qualified_name=...` | `relative_path` + `start_line` |
| `search_graph` | `project=...` required | omitting project |
| `find_referencing_symbols` | `name_path=...`, `relative_path=FILE` | dir path, `symbol_name=` |
| `replace_content` | `needle`, `repl`, `mode` | `pattern`, `replacement`, `is_regex` |
| `replace_content` mode | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` backrefs | `$!1`, `$!2` | `\1`, `\2` |
| `find_symbol` (Serena) | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` (Serena) | 0-based lines, `end_line` inclusive | 1-based |

## CBM error handling

If CBM returns malformed/error/`project not found`: (1) verify project name with `list_projects()`, (2) retry once with different params, (3) pivot to Serena. **Do not fall back to native tools.**

## Common orca projects

| short | CBM project name | path | lang |
|---|---|---|---|
| orca | `Users-ilyabrykau-src-orca` | `~/src/orca` | Python/Django |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` | `~/src/orca-sensor` | Go |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` | `~/src/orca-runtime-sensor` | Go+eBPF |
| orca-unified | `orca-unified` | `~/src` | Python+Go |
| helm-charts | `Users-ilyabrykau-src-helm-charts` | `~/src/helm-charts` | YAML |
