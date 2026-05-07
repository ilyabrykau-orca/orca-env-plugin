---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## Enforcement

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` HARD-BLOCKED on `.py .go .ts .tsx .js .jsx .rs .cpp .c .h .hpp .rb .java`.  
Non-code files (`.json .yaml .md .toml .cfg .sh Makefile Dockerfile`) → native tools allowed.

## Session init

```
mcp__serena__activate_project(project=<detected-project>)
```

## Projects

| Short | CBM project | Path | Lang |
|-------|-------------|------|------|
| orca | `Users-ilyabrykau-src-orca` | ~/src/orca | Python/Django |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` | ~/src/orca-sensor | Go |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | `orca-unified` | ~/src | Python+Go |
| helm-charts | `Users-ilyabrykau-src-helm-charts` | ~/src/helm-charts | YAML |

## Params cheat sheet

| Tool | Param | Correct | Wrong |
|------|-------|---------|-------|
| `search_code` (CBM) | text | `pattern` | `query` |
| `search_code` (CBM) | scope | `project` (required) | omitting it |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `relative_path` + `start_line` |
| `search_graph` (CBM) | scope | `project` (required) | omitting it |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement`, `is_regex` |
| `replace_content` | mode | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |
