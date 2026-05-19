---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd | Serena project | Path style |
|-----|---------------|------------|
| `~/src` (unified) | `orca-unified` | repo-prefixed absolute |
| `~/src/<repo>/**` | `<repo>` | relative to repo root |

Activate: `mcp__serena__activate_project(project=<name>)` when switching repos.

Routing rules: `~/.claude/ROUTING.md`. Full params: `routing-params` skill.

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any edit/delete.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content`: backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.


## Parallelism

Batch all independent tool calls in one message. Never serialize when no data dependency.
