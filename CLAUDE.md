# Orca Env Plugin — MANDATORY routing rules

You have three tool families. Use aliases — **CBM**, **Serena**, **CTX** — everywhere:

| Alias | Server | Key tools |
|-------|--------|-----------|
| **CBM** | codebase-memory-mcp | `search_code`, `search_graph`, `get_code_snippet`, `trace_path` |
| **Serena** | serena | `replace_symbol_body`, `replace_content`, `insert_after_symbol` |
| **CTX** | context-mode | `ctx_batch_execute` (primary), `ctx_search`, `ctx_execute`, `ctx_fetch_and_index`, `ctx_index` |

## Routing — MANDATORY

| Task | Use | Never |
|------|-----|-------|
| Explore source code (`.go .ts .py .c .h`) | **CBM** | Read / Glob / Grep / Bash cat |
| Edit source code | **Serena** (refs first) | Edit / Write / sed |
| Non-source research / shell output | **CTX** `ctx_batch_execute` | Bash >20 lines |
| Follow-up queries on indexed content | **CTX** `ctx_search` | re-running commands |
| Compute / parse / process data | **CTX** `ctx_execute` | pulling raw data into context |
| Fetch web pages / external docs | **CTX** `ctx_fetch_and_index` | WebFetch / curl / wget |
| Read non-source to then Edit | native `Read` | ctx_execute_file for analysis |
| Write any file | native `Write` / `Edit` | ctx_execute / Bash |

## Think in Code — MANDATORY

When you need to analyze, count, filter, or transform data: **write code** via CTX `ctx_execute(language, code)`. Do NOT pull raw output into context. Pure JS, Node built-ins only, always `try/catch`.

## Rules

- Serena edits: ALWAYS run `find_referencing_symbols` first — edit guard enforces this.
- `ctx_batch_execute`: provide descriptive `label` per command — labels become FTS5 search chunks.
- Bash: only for `git`, `mkdir`, `rm`, `mv`, short-output navigation.

## File writing policy

Native `Write` to create · native `Edit` to modify · Serena for source code.
Never `ctx_execute`, `ctx_execute_file`, or Bash to write files.

## Output

- Responses under 500 words.
- Artifacts to FILES — never inline. Return: file path + 1-line description.