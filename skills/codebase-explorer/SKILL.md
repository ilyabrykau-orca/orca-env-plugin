---
name: codebase-explorer
description: Source-code exploration via codebase-memory-mcp. Use for ALL code search, symbol lookup, call graphs, and impact analysis in orca repos.
---

# Codebase Explorer (codebase-memory-mcp)

Native Grep/Glob/Read are HARD-BLOCKED on code files. Use CBM for all code exploration.

## Tools Reference

| Tool | When | Key Params |
|------|------|-----------|
| `search_graph` | Find symbols by name/label/pattern | `name_pattern`, `label`, `qn_pattern` |
| `search_code` | Text search across indexed repos | `pattern`, `file_pattern` |
| `get_code_snippet` | Read source by qualified name | `qualified_name` |
| `trace_path` | Call chains and data flow | `function_name`, `mode` (calls/data_flow/cross_service) |
| `get_architecture` | Project structure overview | `aspects` |
| `query_graph` | Complex Cypher graph patterns | `query` |
| `index_repository` | Index a new repo | `path` |
| `index_status` | Check indexing status | |

## Common Patterns

### "How does authentication work?"
```
mcp__codebase-memory-mcp__search_code(pattern="auth", file_pattern="*.py")
mcp__codebase-memory-mcp__search_graph(name_pattern="auth")
```

### "Where is class SensorBase?"
```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase", label="class")
```

### "Who calls process_event?"
```
mcp__codebase-memory-mcp__trace_path(function_name="process_event", mode="calls")
```

### "What's the impact of changing SensorBase?"
```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase")
mcp__codebase-memory-mcp__trace_path(function_name="SensorBase", mode="calls")
```

### "Search project docs"
```
mcp__codebase-memory-mcp__search_code(pattern="deployment", file_pattern="*.md")
```
