---
name: docs
description: Library documentation lookup via Docs MCP server. Use for external library/framework docs. NOT for code search — use codebase-memory-mcp for that.
---

# Docs MCP — Library Documentation

Use for external library documentation. NOT for searching project code (use codebase-memory-mcp for that).

## Search Indexed Docs

```
mcp__docs__search_docs(library="fastapi", query="dependency injection middleware", limit=5)
```

## Fetch Any URL

```
mcp__docs__fetch_url(url="https://docs.example.com/api/reference")
```

## Index New Library Docs

```
mcp__docs__scrape_docs(library="confluent-kafka", url="https://docs.confluent.io/...", version="2.3")
```

## Check What's Indexed

```
mcp__docs__list_libraries()
```

## When To Use

| Need | Tool |
|------|------|
| External library API | `mcp__docs__search_docs` or `mcp__docs__fetch_url` |
| Internal project code | `mcp__codebase-memory-mcp__search_code` — NOT Docs MCP |
