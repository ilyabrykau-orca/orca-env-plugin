---
name: codanna
description: Codanna code intelligence — search, symbol lookup, call graphs, impact analysis. Use for ALL code search and understanding tasks in orca repos.
---

# Codanna Code Intelligence

Native Grep/Glob are HARD-BLOCKED on code files. Use Codanna for all code search.

## Tools Reference

| Tool | When | Key Params |
|------|------|-----------|
| `semantic_search_with_context` | "How does X work?" | `query`, `lang`, `limit`, `threshold` |
| `find_symbol` | "Where is class Y?" | `name`, `lang`, `kind` |
| `search_symbols` | Fuzzy name search | `query`, `lang`, `kind`, `limit` |
| `find_callers` | Who calls this? | `function_name` |
| `get_calls` | What does this call? | `function_name` |
| `analyze_impact` | Full dependency graph | `symbol_name`, `max_depth` |
| `semantic_search_docs` | Search markdown docs | `query`, `limit` |
| `search_documents` | Keyword doc search | `query`, `limit` |

## Common Patterns

### "How does authentication work?"
```python
mcp__codanna__semantic_search_with_context(
    query="how does user authentication flow work",
    lang="python",
    limit=5
)
```

### "Where is class SensorBase?"
```python
mcp__codanna__find_symbol(
    name="SensorBase",
    lang="python",
    kind="class"
)
```

### "Find all Go interfaces with 'Agent'"
```python
mcp__codanna__search_symbols(
    query="Agent",
    lang="go",
    kind="interface",
    limit=10
)
```

### "Who calls process_event?"
```python
# Step 1: locate (may return multiple — use symbol_id for precision in follow-ups)
mcp__codanna__find_symbol(name="process_event", lang="python")

# Step 2: get callers
mcp__codanna__find_callers(function_name="process_event")
```

### "What does handle_request call?"
```python
mcp__codanna__get_calls(function_name="handle_request")
```

### "What's the impact of changing SensorBase?"
```python
mcp__codanna__analyze_impact(
    symbol_name="SensorBase",
    max_depth=3
)
```

### "Search project docs for deployment"
```python
mcp__codanna__semantic_search_docs(
    query="deployment process and configuration",
    limit=5
)
```

## Tips

- `lang` not `language` — always
- When `find_symbol` returns multiple matches, use `symbol_id` for precise `find_callers`/`get_calls` follow-up
- `semantic_search_with_context` returns callers+calls+docs — most complete, use for broad questions
- `analyze_impact` with `max_depth=3` is safe; 4+ can return very large responses
- Raise `threshold` to 0.75 for high-precision semantic search (default 0.60)

## Wrong vs Right

| Wrong | Right |
|-------|-------|
| `find_symbol(name="Foo", language="go")` | `find_symbol(name="Foo", lang="go")` |
| `find_callers(symbol_id="abc123")` | `find_callers(function_name="process_event")` |
| `get_calls(symbol_id="abc", depth=2)` | `get_calls(function_name="handle_request")` |
| `analyze_impact(symbol_id="abc")` | `analyze_impact(symbol_name="SensorBase")` |
