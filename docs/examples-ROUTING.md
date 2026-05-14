# Code Tool Routing (always-on, plugin-independent)

For source files (`.py .go .ts .tsx .js .jsx .rs .cpp .c .h .rb .java`):

## Hard rule — file-path lookups

If the user's request already contains a code file path (e.g. `orca-sensor/foo/bar.go:53` or `**/handlers/session-start.ts`), your **first** tool call must be `mcp__codebase-memory-mcp__get_code_snippet` or `mcp__serena__read_file` on that path. Never preflight with `Glob`/`Grep`/`Read` "to make sure the file is there" — the user already said it is. A Glob/Grep on a `.py/.go/.ts/.tsx/.js/.jsx/.rs/.cpp/.c/.h/.rb/.java` path counts as a native-code bypass even if you only used it for path confirmation.

**Concrete recipes** — copy these patterns verbatim instead of pre-Globbing:

User says `orca-sensor/services/sensor-management/server/bu_cache_refresher.go:53`:
```
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="services/sensor-management/server/bu_cache_refresher.go",
    project="Users-ilyabrykau-src-orca-sensor")
```
or, for a fixed line window:
```
mcp__serena__activate_project(project="orca-sensor")  # only if not already active
mcp__serena__read_file(
    relative_path="services/sensor-management/server/bu_cache_refresher.go",
    start_line=45, end_line=75)   # 0-based, inclusive
```

User says `orca-env-plugin/src/handlers/session-start.ts`:
```
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="src/handlers/session-start.ts",
    project="orca-env-plugin")
```

If `get_code_snippet` returns empty/error, retry once with broader `qualified_name` (drop suffix), or pivot to `mcp__serena__read_file` per the recipe above. Still no Glob.

## Reads / discovery

- PREFER: `mcp__codebase-memory-mcp__{search_code, search_graph, get_code_snippet, trace_path, get_architecture, query_graph}` with `project=<repo-name>` (required).
- FALLBACK if CBM empty/error: `mcp__serena__{find_symbol, get_symbols_overview, search_for_pattern, read_file}`.
- AVOID native `Read`/`Grep`/`Glob` on code files. Non-code (`.json .yaml .md .toml .sh Makefile Dockerfile`) → native tools fine. (See **Hard rule — file-path lookups** above.)

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

## Recovery — don't fall back to native

If a CBM call returns empty/error/`project not found`:
1. `mcp__codebase-memory-mcp__list_projects()` — verify exact project name.
2. Retry CBM with corrected `project` or broader `pattern`.
3. If still empty: pivot to Serena (steps below).

If a Serena call fails with `project not active` / `path not in project` / `symbol not found at root`:
1. `mcp__serena__activate_project(project=<short-name>)` — the project name from ROUTING.md's table below, **not** an absolute path.
2. Re-issue the Serena call.
3. If Serena `find_symbol` still misses: use `mcp__codebase-memory-mcp__get_code_snippet(qualified_name=..., project=...)` — that is the canonical read tool, not native Read.

**Never** fall back to native `Read`/`Grep` on code files just because CBM or Serena errored. The recovery sequence above is short and converges.

## Read a specific file region without Serena/CBM symbol resolution

Use `mcp__serena__read_file(relative_path=..., start_line=0, end_line=N)` (0-based, end inclusive). If even that fails, `activate_project` first. Native `Read` is the **last resort** and signals a real config bug worth reporting, not a routine action.

## Common orca projects

| short | CBM project name | path | lang |
|---|---|---|---|
| orca | `Users-ilyabrykau-src-orca` | `~/src/orca` | Python/Django |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` | `~/src/orca-sensor` | Go |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` | `~/src/orca-runtime-sensor` | Go+eBPF |
| orca-unified | `orca-unified` | `~/src` | Python+Go |
| helm-charts | `Users-ilyabrykau-src-helm-charts` | `~/src/helm-charts` | YAML |
