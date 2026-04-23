# Orca Env Plugin — MANDATORY routing rules

## Tool families

| Alias | Namespace | Tools |
|-------|-----------|-------|
| **CBM** | `mcp__codebase-memory-mcp__*` | Pick right tool per task: `search_code` (text), `search_graph` (structural), `get_code_snippet` (read), `trace_path` (calls), `get_architecture`, `query_graph`, `index_repository`, `detect_changes`, `get_graph_schema` |
| **Serena READ** | `mcp__serena__*` | `find_symbol`, `get_symbols_overview`, `read_file`, `find_referencing_symbols`, `search_for_pattern`, `find_file`, `list_dir` — use freely |
| **Serena WRITE** | `mcp__serena__*` | `replace_symbol_body`, `replace_content`, `insert_after_symbol`, `insert_before_symbol`, `rename_symbol`, `safe_delete_symbol` — **call `find_referencing_symbols` first** |
| **CTX** | `mcp__plugin_context-mode_context-mode__*` | Pick right tool: `ctx_batch_execute` (primary), `ctx_search`, `ctx_execute`, `ctx_execute_file`, `ctx_fetch_and_index`, `ctx_index` |

## Routing — MANDATORY

| Task | Use | Never |
|------|-----|-------|
| Explore source code (`.go .ts .py .c .h`) | **CBM** — pick right tool per task | Read / Glob / Grep / Bash cat |
| Read a source symbol or file | **Serena READ** | native Read on source |
| Edit / modify source code | **Serena WRITE** — refs first, same turn | Edit / Write / sed |
| Non-source research / shell output | **CTX** `ctx_batch_execute` | Bash >20 lines |
| Follow-up queries on indexed content | **CTX** `ctx_search` | re-running commands |
| Compute / parse / process data | **CTX** `ctx_execute` | pulling raw data into context |
| Fetch web pages / external docs | **CTX** `ctx_fetch_and_index` | WebFetch / curl / wget |
| Read non-source to then Edit | native `Read` | — |
| Write any non-source file | native `Write` / `Edit` | ctx_execute / Bash |

## Think in Code — MANDATORY

When you need to analyze, count, filter, or transform data: **write code** via CTX `ctx_execute(language, code)`. Do NOT pull raw output into context. Pure JS, Node built-ins only, always `try/catch`.

## Rules

- **Serena WRITE**: ALWAYS call `find_referencing_symbols` in the same turn before editing — hook blocks edits without it.
- **CBM**: Do not default to `search_code` — choose the tool that fits the question (structural → `search_graph`, call chain → `trace_path`, architecture → `get_architecture`).
- **CTX `ctx_batch_execute`**: provide descriptive `label` per command — labels become FTS5 search chunks.
- **Bash**: only for `git`, `mkdir`, `rm`, `mv`, short-output navigation.

## File writing policy

Native `Write` to create · native `Edit` to modify · Serena WRITE for source code.
Never `ctx_execute`, `ctx_execute_file`, or Bash to write files.

## Output

- Responses under 500 words.
- Artifacts to FILES — never inline. Return: file path + 1-line description.