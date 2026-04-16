---
name: docs
description: Library documentation lookup via Docs MCP server. Use for external library/framework docs (fastapi, pydantic, pytest, kafka, boto3, etc). NOT for code search — use Codanna for that.
---

# Docs MCP — Library Documentation

Use for external library documentation. NOT for searching orca project code (use Codanna for that).

## Search Indexed Docs

```python
# Search a specific library
mcp__docs__search_docs(
    library="fastapi",
    query="dependency injection middleware",
    limit=5
)

# Search with version constraint
mcp__docs__search_docs(
    library="pydantic",
    query="model validation",
    version="2.x",
    limit=5
)
```

## Fetch Any URL

```python
# Convert any web page to markdown
mcp__docs__fetch_url(
    url="https://docs.example.com/api/reference"
)
```

## Index New Library Docs

```python
# Scrape and index a library's documentation
mcp__docs__scrape_docs(
    library="confluent-kafka",
    url="https://docs.confluent.io/kafka-clients/python/current/overview.html",
    version="2.3"
)
```

## Check What's Indexed

```python
# List all indexed libraries
mcp__docs__list_libraries()

# Find specific version
mcp__docs__find_version(library="fastapi", targetVersion="0.100.x")
```

## When To Use

| Need | Tool |
|------|------|
| External library API | `search_docs` or `fetch_url` |
| Internal project docs | `mcp__codanna__semantic_search_docs` |
| Code search | Codanna — NOT Docs MCP |
