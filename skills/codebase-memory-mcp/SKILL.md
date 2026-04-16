---
name: codebase-memory-mcp
description: codebase-memory-mcp code intelligence — graph search, symbol lookup, call graphs, architecture, and indexed grep. Use for ALL code search and understanding tasks in orca repos.
---

# codebase-memory-mcp Code Intelligence

Native Grep/Glob/Search are HARD-BLOCKED for this workflow. Use codebase-memory-mcp for indexed code search and Serena for symbolic edits.

## Core loop

1. `mcp__codebase-memory-mcp__search_graph(...)` — discover symbols/files
2. `mcp__codebase-memory-mcp__get_code_snippet(...)` — read exact symbol body by qualified name
3. `mcp__codebase-memory-mcp__trace_call_path(...)` — inspect callers/callees
4. `mcp__serena__find_referencing_symbols(...)` — confirm downstream impact before edits
5. `mcp__serena__replace_symbol_body(...)` or `mcp__serena__replace_content(...)`

## Common patterns

```python
# Find handlers or symbols by name
mcp__codebase-memory-mcp__search_graph(
    project="orca-runtime-sensor",
    label="Function",
    name_pattern=".*ProcessHTTP.*",
    limit=10
)

# Grep-like search inside indexed files
mcp__codebase-memory-mcp__search_code(
    project="orca-runtime-sensor",
    pattern="Content-Type",
    limit=20
)

# Read source by qualified name (discover with search_graph first)
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="orca-runtime-sensor.pkg.http.ProcessHTTP1Data"
)

# Call graph traversal
mcp__codebase-memory-mcp__trace_call_path(
    project="orca-runtime-sensor",
    function_name="ProcessHTTP1Data",
    direction="inbound",
    max_depth=3
)

# Architecture overview
mcp__codebase-memory-mcp__get_architecture(
    project="orca-runtime-sensor",
    aspects=["languages", "packages", "hotspots", "layers"]
)
```

## Wrong vs right

| Wrong | Right |
|---|---|
| Native `Grep` on code | `mcp__codebase-memory-mcp__search_code(...)` |
| Native `Glob` for symbol hunt | `mcp__codebase-memory-mcp__search_graph(...)` |
| Native `Read` on a large source file | `search_graph` -> `get_code_snippet` |
| Edit code with `Write` | Serena symbolic edit tools |

## Notes

- Use `project=` when multiple repos are indexed to avoid cross-project noise.
- `get_code_snippet` requires a qualified name; use `search_graph` first.
- If the repo is not indexed yet, call `mcp__codebase-memory-mcp__index_repository(repo_path="/absolute/path")` or `index_status` / `list_projects` first.


## Editing handoff to Serena

```python
mcp__serena__replace_content(
    relative_path="orca-runtime-sensor/pkg/http/protocol.go",
    needle="old_text",
    repl="new_text",
    mode="literal"
)
```
