# Claude Toolkit v2 Migration Design

**Date**: 2026-04-17
**Status**: Draft
**Scope**: Migrate `orca-env-plugin` (claude-toolkit) from broken v1.x → v2 with restored behavioral enforcement

## Problem

Current plugin has broken routing:
- Deny messages reference dead Codanna MCP (no process, no config)
- No RTK Bash hook active (retired, never moved to plugin)
- Grep/Glob blocked unconditionally without path checks
- Skills reference nonexistent tools
- SessionStart injects ~1500 tokens eagerly — most redundant with hook enforcement
- MemPalace prompted as mandatory save target but never actually used
- No explicit agent tool restrictions — generic Explore can bypass routing

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Canonical exploration backend | **CBM** (codebase-memory-mcp) | Only running backend; Codanna is gone |
| RTK hook location | **Plugin-owned** | Single control plane |
| MemPalace role | **Read-path at SessionStart** | Search for context, not save enforcement |
| Hook implementation | **Single compiled Bun binary** | Eliminates jq dep, multi-process spawns, shell fragility |
| RTK in binary? | **Yes** | Shells out to `rtk rewrite` but all JSON/protocol logic in TS |
| LLMLingua compression | **Optional, measure first** | Apply if skills > ~500 tokens after SessionStart reduction |
| Superpowers coexistence | **No conflict** | Different hook events, complementary concerns |
| Caveman coexistence | **No conflict** | Style/tone only, no tool routing |

## Architecture

### Single Binary

All hook logic compiles to one Bun native binary (`dist/claude-toolkit`). Event name passed as CLI arg.

```
hooks.json → dist/claude-toolkit <event>
```

```
orca-env-plugin/
  src/
    index.ts                 # entry: read stdin, route by argv[2]
    handlers/
      pre-tool-use.ts        # native-tool-guard + serena-edit-guard + rtk-rewrite
      session-start.ts       # project detect + mempalace search + minimal context
      prompt-submit.ts       # keyword/intent skill activation
      post-tool-use.ts       # refs-traced state tracking
      stop.ts                # transcript stats
    lib/
      constants.ts           # extension sets, path prefixes, project map
      protocol.ts            # hook JSON builders (deny/allow/warn/rewrite)
      logger.ts              # append to hooks.jsonl
      state.ts               # atomic read/write state files
  hooks/
    hooks.json               # single entry point per event
  dist/
    claude-toolkit           # bun --compile output (committed to branch)
  skills/
    orca-setup/SKILL.md      # updated: CBM not Codanna
    serena-workflow/SKILL.md  # unchanged
    codebase-explorer/SKILL.md # new: replaces codanna skill
    docs/SKILL.md            # updated: remove Codanna refs
  agents/
    cbm-explorer.md          # explicit CBM-only tools
    serena-editor.md         # explicit Serena-only tools
  package.json
  tsconfig.json
  build.sh                   # bun build --compile --minify --bytecode
  scripts/
    compress-prompts.py      # optional LLMLingua compression
```

### hooks.json

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|Grep|Glob|Search|Bash|mcp__serena__(replace_symbol_body|replace_content|insert_after_symbol|insert_before_symbol|rename_symbol)",
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' pre-tool-use", "timeout": 5 }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' session-start", "async": false }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' prompt-submit" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__serena__find_referencing_symbols",
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' post-tool-use", "timeout": 5 }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' stop", "timeout": 30 }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "'${CLAUDE_PLUGIN_ROOT}/dist/claude-toolkit' subagent-stop", "timeout": 30 }]
      }
    ]
  }
}
```

## PreToolUse Handler — Three Code Paths

### Path 1: Native File Tools (Read/Edit/Write/Grep/Glob/Search)

```
Extract file_path (or pattern/path/glob) from tool_input
  → No path → ALLOW (fail open)
  → Under ~/.claude/ → ALLOW
  → Outside ~/src/ → ALLOW
  → Inside ~/src/:
      Extract extension
      → ALLOWED_EXTS (md,txt,rst,json,yaml,yml,toml,ini,cfg,conf,sh,bash,zsh,
          env,lock,sum,mod,csv,svg,html,css,xml,proto,sql,log,diff,patch) → ALLOW
      → Allowed filename (README*,Makefile,Dockerfile*,go.mod,go.sum,
          package.json,*.lock,pyproject.toml,Cargo.toml,tsconfig*,...) → ALLOW
      → Allowed path component (docs/,vendor/,generated/,testdata/,
          .github/,scripts/,charts/,templates/,node_modules/) → ALLOW
      → SOURCE_EXTS (go,ts,tsx,js,jsx,rs,py,c,cc,cpp,h,hpp,rb,java,kt,php,scala,swift):
          Read/Grep/Glob/Search → DENY:
            "Use codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path."
          Edit/Write → DENY:
            "Use Serena: replace_symbol_body, replace_content, insert_after_symbol."
      → Grep/Glob with source type/glob filter on ~/src dir → DENY (same CBM message)
      → Unknown ext → ALLOW (fail open)
```

All decisions logged to `~/.claude/logs/hooks.jsonl`.

**Performance**: Pre-computed `Set.has()` for extensions. `startsWith()` for path checks. Zero regex on hot path. Sub-millisecond.

### Path 2: Serena Edit Guard (mcp__serena__ edit tools)

```
Extract relative_path from tool_input
  → No path → ALLOW
  → Check state/refs-traced.json for session+file
      → Traced → ALLOW
      → Not traced → WARN (exit 1):
          "Call find_referencing_symbols first to check downstream impact."
```

Warn, not block. Nudge to trace references before editing.

### Path 3: RTK Rewrite (Bash)

```
Extract command from tool_input
  → No command → passthrough
  → shouldSkipRtk(cmd) → passthrough + log skip
      Skip if: CLAUDE_RAW=1, pipes (|), redirects (><), heredocs (<<),
      chains (&&, ||, ;), command substitution ($(), ``)
  → Bun.spawn(['rtk', 'rewrite', cmd])
      → exit 0 + stdout → ALLOW with rewritten command
      → exit 1 → passthrough (no RTK equivalent)
      → exit 2 → passthrough (deny rule)
      → exit 3 + stdout → rewrite but no auto-allow (user prompt)
```

RTK skip detection: single-pass charcode scan, no regex.

## SessionStart Handler — Minimal

~200 tokens injected instead of ~1500. Three jobs:

**1. Project detection** (by PWD):
```
*/orca-cloud-platform*  → "" (no Serena project)
*/orca-runtime-sensor*  → "orca-runtime-sensor"
*/orca-sensor*          → "orca-sensor"
*/helm-charts*          → "helm-charts"
*/src/orca*             → "orca"
*/src                   → "orca-unified"
*                       → ""
```

Emits: `IMMEDIATELY call mcp__serena__activate_project(project=<name>)`

**2. MemPalace context search** (if available):
```
mempalace_search(query: project + branch) → inject results as advisory context
Skip silently if MCP unavailable.
```

**3. Routing table** (~3 lines):
```
Source-code exploration → CBM (search_graph, search_code, get_code_snippet, trace_path)
Source-code edits → Serena (replace_symbol_body, replace_content)
Docs/config/logs → native tools
```

Full skill content loaded lazily via Skill tool when needed.

## UserPromptSubmit — Context-Aware Skill Activation

Richer `skill-rules.json` with keywords + intent patterns:

```json
{
  "skills": {
    "codebase-explorer": {
      "priority": "critical",
      "promptTriggers": {
        "keywords": [
          "investigate", "explore", "understand code", "codebase",
          "search graph", "trace path", "call chain", "callers",
          "who calls", "what calls", "impact analysis", "architecture",
          "find function", "find class", "find symbol", "code snippet",
          "data flow", "dependencies", "implementation"
        ],
        "intentPatterns": [
          "(how|where|what|who) does .* (work|call|depend|use)",
          "(find|locate|search|trace|show) .* (function|class|method|symbol|callers|calls)",
          "(explore|understand|investigate) .* (code|module|package|service)"
        ]
      }
    },
    "serena-editor": {
      "priority": "critical",
      "promptTriggers": {
        "keywords": [
          "edit", "modify", "change", "refactor", "rename",
          "replace", "add method", "add function", "implement",
          "fix bug", "update code", "rewrite"
        ],
        "intentPatterns": [
          "(edit|modify|change|fix|update|refactor|rename|rewrite) .* (function|class|method|code)",
          "(add|create|implement) .* (method|function|class|handler|endpoint)"
        ]
      }
    },
    "web-search": {
      "priority": "high",
      "promptTriggers": {
        "keywords": [
          "search web", "find online", "latest version", "release notes",
          "changelog", "breaking changes", "migration guide", "CVE",
          "vulnerability", "security advisory"
        ]
      }
    },
    "docs-lookup": {
      "priority": "medium",
      "promptTriggers": {
        "keywords": [
          "docs", "documentation", "api reference", "library",
          "how to use", "example of"
        ]
      }
    }
  }
}
```

Output includes direct tool names:
```
SKILL ACTIVATION CHECK
REQUIRED: codebase-explorer
ACTION: Use CBM tools (search_graph, trace_path, get_code_snippet)
```

## Agents — Explicit Tool Lists

### CBM Explorer

```yaml
name: cbm-explorer
description: "MUST BE USED for source-code exploration, callers, data flow,
  implementation discovery, architecture/impact analysis."
tools:
  - mcp__codebase-memory-mcp__search_graph
  - mcp__codebase-memory-mcp__search_code
  - mcp__codebase-memory-mcp__get_code_snippet
  - mcp__codebase-memory-mcp__trace_path
  - mcp__codebase-memory-mcp__get_architecture
  - mcp__codebase-memory-mcp__query_graph
  - mcp__codebase-memory-mcp__index_repository
  - mcp__codebase-memory-mcp__index_status
  - mcp__docs__search_docs
  - mcp__docs__fetch_url
  - mcp__exa__web_search_exa
  - mcp__exa__web_fetch_exa
```

No Bash. No Read/Grep/Glob/Search. No Edit/Write.

### Serena Editor

```yaml
name: serena-editor
description: "MUST BE USED for source-code edits. Always call
  find_referencing_symbols before editing."
tools:
  - mcp__serena__find_symbol
  - mcp__serena__get_symbols_overview
  - mcp__serena__find_referencing_symbols
  - mcp__serena__replace_symbol_body
  - mcp__serena__replace_content
  - mcp__serena__insert_after_symbol
  - mcp__serena__insert_before_symbol
  - mcp__serena__rename_symbol
  - mcp__serena__safe_delete_symbol
  - mcp__serena__read_file
  - mcp__serena__search_for_pattern
```

No Bash. No native file tools.

### Generic Explore Escape Hatch

Mitigated by hooks: even if Claude spawns an Explore agent, PreToolUse fires globally and blocks native tools on source code. Hook is the enforcement, not agent definition.

## Cleanup

### Remove from plugin
- `skills/codanna/SKILL.md` — dead
- `hooks/pre-tool-router` (shell) — replaced by binary
- `hooks/session-start` (shell) — replaced by binary
- `hooks/skill-activation-prompt` (shell) — replaced by binary
- `hooks/post-serena-refs` (shell) — replaced by binary
- `hooks/stop.js` — replaced by binary
- `hooks/subagent-stop.js` — replaced by binary
- `hooks/utils/transcript-parser.js` — folded into binary

### Update in plugin
- `skills/orca-setup/SKILL.md` — Codanna → CBM
- `skills/docs/SKILL.md` — remove Codanna refs
- `skills/skill-rules.json` — richer keywords, remove add-language
- `hooks/hooks.json` — single binary routing

### Add to plugin
- `src/` TypeScript tree
- `dist/claude-toolkit` compiled binary
- `agents/cbm-explorer.md`
- `agents/serena-editor.md`
- `skills/codebase-explorer/SKILL.md` (new, replaces codanna)
- `build.sh`
- `package.json` / `tsconfig.json`

### Remove from ~/.claude/hooks/disabled/
Archive to tarball, clean directory.

### CLAUDE.md
Strip to ~15 lines: routing table, scope rules, RTK note, Serena path convention.

## CLAUDE.md Target

```markdown
# Claude Code Workspace

## Scope
- Single-command Bash. No chained explanations.
- Treat memory as hints. Re-check upstream.

## Decision tree
- External/time-sensitive truth → web/docs/exa first
- Indexed source-code exploration → CBM (search_graph, search_code, get_code_snippet, trace_path)
- Source-code reads → Serena (find_symbol, read_file)
- Source-code edits → Serena (replace_symbol_body, replace_content, insert_after_symbol)
- Docs/config/logs/diffs/debugging/raw text → native tools
- Build/test/git/filesystem facts → Bash
- RTK default for simple Bash commands
- Unified workspace Serena paths: repo-prefixed (e.g. orca/sensors/base.py)
- No python -c / perl / ruby / sed -i for source-code edits

@RTK.md
```

## Token Optimization — Phase 9

Applied only after behavior verified:

1. SessionStart injection: ~200 tokens (down from ~1500)
2. Deny messages are the recovery path — no eager prose duplication
3. Skills lazy-loaded via Skill tool
4. CLAUDE.md: ~15 lines advisory
5. Optional LLMLingua: measure skill token counts post-implementation; compress if any single skill > ~500 tokens

## Live Validation Checklist

| # | Check | Method |
|---|-------|--------|
| A | One RTK source | hooks.json: Bash in single PreToolUse matcher |
| B | One native-tool-guard | Same binary handles all Read/Edit/Write/Grep/Glob/Search |
| C | Read ~/src/*.go denied | Attempt Read, verify deny message references CBM |
| D | Grep on source denied | Attempt Grep type=go, verify deny |
| E | Edit on source denied | Attempt Edit on .go, verify deny |
| F | Read README.md allowed | Attempt, verify pass |
| G | Read ~/.claude/settings.json allowed | Verify pass |
| H | Simple Bash → RTK | Run git status, verify RTK rewrite in logs |
| I | CLAUDE_RAW=1 bypass | Run raw command, verify skip in logs |
| J | Explorer agent tools | Inspect — no Bash/native file tools |
| K | Editor agent tools | Inspect — Serena only |
| L | Explore escape hatch | Hook blocks native tools even in subagents |
| M | CBM in deny messages | Verify deny text references CBM not Codanna |
| N | MemPalace read-only | SessionStart searches, no save enforcement |
| O | No stale cache | Plugin loads from source, no cache copy |

## Implementation Phases

1. **Backup** — archive current state
2. **Scaffold** — TS project, src/ tree, tsconfig, package.json, build.sh
3. **Implement handlers** — port all hook logic to TS handlers
4. **Compile** — bun build --compile, commit binary
5. **Update hooks.json** — route all events to binary
6. **Update skills** — Codanna → CBM everywhere
7. **Add agents** — explicit tool-restricted definitions
8. **Cleanup** — remove old shell hooks, archive disabled/ dir
9. **Update CLAUDE.md** — strip to minimal routing table
10. **Live validation** — run full checklist
11. **Optional compression** — measure, apply LLMLingua if needed
