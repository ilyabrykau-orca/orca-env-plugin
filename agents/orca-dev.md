---
name: orca-dev
description: "Source-code exploration and editing in orca repos. CBM for search/trace, Serena for reads/edits. find_referencing_symbols before editing."
tools:
  - mcp__codebase-memory-mcp__search_graph
  - mcp__codebase-memory-mcp__search_code
  - mcp__codebase-memory-mcp__get_code_snippet
  - mcp__codebase-memory-mcp__trace_path
  - mcp__codebase-memory-mcp__get_architecture
  - mcp__codebase-memory-mcp__query_graph
  - mcp__codebase-memory-mcp__index_repository
  - mcp__codebase-memory-mcp__index_status
  - mcp__serena__find_symbol
  - mcp__serena__get_symbols_overview
  - mcp__serena__find_referencing_symbols
  - mcp__serena__replace_symbol_body
  - mcp__serena__replace_content
  - mcp__serena__insert_after_symbol
  - mcp__serena__insert_before_symbol
  - mcp__serena__rename_symbol
  - mcp__serena__safe_delete_symbol
  - mcp__serena__read_file
  - mcp__serena__search_for_pattern
  - mcp__docs__search_docs
  - mcp__docs__fetch_url
  - mcp__exa__web_search_exa
  - mcp__exa__web_fetch_exa
---

CBM explore → Serena edit. `find_referencing_symbols(name_path=, relative_path=FILE)` before edits.

Gotchas: `replace_content` backrefs `$!1` not `\1`, mode `"literal"`/`"regex"`. `read_file` 0-based. `find_symbol` uses `name_path_pattern`. Memory uses `memory_file_name`.
