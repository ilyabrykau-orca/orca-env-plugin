---
name: cbm-workflow
description: CBM code intelligence — search, symbol lookup, call graphs, architecture, performance analysis, memory optimization, allocation patterns. Use for ALL code search, understanding, and exploration tasks in orca repos. Triggers on explore, understand, find, analyze, performance, memory, allocation, hot path, benchmark, optimize, inefficiency, dead code, unused, refactor.
---

# CBM Code Intelligence

Native Grep/Glob are HARD-BLOCKED on code files. Use CBM for all code search.

**NEVER use Serena's find_symbol or get_symbols_overview as the first exploration step. Always start with CBM.**

## Quick Start — Pick Your Intent

| "I want to..." | Tool | Key Params |
|---|---|---|
| Search code by text | `search_code` | `pattern`, `project` |
| Find a symbol by name | `search_graph` | query with symbol name |
| Read a symbol's source | `get_code_snippet` | `qualified_name` |
| Trace a call chain | `trace_path` | `source`, `target`, `project` |
| Get architecture overview | `get_architecture` | `project` |
| Find all references | `search_graph` | query for edges |

## When CBM Returns Empty — MANDATORY Recovery

If any CBM call returns empty results (`"results":[]`, `0 results`, `No symbols found`, or a project-not-found error), you MUST follow this escalation ladder. Do NOT fall back to Serena reads.

### Step 1: Verify the project name

Project names in CBM use the full path form, not short names:
- WRONG: `project="orca-runtime-sensor"`
- RIGHT: `project="Users-ilyabrykau-src-orca-runtime-sensor"`

Run `mcp__codebase-memory-mcp__list_projects()` to discover the correct name.

### Step 2: Broaden the search pattern

Drop `path_filter` first. Then make the pattern shorter or use a single concrete keyword:
- WRONG: `pattern="containermonitor allocation hot path"` (too abstract)
- RIGHT: `pattern="ContainerMonitor"` (matches a real symbol name)
- RIGHT: `pattern="func.*Monitor"` (regex matching)

### Step 3: Switch CBM tools

If `search_code` returns empty, try these alternatives:
```python
# Get full module overview — best for "what's in this package?"
mcp__codebase-memory-mcp__get_architecture(project="Users-ilyabrykau-src-orca-runtime-sensor")

# Find by symbol name structure
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.file CONTAINS 'containermonitor' RETURN n.name, n.qualified_name",
    project="Users-ilyabrykau-src-orca-runtime-sensor"
)

# Direct snippet if you know/guess the qualified name
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="pkg/containermonitor::ContainerMonitor"
)
```

### Step 4: Last resort (only after exhausting CBM)

Only when ALL CBM avenues above have been tried and returned empty:
- `mcp__serena__get_symbols_overview` for file structure
- `mcp__serena__find_symbol` for specific symbol reads

These are LAST RESORTS, not first reaches. If you use them without trying Steps 1-3, you are violating the routing contract.

## Project Names — Full Reference

| Short name | CBM indexed name |
|---|---|
| orca | Users-ilyabrykau-src-orca |
| orca-runtime-sensor | Users-ilyabrykau-src-orca-runtime-sensor |
| orca-sensor | Users-ilyabrykau-src-orca-sensor |
| orca-cloud-platform | Users-ilyabrykau-src-orca-cloud-platform |
| helm-charts | Users-ilyabrykau-src-helm-charts |
| grafana-provisioning | Users-ilyabrykau-src-grafana-provisioning |
| orca-env-plugin | Users-ilyabrykau-src-orca-env-plugin |

## Common Patterns

### "How does authentication work?"

```python
mcp__codebase-memory-mcp__search_code(
    pattern="authentication",
    project="Users-ilyabrykau-src-orca"
)
```

### "Where is class SensorBase?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'SensorBase' RETURN n",
    project="Users-ilyabrykau-src-orca"
)
```

### "Read the source of process_event"

```python
# Step 1: find qualified name
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'process_event' RETURN n.qualified_name",
    project="Users-ilyabrykau-src-orca"
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
    project="Users-ilyabrykau-src-orca"
)
```

### "What does process_event call?"

```python
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n)-[:CALLS]->(callee) WHERE n.name = 'process_event' RETURN callee.name, callee.file",
    project="Users-ilyabrykau-src-orca"
)
```

### "Show me the full architecture"

```python
mcp__codebase-memory-mcp__get_architecture(project="Users-ilyabrykau-src-orca")
```

### "Trace from ingest to storage"

```python
mcp__codebase-memory-mcp__trace_path(
    source="ingest_event",
    target="store_result",
    project="Users-ilyabrykau-src-orca"
)
```

## Progressive Disclosure — Power Queries

For complex queries beyond the recipes above, use `query_graph` with Cypher:

### Multi-hop: "What does X call that also calls Y?"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (a)-[:CALLS]->(b)-[:CALLS]->(c) WHERE a.name='X' AND c.name='Y' RETURN b",
    project="Users-ilyabrykau-src-orca"
)
```

### Impact radius: "Everything within 2 hops of SensorBase"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n)-[*1..2]-(m) WHERE n.name='SensorBase' RETURN m",
    project="Users-ilyabrykau-src-orca"
)
```

### Unused exports: "Functions defined but never called"

```python
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n:Function) WHERE NOT ()-[:CALLS]->(n) RETURN n.name, n.file",
    project="Users-ilyabrykau-src-orca"
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
- `project` is required on all CBM calls — use the FULL path form from the table above

## Wrong vs Right

| Wrong | Right |
|---|---|
| `get_code_snippet(relative_path="x.py", start_line=10)` | `get_code_snippet(qualified_name="module::func")` |
| `search_code(query="foo")` | `search_code(pattern="foo", project="Users-ilyabrykau-src-orca")` |
| `search_code(project="orca-runtime-sensor")` | `search_code(project="Users-ilyabrykau-src-orca-runtime-sensor")` |
| Using native Grep for code search | `search_code(pattern=..., project=...)` |
| Manual grep for callers | `search_graph` with CALLS edge query |
| CBM call without `project` param | Always include `project="Users-ilyabrykau-src-..."` |
| CBM empty → Serena find_symbol | CBM empty → list_projects → retry CBM → get_architecture |
| Serena find_symbol as first exploration | CBM search_code or get_architecture first |
