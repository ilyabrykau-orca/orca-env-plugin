# claude-toolkit

Claude Code plugin that enforces MCP tool routing for codebases using [Codanna](https://github.com/bartolli/codanna) and [Serena](https://github.com/aorwall/serena).

Instead of letting Claude use native Read/Edit/Grep on code files, this plugin blocks them and routes to MCP-powered alternatives — giving you semantic search, symbolic editing, reference tracking, and impact analysis.

## What it does

| Native tool | Blocked on | Routed to |
|---|---|---|
| `Read` | Code files (.py, .go, .ts, .rs, ...) | `mcp__serena__find_symbol` / `mcp__serena__read_file` |
| `Edit` / `Write` | Code files | `mcp__serena__replace_symbol_body` / `mcp__serena__replace_content` |
| `Grep` | All files | `mcp__codanna__semantic_search_with_context` |
| `Glob` | All files | `mcp__codanna__search_symbols` |

Non-code files (.json, .yaml, .md, .toml) pass through to native tools.

### Additional features

- **Serena edit guard** — warns if you edit code without first calling `find_referencing_symbols` (prevents breaking callers)
- **Project detection** — auto-detects workspace project from cwd, injects Serena activation context
- **Skill activation** — suggests relevant skills (codanna, serena-workflow, docs) based on prompt keywords
- **Session analytics** — tracks token usage, tool distribution, and costs per session

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- [Codanna](https://github.com/bartolli/codanna) running at `https://localhost:8443/mcp`
- [Serena](https://github.com/aorwall/serena) running at `http://127.0.0.1:8765/mcp`
- `jq` installed (`brew install jq`)

## Install

```bash
# Register marketplace (one-time)
claude plugin marketplace add orca-sensor-marketplace ilyabrykau-orca/orca-sensor-marketplace

# Install plugin
claude plugin install claude-toolkit@orca-sensor-marketplace
```

Or install directly from the repo:

```bash
claude plugin install --from-repo ilyabrykau-orca/claude-toolkit
```

## Plugin structure

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

## Hook latency

All PreToolUse hooks run in a single bash process (~8-10ms).
Node.js hooks (stop/subagent-stop) run once per session end.

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

## Configuration

### Project detection

The `session-start` hook detects the workspace from `$PWD`:

| Path pattern | Detected project |
|---|---|
| `*/orca-runtime-sensor*` | `orca-runtime-sensor` |
| `*/orca-sensor*` | `orca-sensor` |
| `*/helm-charts*` | `helm-charts` |
| `*/src/orca*` | `orca` |
| `*/src` | `orca-unified` |

Edit `hooks/session-start` to add your own projects.

### Blocked file extensions

Edit the `case` pattern in `hooks/pre-tool-router` (line 41):

```bash
*.py|*.go|*.ts|*.tsx|*.js|*.jsx|*.rs|*.cpp|*.c|*.h|*.hpp|*.rb|*.java|*.kt|*.php|*.scala|*.swift|*.sh|*.bash)
```

## License

MIT
