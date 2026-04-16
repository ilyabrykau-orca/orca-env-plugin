---
name: serena-workflow
description: Serena editing workflow — symbol-level editing, replace_content, memory management. Use for ALL code editing tasks in orca repos.
---

# Serena Editing Workflow

Native Edit/Write are HARD-BLOCKED on code files. Use Serena for all code editing.

## Mandatory Pre-Edit Checklist

Before ANY code edit:
1. `mcp__serena__find_referencing_symbols(name_path="target_symbol", relative_path="path/to/file.py")` — **`relative_path` must be a FILE, not a directory**
2. Review references — understand impact scope
3. Plan with TaskCreate: research → implement → verify
4. Get user approval

## Edit Tool Selection

| Situation | Tool |
|-----------|------|
| Replace entire function/class/method | `replace_symbol_body` |
| Edit few lines within a larger symbol | `replace_content` |
| Add new code after existing symbol | `insert_after_symbol` |
| Add new code before first symbol | `insert_before_symbol` |
| Rename across whole codebase | `rename_symbol` |

## A. replace_symbol_body

```python
mcp__serena__replace_symbol_body(
    name_path="MyClass/process_data",
    relative_path="orca/sensors/processor.py",
    body="def process_data(self, event):\n    return self.transform(event)"
)
```

Note: `body` is the implementation only — excludes docstrings and leading comments.

## B. replace_content

```python
# Literal replacement (exact string match)
mcp__serena__replace_content(
    relative_path="orca/config.py",
    needle="TIMEOUT = 30",
    repl="TIMEOUT = 60",
    mode="literal"
)

# Regex with wildcards (preferred — avoids quoting full text)
mcp__serena__replace_content(
    relative_path="orca/sensors/base.py",
    needle="def old_method\\(self\\).*?return result",
    repl="def new_method(self):\n    return self.compute()",
    mode="regex"
)

# Regex with backreferences — use $!1, $!2 (NOT \1, \2)
mcp__serena__replace_content(
    relative_path="orca/utils.py",
    needle="log\\(\"(.*?)\"\\)",
    repl="logger.info(\"$!1\")",
    mode="regex"
)
```

## C. Insert Code

```python
# After an existing symbol
mcp__serena__insert_after_symbol(
    name_path="existing_function",
    relative_path="orca/utils.py",
    body="\ndef new_function():\n    pass"
)

# Before an existing symbol (e.g. add imports at top of file)
mcp__serena__insert_before_symbol(
    name_path="first_class",
    relative_path="orca/models.py",
    body="import logging\n\nlogger = logging.getLogger(__name__)\n"
)
```

## D. Rename Across Codebase

```python
mcp__serena__rename_symbol(
    name_path="OldClassName",
    relative_path="orca/models.py",
    new_name="NewClassName"
)
```

## Reading Code

```python
# Read symbol with source (token-efficient — preferred)
mcp__serena__find_symbol(
    name_path_pattern="MyClass/my_method",
    include_body=True,
    relative_path="orca/sensors/"
)

# File overview — what symbols exist
mcp__serena__get_symbols_overview(
    relative_path="orca/sensors/base.py",
    depth=1
)

# Regex search across files
mcp__serena__search_for_pattern(
    substring_pattern="TODO|FIXME",
    paths_include_glob="**/*.py",
    relative_path="orca/"
)

# Read file range (0-based lines, end_line inclusive)
mcp__serena__read_file(
    relative_path="orca/sensors/base.py",
    start_line=0,
    end_line=49
)
```

## Memory

```python
# Save (memory_file_name — no .md extension needed)
mcp__serena__write_memory(
    memory_file_name="kafka_migration",
    content="# Kafka Migration\n\nDecision: use confluent-kafka..."
)

# Read
mcp__serena__read_memory(memory_file_name="cross_project_map")

# List all
mcp__serena__list_memories()

# Edit in place
mcp__serena__edit_memory(
    memory_file_name="kafka_migration",
    needle="confluent-kafka",
    repl="confluent-kafka-python",
    mode="literal"
)
```

## Key Gotchas

| Gotcha | Rule |
|--------|------|
| `find_referencing_symbols` path | Must be a **FILE**, not a directory |
| `replace_content` backrefs | `$!1`, `$!2` — NOT `\1`, `\2` |
| `replace_symbol_body` body | Implementation only — no docstrings/comments |
| `read_file` lines | 0-based; `end_line` is inclusive |
| `mode` values | Exactly `"literal"` or `"regex"` (lowercase) |
| Memory key | `memory_file_name` — NOT `memory_name`, `memory_file`, `name` |
| `find_symbol` param | `name_path_pattern` — NOT `name` or `symbol_name` |

## Wrong vs Right

| Wrong | Right |
|-------|-------|
| `find_referencing_symbols(symbol_name="Foo")` | `find_referencing_symbols(name_path="Foo", relative_path="orca/file.py")` |
| `write_memory(memory_file="x.md", ...)` | `write_memory(memory_file_name="x", ...)` |
| `read_memory(memory_file="cross_project_map.md")` | `read_memory(memory_file_name="cross_project_map")` |
| `find_symbol(name="Foo", include_body=True)` | `find_symbol(name_path_pattern="Foo", include_body=True)` |
