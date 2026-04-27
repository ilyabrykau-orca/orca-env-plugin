# orca-env-plugin

Claude Code plugin: enforced tool routing for orca repos, Serena workspace activation, session analytics.

<tool_routing>
Routing enforced by PreToolUse hooks + permissions.deny + PostToolBatch audit.
Source prefix: ~/src (orca, orca-sensor, orca-runtime-sensor, orca-cloud-platform, helm-charts, grafana-provisioning).

## Source files (.go .ts .tsx .py .rs)

Read / search / navigate: `mcp__codebase-memory-mcp__*`.
Use search_code, get_code_snippet, search_graph, trace_path, get_architecture, query_graph.
Never use Read, Grep, or Glob on source files. Use mcp__codebase-memory-mcp__search_code instead.

Write / edit / refactor: `mcp__serena__*`.
Call find_referencing_symbols(name_path=…, relative_path=…) FIRST in the same turn — a hook rejects edits without it.
Never use Edit, Write, or MultiEdit on source files. Use mcp__serena__replace_symbol_body or replace_content instead.

## Non-source (.md .json .yaml .toml configs)

Native Read, Edit, Write.

## Shell

Bash only. rtk auto-rewrites commands for token savings (transparent, no action needed).

## Exempt paths

vendor/, third_party/, generated/, node_modules/, dist/, build/ — native tools permitted.
</tool_routing>

## Execution contract

No clarifying turns. State assumption, proceed, verify.
Batch independent tool calls in one message.
Responses ≤500 words. Write artifacts to files.

## Commands

- Build binary: `bash build.sh`
- Hook tests (static + unit): `python ~/.claude/skills/md-generator/scripts/run_plugin_tests.py . --static --unit`
- TypeScript tests: `bun test`
- Typecheck: `bun run --bun tsc --noEmit`

## Structure

- `src/` — TypeScript source (session analytics binary: Stop/SubagentStop)
- `hooks/` — enforcement scripts + hooks.json
- `skills/orca-dev/` — orca-dev skill
- `agents/orca-dev.md` — workflow subagent (CBM + Serena only, no native source tools)
- `dist/` — compiled Bun binary
- `tests/` — hook unit tests, fixtures, e2e evals
