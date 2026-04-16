---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, Codanna/Serena patterns, memory protocol.
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
# Broad "how does X work?" — returns docs + callers + calls
mcp__codanna__semantic_search_with_context(query="how does kafka offset commit work", lang="python", limit=5)

# Exact symbol lookup by name
mcp__codanna__find_symbol(name="AbstractSensor", lang="python", kind="class")

# Fuzzy search with filters
mcp__codanna__search_symbols(query="sensor", kind="class", lang="python", limit=10)
```

### Read Code

```python
# Read symbol with body (preferred — token efficient)
mcp__serena__find_symbol(name_path_pattern="AbstractSensor", include_body=True, relative_path="orca/sensors/")

# Read file range
mcp__serena__read_file(relative_path="orca/sensors/base.py", start_line=10, end_line=50)
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codanna__semantic_search_with_context(query="...")`
2. **Locate**: `mcp__codanna__find_symbol(name="...", lang="...")`
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
mcp__codanna__find_callers(function_name="process_event")

# What does this call?
mcp__codanna__get_calls(function_name="handle_request")

# Full impact before risky refactor
mcp__codanna__analyze_impact(symbol_name="SensorBase", max_depth=3)
```

### Library Documentation

```python
mcp__docs__search_docs(library="fastapi", query="dependency injection", limit=5)
mcp__docs__fetch_url(url="https://docs.example.com/api")
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

Copy-paste correct parameter names. No aliases work.

| Tool | Param | Correct | WRONG (do not use) |
|------|-------|---------|---------------------|
| `find_symbol` (Codanna) | language | `lang` | `language` |
| `search_symbols` | language | `lang` | `language` |
| `semantic_search_with_context` | language | `lang` | `language` |
| `find_callers` | symbol | `function_name` | `symbol_id` |
| `get_calls` | symbol | `function_name` | `symbol_id`, `depth` |
| `analyze_impact` | symbol | `symbol_name` | `symbol_id` |
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
