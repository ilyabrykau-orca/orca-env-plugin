---
name: docs
description: Library documentation lookup via Docs MCP server. Use for external library/framework docs. NOT for code search — use codebase-memory-mcp for that.
---

# Docs MCP — Library Documentation

Use for external library documentation. NOT for searching orca project code (use codebase-memory-mcp for that).

## Search Indexed Docs

```python
mcp__docs__search_docs(library="fastapi", query="dependency injection middleware", limit=5)
mcp__docs__search_docs(library="pydantic", query="model validation", version="2.x", limit=5)
```

## Fetch Any URL

```python
mcp__docs__fetch_url(url="https://docs.example.com/api/reference")
```

## When To Use

| Need | Tool |
|------|------|
| External library API | `search_docs` or `fetch_url` |
| Internal project docs | native `Read` or project docs |
| Code search | codebase-memory-mcp — NOT Docs MCP |
