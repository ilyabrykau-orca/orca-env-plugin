# Orca Env Plugin — MANDATORY routing rules

## Tool families

| Alias | Namespace | Role |
|-------|-----------|------|
| **CBM** | `mcp__codebase-memory-mcp__*` | Source code exploration and reading — consult tool descriptions |
| **Serena** | `mcp__serena__*` | Source code WRITE only — call `find_referencing_symbols` first to trace impact |
| **CTX** | `mcp__plugin_context-mode_context-mode__*` | Non-source research, shell, web, compute — consult tool descriptions |

## Routing — MANDATORY

| Task | Use | Never |
|------|-----|-------|
| Explore / read source code (`.go .ts .py .c .h`) | **CBM** | Read / Glob / Grep / Bash cat / Serena read |
| Write source code | **Serena** — `find_referencing_symbols` first (traces impact), same turn | Edit / Write / sed |
| Non-source research / shell output | **CTX** | Bash >20 lines |
| Read non-source to then Edit | native `Read` | — |
| Write any non-source file | native `Write` / `Edit` | ctx_execute / Bash |

## Think in Code — MANDATORY

When you need to analyze, count, filter, or transform data: **write code** via CTX `ctx_execute(language, code)`. Do NOT pull raw output into context. Pure JS, Node built-ins only, always `try/catch`.

## Rules

- **Serena edits**: call `find_referencing_symbols` in the same turn before any write — hook blocks edits without it.
- **CBM / CTX**: consult tool descriptions; pick the tool that fits the task, not the default.
- **CTX `ctx_batch_execute`**: provide descriptive `label` per command — labels become FTS5 search chunks.
- **Bash**: only for `git`, `mkdir`, `rm`, `mv`, short-output navigation.

## File writing policy

Native `Write` to create · native `Edit` to modify · Serena WRITE for source code.
Never `ctx_execute`, `ctx_execute_file`, or Bash to write files.

## Output

- Responses under 500 words.
- Artifacts to FILES — never inline. Return: file path + 1-line description.