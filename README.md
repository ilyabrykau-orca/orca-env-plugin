# orca-env-plugin

Orca-specific Claude Code plugin: MCP routing enforcement, caveman mode persistence, workspace detection, and SQLite session audit. Designed for the `~/src` orca workspace layout.

Blocks native Read/Edit/Grep on code files → routes to MCP alternatives ([codebase-memory-mcp](https://github.com/orcasecurity/codebase-memory-mcp) for search, [Serena](https://github.com/oraios/serena) for edits).

Optional: co-install [`claude-mem`](https://github.com/thedotmack/claude-mem) (`npx claude-mem install`) for memory/history search on `:37777`. Plugin degrades gracefully if worker is absent.

## Routing

| Native tool | Blocked on | Routed to |
|---|---|---|
| `Read` | Code files (.py, .go, .ts, .rs, ...) | `mcp__serena__find_symbol` / `mcp__serena__read_file` |
| `Edit` / `Write` | Code files | `mcp__serena__replace_symbol_body` / `mcp__serena__replace_content` |
| `Grep` | All files | `mcp__codanna__semantic_search_with_context` |
| `Glob` | All files | `mcp__codanna__search_symbols` |

Non-code files (.json, .yaml, .md, .toml) pass through.

### Extra features
- **Serena edit guard** — warns on edit w/o `find_referencing_symbols`
- **Project detection** — auto-detects workspace, injects Serena activation
- **Skill activation** — suggests skills by prompt keywords
- **Session analytics** — token usage, tool distribution, costs

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI
- [Codanna](https://github.com/bartolli/codanna) at `https://localhost:8443/mcp`
- [Serena](https://github.com/aorwall/serena) at `http://127.0.0.1:8765/mcp`
- `jq` (`brew install jq`)

## Install

```bash
# Register marketplace (one-time)
claude plugin marketplace add orca-sensor-marketplace ilyabrykau-orca/orca-sensor-marketplace

# Install plugin
claude plugin install claude-toolkit@orca-sensor-marketplace
```

Or from repo:

```bash
claude plugin install --from-repo ilyabrykau-orca/claude-toolkit
```

## Structure

```
hooks/
  pre-tool-router       ← bash: native blocking + Serena edit guard (~10ms)
  post-serena-refs      ← bash: tracks reference-traced files
  skill-activation-prompt ← bash: keyword matching for skill suggestions
  session-start         ← bash: project detection + context injection
  stop.js               ← node: session analytics (once per session)
  subagent-stop.js      ← node: subagent analytics
  utils/transcript-parser.js

skills/
  codanna/SKILL.md      ← Codanna API patterns, wrong-vs-right table
  orca-setup/SKILL.md   ← workspace routing rules, build commands
  serena-workflow/SKILL.md ← Serena editing protocol
  docs/SKILL.md         ← Docs MCP usage
  skill-rules.json      ← keyword triggers for skill activation

tests/
  run-all.sh            ← unified runner (--unit / --integration)
  unit/                 ← 11 test files
  integration/          ← integration tests + prompts
```

## Hook Latency

| Hook | Latency | Frequency |
|---|---|---|
| `pre-tool-router` | ~10ms | Every tool call |
| `post-serena-refs` | ~12ms | After `find_referencing_symbols` |
| `skill-activation-prompt` | ~8ms | Per user message |
| `session-start` | ~11ms | Per session |
| `stop.js` | ~70ms | Once at session end |

## Testing

```bash
# Run all unit tests
bash tests/run-all.sh --unit

# Run with verbose output
bash tests/run-all.sh --unit --verbose
```

## Config

### Project detection

`session-start` hook detects workspace from `$PWD`:

| Path pattern | Detected project |
|---|---|
| `*/orca-runtime-sensor*` | `orca-runtime-sensor` |
| `*/orca-sensor*` | `orca-sensor` |
| `*/helm-charts*` | `helm-charts` |
| `*/src/orca*` | `orca` |
| `*/src` | `orca-unified` |

Edit `hooks/session-start` for custom projects.

### Blocked extensions

Edit `case` pattern in `hooks/pre-tool-router` (line 41):

```bash
*.py|*.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.cpp|*.c|*.h|*.hpp|*.rb|*.java|*.kt|*.php|*.scala|*.swift|*.sh|*.bash)
```

## License

MIT
