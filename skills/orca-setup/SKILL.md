---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## TOOL ENFORCEMENT ACTIVE

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` are **HARD-BLOCKED** on code files.
A PreToolUse hook returns deny if you attempt to use them. Use MCP tools instead.

Non-code files (.json, .yaml, .md, .toml, .cfg, .sh, Makefile, Dockerfile) → native tools allowed.

---

## Step 1: Activate Project

Execute immediately:

```
mcp__serena__activate_project(project=<detected-project>)
```

Then load memories:

```
mcp__serena__list_memories()
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Step 2: Tool Routing

### Search Code (codebase-memory-mcp)

```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase", label="class")
mcp__codebase-memory-mcp__search_code(pattern="kafka offset commit", file_pattern="*.py")
mcp__codebase-memory-mcp__get_code_snippet(qualified_name="orca.sensors.base.AbstractSensor")
mcp__codebase-memory-mcp__trace_path(function_name="process_event", mode="calls")
mcp__codebase-memory-mcp__get_architecture(aspects=["overview"])
```

### Read Code (Serena)

```
mcp__serena__find_symbol(name_path_pattern="AbstractSensor", include_body=True, relative_path="orca/sensors/")
mcp__serena__read_file(relative_path="orca/sensors/base.py", start_line=10, end_line=50)
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codebase-memory-mcp__search_graph(name_pattern="...")`
2. **Locate**: `mcp__codebase-memory-mcp__get_code_snippet(qualified_name="...")`
3. **Trace**: `mcp__serena__find_referencing_symbols(name_path="TargetFunc", relative_path="orca/module/file.py")` — **FILE path, not directory. MANDATORY before any edit.**
4. **Edit**: Serena tools (replace_symbol_body, replace_content, insert_after_symbol)
5. **Verify**: `pytest` / `go test`

### External Docs / Web

```
mcp__docs__search_docs(library="fastapi", query="dependency injection", limit=5)
mcp__exa__web_search_exa(query="Go 1.25 breaking changes")
```

---

## Step 3: Memory Protocol

At session start: `mcp__serena__list_memories()` → read relevant ones.

```
mcp__serena__write_memory(memory_file_name="kafka_migration", content="...")
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Projects

| Project | Path | Language |
|---------|------|----------|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

---

## Params Cheat Sheet

| Tool | Param | Correct | WRONG |
|------|-------|---------|-------|
| `search_graph` (CBM) | symbol name | `name_pattern` | `name`, `query` |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `name`, `symbol_id` |
| `trace_path` (CBM) | function | `function_name` + `mode` | `symbol_name` |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement` |
| `replace_content` | mode values | `"literal"` or `"regex"` | `True`, `false` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| All memory tools | key | `memory_file_name` | `memory_name`, `name` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |
