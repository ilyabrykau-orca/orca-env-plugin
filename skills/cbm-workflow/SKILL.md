---
name: cbm-workflow
description: CBM code intelligence — search, symbol lookup, call graphs, architecture, performance analysis, memory optimization, allocation patterns. Use for ALL code search, understanding, and exploration tasks in orca repos. Triggers on explore, understand, find, analyze, performance, memory, allocation, hot path, benchmark, optimize, inefficiency, dead code, unused, refactor.
---

# CBM Workflow

## Quick-start

| Intent | Tool | Key params |
|--------|------|-----------|
| Text search | `search_code` | `pattern`, `project` (required) |
| Find symbol by name | `search_graph` | `MATCH (n) WHERE n.name='X' RETURN n`, `project` |
| Read symbol body | `get_code_snippet` | `qualified_name` |
| Architecture overview | `get_architecture` | `project` — start here for multi-symbol tasks |
| Trace call chain | `trace_path` | `source`, `target`, `project` |
| Who calls X | `search_graph` | `MATCH (c)-[:CALLS]->(n) WHERE n.name='X' RETURN c`, `project` |
| Impact radius | `query_graph` | `MATCH (n)-[*1..2]-(m) WHERE n.name='X' RETURN m`, `project` |

## Empty-result escalation (mandatory)

Before reaching for Serena, exhaust CBM in order:

1. **Verify project name** — `mcp__codebase-memory-mcp__list_projects()`. Wrong name = empty results every time.
2. **Broaden pattern** — drop `path_filter`; use concrete symbol names not file paths.
3. **Switch tool** — `search_code` empty? Try `search_graph` with a file filter. Still empty? Try `get_architecture(project=...)` to orient.
4. **Last resort only** (all 3 steps exhausted):
   - `mcp__serena__get_symbols_overview(relative_path="dir/")`
   - `mcp__serena__find_symbol(name_path_pattern="X", include_body=True, relative_path="dir/")`

   Reaching for Serena without trying steps 1–3 violates the routing contract.

## CBM project names

| Short | Pass to `project=` |
|-------|-------------------|
| orca | `Users-ilyabrykau-src-orca` |
| orca-sensor | `Users-ilyabrykau-src-orca-sensor` |
| orca-runtime-sensor | `Users-ilyabrykau-src-orca-runtime-sensor` |
| orca-unified | `orca-unified` |
| helm-charts | `Users-ilyabrykau-src-helm-charts` |

## Wrong / right

| Wrong | Right |
|-------|-------|
| `search_code(query="kafka")` | `search_code(pattern="kafka", project="...")` |
| `get_code_snippet(relative_path="x.py", start_line=10)` | `get_code_snippet(qualified_name="module::Class/method")` |
| `search_graph(query="...", ...)` (no `project`) | `search_graph(query="...", project="Users-ilyabrykau-src-orca")` |
| Serena `find_symbol` as first step | `search_code` or `search_graph` first; Serena only after escalation |
