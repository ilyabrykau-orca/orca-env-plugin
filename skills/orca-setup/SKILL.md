---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## TOOL ENFORCEMENT ACTIVE

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` are **HARD-BLOCKED** on code files (.py, .go, .ts, .tsx, .js, .jsx, .rs, .cpp, .c, .h, .hpp, .rb, .java).
A PreToolUse hook returns exit 2 if you attempt to use them. Use MCP tools instead.

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

### Search Code

```python
# Text search ranked by structural importance
mcp__codebase-memory-mcp__search_code(pattern="kafka offset commit", project="orca")

# Find symbol by name (structural query)
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n) WHERE n.name = 'AbstractSensor' RETURN n",
    project="orca"
)

# Full architecture overview — start here for multi-symbol exploration
mcp__codebase-memory-mcp__get_architecture(project="orca")
```

### Read Code

```python
# Read symbol source by qualified name (preferred — token efficient)
mcp__codebase-memory-mcp__get_code_snippet(
    qualified_name="orca.sensors.base::AbstractSensor"
)

# Pre-edit read via Serena (when you need the symbol for editing next)
mcp__serena__find_symbol(name_path_pattern="AbstractSensor", include_body=True, relative_path="orca/sensors/")
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codebase-memory-mcp__search_code(pattern="...")`
2. **Locate**: `mcp__codebase-memory-mcp__search_graph(query="MATCH (n) WHERE n.name = '...' RETURN n")`
3. **Trace**: `mcp__serena__find_referencing_symbols(name_path="TargetFunc", relative_path="orca/module/file.py")` — **FILE path, not directory. MANDATORY before any edit.**
4. **Plan**: TaskCreate with research → implement → verify
5. **Edit**: Serena tools (see below)
6. **Verify**: `pytest` / `go test`

### Edit Tools

```python
# Replace entire function/class (safest)
mcp__serena__replace_symbol_body(
    name_path="MyClass/process_data",
    relative_path="orca/sensors/processor.py",
    body="def process_data(self, event):\n    return self.transform(event)"
)

# Targeted literal edit
mcp__serena__replace_content(
    relative_path="orca/config.py",
    needle="TIMEOUT = 30",
    repl="TIMEOUT = 60",
    mode="literal"
)

# Regex edit — backreferences use $!1, $!2 (NOT \1, \2)
mcp__serena__replace_content(
    relative_path="orca/sensors/base.py",
    needle="log\\(\"(.*?)\"\\)",
    repl="logger.info(\"$!1\")",
    mode="regex"
)

# Insert after existing symbol
mcp__serena__insert_after_symbol(
    name_path="existing_function",
    relative_path="orca/utils.py",
    body="\ndef new_function():\n    pass"
)
```

### Call Graph

```python
# Who calls this? (use before modifying shared code)
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (caller)-[:CALLS]->(n) WHERE n.name = 'process_event' RETURN caller",
    project="orca"
)

# What does this call?
mcp__codebase-memory-mcp__search_graph(
    query="MATCH (n)-[:CALLS]->(callee) WHERE n.name = 'handle_request' RETURN callee",
    project="orca"
)

# Full impact before risky refactor
mcp__codebase-memory-mcp__query_graph(
    query="MATCH (n)-[*1..3]-(m) WHERE n.name='SensorBase' RETURN m",
    project="orca"
)
```

---

## Step 3: Memory Protocol

At session start: `mcp__serena__list_memories()` → read relevant ones.

```python
mcp__serena__write_memory(
    memory_file_name="kafka_migration",
    content="# Kafka Migration\n\nDecision: use confluent-kafka..."
)
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

| Tool | Param | Correct | WRONG (do not use) |
|------|-------|---------|---------------------|
| `search_code` (CBM) | text | `pattern` | `query` |
| `search_code` (CBM) | scope | `project` | (omitting it) |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `relative_path` + `start_line` |
| `search_graph` (CBM) | scope | `project` | (omitting it) |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement`, `is_regex` |
| `replace_content` | mode values | `"literal"` or `"regex"` | `True`, `false`, `"regexp"` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| All memory tools | key | `memory_file_name` | `memory_name`, `memory_file`, `name` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |

---

## Verification

Show actual command output before claiming done:
- Python: `pytest <path> -v`
- Go: `go test ./...`
- Lint: `ruff check .` / `golangci-lint run`
