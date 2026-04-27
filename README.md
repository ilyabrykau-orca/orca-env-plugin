# orca-env-plugin

**v6.0.0** — Enforced tool routing for orca repos, Serena workspace activation, session analytics.

## What it does

- **Blocks** native Read, Edit, Write, Grep, Glob on source files under `~/src` via PreToolUse hooks + `permissions.deny`
- **Routes** source reads/searches to `mcp__codebase-memory-mcp__*` (~120x token savings)
- **Routes** source writes to `mcp__serena__*` (always after `find_referencing_symbols`)
- **Rewrites** Bash commands through `rtk` for token savings (transparent)
- **Audits** every tool batch; surfaces escapes to the model via `decision: block`
- **Records** Serena activation + workspace detection on session start
- **Logs** session statistics (tokens, tools, duration) on stop

## What's enforced and what isn't

Three independent enforcement layers:

1. **PreToolUse `permissionDecision: deny` + exit 2** — gives Claude actionable feedback via `permissionDecisionReason`
2. **`permissions.deny` in settings.json** — declarative deny; survives hook bypass cases
3. **`PostToolBatch` audit** — catches escapes after the batch resolves; blocks next turn

Known Claude Code issues ([#37210](https://github.com/anthropics/claude-code/issues/37210), [#33106](https://github.com/anthropics/claude-code/issues/33106)) can let `Edit` and MCP-tool calls slip through layer 1. Layer 2 still blocks in those cases. If both fail, layer 3 surfaces the violation. None is airtight alone; together they hold.

## Installation

```bash
/plugin install ./path/to/orca-env-plugin
```

## Build

```bash
# Rebuild the session-analytics binary (Stop/SubagentStop hooks)
bash build.sh

# Run hook tests
python3 ~/.claude/skills/md-generator/scripts/run_plugin_tests.py . --static --unit

# TypeScript unit tests
bun test
```

## Override

To bypass a deny for a one-off task, add to `.claude/settings.local.json`:

```json
{"permissions": {"allow": ["Edit(/path/to/specific/file.go)"]}}
```

Never push `settings.local.json` to source control.

## Version history

- **v6.0.0** — Full routing enforcement: PreToolUse deny hooks, permissions.deny, PostToolBatch audit, test scaffold, SessionStart split for compact
- **v5.0.0** — Advisory routing (broken: no enforcement hooks)
