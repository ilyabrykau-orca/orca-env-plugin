# claude-toolkit

Claude Code plugin that enforces MCP tool routing for codebases using [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp), [Serena](https://github.com/oraios/serena), and [RTK](https://github.com/rtk-ai/rtk).

Instead of letting Claude use native Read/Edit/Grep on code files, this plugin blocks them and routes to MCP-powered alternatives — giving you structural search, symbolic editing, reference tracking, impact analysis, and lower-token Bash output.

## What it does

| Native tool | Blocked on | Routed to |
|---|---|---|
| `Read` | Code files (.py, .go, .ts, .rs, ...) | `mcp__codebase-memory-mcp__search_graph` / `mcp__codebase-memory-mcp__get_code_snippet` |
| `Edit` / `Write` | Code files | `mcp__serena__replace_symbol_body` / `mcp__serena__replace_content` |
| `Grep` / `Search` | All files | `mcp__codebase-memory-mcp__search_code` |
| `Glob` | All files | `mcp__codebase-memory-mcp__search_graph` |
| `Bash` | Simple single commands | `rtk <command>` via transparent PreToolUse rewrite |

Non-code files (.json, .yaml, .md, .toml) pass through to native tools. Composite shell commands (pipes, redirects, heredocs, `&&`, `||`, `;`) bypass RTK automatically so raw debugging still works.

### Additional features

- **Serena edit guard** — warns if you edit code without first calling `find_referencing_symbols` (prevents breaking callers)
- **Project detection** — auto-detects workspace project from cwd, injects Serena activation context
- **Skill activation** — suggests relevant skills (codebase-memory-mcp, serena-workflow, docs) based on prompt keywords
- **Session analytics** — tracks token usage, tool distribution, and costs per session

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) installed and in `PATH`
- [Serena](https://github.com/oraios/serena) running and configured for Claude Code
- [RTK](https://github.com/rtk-ai/rtk) installed and in `PATH`
- `jq` installed (`brew install jq`)

Recommended setup:

```bash
codebase-memory-mcp install
codebase-memory-mcp config set auto_index true
rtk init --global --agent claude
```

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
  rtk-rewrite.sh        ← bash: transparent RTK Bash rewrite
  post-serena-refs      ← bash: tracks reference-traced files
  skill-activation-prompt ← bash: keyword matching for skill suggestions
  session-start         ← bash: project detection + context injection
  stop.js               ← node: session analytics (once per session)
  subagent-stop.js      ← node: subagent analytics
  utils/transcript-parser.js

skills/
  codebase-memory-mcp/SKILL.md  ← CBM query patterns, wrong-vs-right table
  orca-setup/SKILL.md           ← workspace routing rules, RTK/CBM/Serena patterns
  serena-workflow/SKILL.md      ← Serena editing protocol
  docs/SKILL.md                 ← Docs MCP usage
  skill-rules.json              ← keyword triggers for skill activation
```

## Hook latency

All PreToolUse hooks run in a single bash process (~8-12ms).
Node.js hooks (stop/subagent-stop) run once per session end.

| Hook | Latency | Frequency |
|---|---|---|
| `rtk-rewrite.sh` | ~5ms | Every Bash tool call |
| `pre-tool-router` | ~10ms | Every routed tool call |
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

Edit the `case` pattern in `hooks/pre-tool-router`.

## License

MIT
