---
name: cbm-workflow
description: CBM code intelligence — search, symbol lookup, call graphs, architecture. Use for ALL code search and understanding tasks in orca repos.
---

# CBM Code Intelligence

Native Grep/Glob are HARD-BLOCKED on code files. Use CBM for all code search.

## Quick Start — Pick Your Intent

| "I want to..." | Tool | Key Params |
|---|---|---|
| Search code by text | `search_code` | `pattern`, `project` |
| Find a symbol by name | `search_graph` | query with symbol name |
| Read a symbol's source | `get_code_snippet` | `qualified_name` |
| Trace a call chain | `trace_path` | `source`, `target`, `project` |
| Get architecture overview | `get_architecture` | `project` |
| Find all references | `search_graph` | query for edges |

## Common Patterns

### "How does authentication work?"

```python
mcp__codebase-memory-mcp__search_code(
    pattern="authentication",
    project="orca"
)
```

### "Where is class SensorBase?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'SensorBase' RETURN n",
    project="orca"
)
```

### "Read the source of process_event"

```python
# Step 1: find qualified name
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'process_event' RETURN n.qualified_name",
    project="orca"
)

# Step 2: read source by qualified name
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="orca.sensors.base::process_event"
)
```

### "Who calls handle_request?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (caller)-[:CALLS]->(n) WHERE n.name = 'handle_request' RETURN caller.name, caller.file",
    project="orca"
)
```

### "What does process_event call?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n)-[:CALLS]->(callee) WHERE n.name = 'process_event' RETURN callee.name, callee.file",
    project="orca"
)
```

### "Show me the full architecture"

```python
mcp__codebase-memory-mcp__get_architecture(project="orca")
```

### "Trace from ingest to storage"

```python
mcp__codebase-memory-mcp__trace_path(
    source="ingest_event",
    target="store_result",
    project="orca"
)
```

## Progressive Disclosure — Power Queries

For complex queries beyond the recipes above, use `query_graph` with Cypher:

### Multi-hop: "What does X call that also calls Y?"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (a)-[:CALLS]->(b)-[:CALLS]->(c) WHERE a.name='X' AND c.name='Y' RETURN b",
    project="orca"
)
```

### Impact radius: "Everything within 2 hops of SensorBase"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n)-[*1..2]-(m) WHERE n.name='SensorBase' RETURN m",
    project="orca"
)
```

### Unused exports: "Functions defined but never called"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n:Function) WHERE NOT ()-[:CALLS]->(n) RETURN n.name, n.file",
    project="orca"
)
```

## Edge Types Reference

| Edge | Meaning |
|---|---|
| CALLS | function/method invocation |
| IMPORTS | module/package import |
| DEFINES | file/module defines symbol |
| INHERITS | class inheritance |
| IMPLEMENTS | interface implementation |

## Tips

- Always start with `get_architecture` for multi-symbol exploration — one call replaces 4-6 round-trips
- `search_code` for text matching, `search_graph` for structural queries
- `get_code_snippet(qualified_name=...)` is direct — never use the `relative_path`+`start_line` form
- `path_filter` regex narrows scope (e.g. `^src/`)
- `project` is required on all CBM calls

## Wrong vs Right

| Wrong | Right |
|---|---|
| `get_code_snippet(relative_path="x.py", start_line=10)` | `get_code_snippet(qualified_name="module::func")` |
| `search_code(query="foo")` | `search_code(pattern="foo", project="orca")` |
| Using native Grep for code search | `search_code(pattern=..., project=...)` |
| Manual grep for callers | `search_graph` with CALLS edge query |
| CBM call without `project` param | Always include `project="orca"` (or correct project) |
