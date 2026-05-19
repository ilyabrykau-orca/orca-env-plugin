---
name: serena-workflow
description: Serena editing workflow — symbol-level editing, replace_content, memory management. Use for ALL code editing tasks in orca repos.
---

# Serena Editing Workflow

## Pre-edit checklist (mandatory)

Before ANY code edit:
1. `mcp__serena__find_referencing_symbols(name_path="target", relative_path="path/to/file.py")` — `relative_path` must be a FILE, not a directory
2. Review references — understand impact scope
3. Plan with TaskCreate

## Edit tool selector

| Situation | Tool |
|-----------|------|
| Replace entire function/class/method | `replace_symbol_body` |
| Edit lines within a symbol | `replace_content` |
| Add code after existing symbol | `insert_after_symbol` |
| Add code before first symbol | `insert_before_symbol` |
| Rename across codebase | `rename_symbol` |
| Delete a symbol | `safe_delete_symbol` |

## A. replace_symbol_body

```python
mcp__serena__replace_symbol_body(
    name_path="MyClass/process_data",
    relative_path="orca/sensors/processor.py",
    body="def process_data(self, event):\n    return self.transform(event)"
)
```

`body` is implementation only — no docstrings or leading comments.

## B. replace_content

```python
# Literal
mcp__serena__replace_content(
    relative_path="orca/config.py",
    needle="TIMEOUT = 30",
    repl="TIMEOUT = 60",
    mode="literal"
)

# Regex — backrefs use $!1 not \1
mcp__serena__replace_content(
    relative_path="orca/sensors/base.py",
    needle="log\\(\"(.*?)\"\\)",
    repl="logger.info(\"$!1\")",
    mode="regex"
)
```

## C. Insert

```python
mcp__serena__insert_after_symbol(
    name_path="existing_function",
    relative_path="orca/utils.py",
    body="\ndef new_function():\n    pass"
)

mcp__serena__insert_before_symbol(
    name_path="first_class",
    relative_path="orca/models.py",
    body="import logging\n\nlogger = logging.getLogger(__name__)\n"
)
```

## D. Rename

```python
mcp__serena__rename_symbol(
    name_path="OldClassName",
    relative_path="orca/models.py",
    new_name="NewClassName"
)
```

## Gotchas

| Gotcha | Rule |
|--------|------|
| `find_referencing_symbols` path | Must be a FILE, not a directory |
| `replace_content` backrefs | `$!1`, `$!2` — NOT `\1`, `\2` |
| `replace_symbol_body` body | Implementation only — no docstrings/comments |

| `mode` values | Exactly `"literal"` or `"regex"` (lowercase) |
| `find_symbol` param | `name_path_pattern` — NOT `name` or `symbol_name` |

## Wrong / right

| Wrong | Right |
|-------|-------|
| `find_referencing_symbols(symbol_name="Foo")` | `find_referencing_symbols(name_path="Foo", relative_path="orca/file.py")` |
| `find_symbol(name="Foo", include_body=True)` | `find_symbol(name_path_pattern="Foo", include_body=True)` |
| `replace_content(mode="regexp")` | `replace_content(mode="regex")` |
