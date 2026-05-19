---
name: routing-params
description: Full CBM/Serena parameter reference, project names, recovery procedures. Load when hitting param errors, wrong project name, backrefs, or recovery from CBM empty results.
---

# Routing Params Reference

## CBM params

| Tool | Param | Correct | Wrong |
|------|-------|---------|-------|
| `search_code` | text | `pattern=` | `query=` |
| `search_code` | scope | `project=` (required) | omitting it |
| `get_code_snippet` | symbol | `qualified_name=SYMBOL_NAME` | file path, `relative_path=` + line numbers |
| `search_graph` | scope | `project=` (required) | omitting it |

## Serena params

| Tool | Param | Correct | Wrong |
|------|-------|---------|-------|
| `find_referencing_symbols` | symbol | `name_path=` + `relative_path=FILE` | dir path, `symbol_name=` |
| `replace_content` | params | `needle=`, `repl=`, `mode=` | `pattern=`, `replacement=`, `is_regex=` |
| `replace_content` | mode | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| `find_symbol` | symbol | `name_path_pattern=` | `name=`, `symbol_name=` |

## Projects

| Short | CBM project | Path |
|-------|-------------|------|
| orca | `Users-ilyabrykau-src-orca` | ~/src/orca |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` | ~/src/orca-sensor |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` | ~/src/orca-runtime-sensor |
| orca-unified | `orca-unified` | ~/src |
| helm-charts | `Users-ilyabrykau-src-helm-charts` | ~/src/helm-charts |

## Recovery

- CBM empty result → `list_projects()` to confirm project name, retry with correct name
- Serena "no such tool" → `mcp__serena__activate_project(project=SHORT_NAME)` then retry
- `get_code_snippet` "symbol not found" → use `search_graph(name_pattern=NAME, project=PROJ)` first to discover exact qualified_name
- `read_file` "no such tool" → does NOT exist in claude-code context; use CBM search_code/get_code_snippet

## Serena tools available in claude-code context

Read: `get_symbols_overview`, `find_symbol`, `find_referencing_symbols`, `find_declaration`, `find_implementations`
Edit: `replace_content`, `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`, `rename_symbol`, `safe_delete_symbol`
NOT available: `read_file`, `create_text_file`, `list_dir`, `find_file`, `search_for_pattern`
