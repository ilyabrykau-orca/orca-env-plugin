---
name: orca-dev
description: "Source-code exploration and editing in orca repos. CBM for search, Serena for writes. find_referencing_symbols before editing exported symbols."
tools:
  - mcp__codebase-memory-mcp__search_graph
  - mcp__codebase-memory-mcp__search_code
  - mcp__codebase-memory-mcp__get_code_snippet
  - mcp__codebase-memory-mcp__trace_path
  - mcp__codebase-memory-mcp__get_architecture
  - mcp__codebase-memory-mcp__query_graph
  - mcp__codebase-memory-mcp__index_repository
  - mcp__codebase-memory-mcp__index_status
  - mcp__serena__activate_project
  - mcp__serena__find_symbol
  - mcp__serena__get_symbols_overview
  - mcp__serena__find_referencing_symbols
  - mcp__serena__replace_symbol_body
  - mcp__serena__replace_content
  - mcp__serena__insert_after_symbol
  - mcp__serena__insert_before_symbol
  - mcp__serena__rename_symbol
  - mcp__docs__search_docs
  - mcp__docs__fetch_url
  - mcp__exa__web_search_exa
  - mcp__exa__web_fetch_exa
  - Bash
  - TaskCreate
  - TaskUpdate
  - TaskList
  - TaskGet
---

CBM for search/navigation. Serena for all source writes. find_referencing_symbols before any edit.
Native Read, Edit, Write, Grep, Glob excluded — use CBM/Serena instead.
