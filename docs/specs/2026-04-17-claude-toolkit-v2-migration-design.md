# Claude Toolkit v2 Migration Design

**Date**: 2026-04-17 | **Status**: Draft
**Scope**: orca-env-plugin v1.x → v2 w/ restored enforcement

## Problem

- Deny msgs reference dead Codanna MCP
- No RTK Bash hook active
- Grep/Glob blocked unconditionally w/o path checks
- Skills reference nonexistent tools
- SessionStart injects ~1500 tokens eagerly — mostly redundant
- MemPalace prompted as mandatory save but never used
- No agent tool restrictions — Explore bypasses routing

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Exploration backend | **CBM** | Only running; Codanna gone |
| RTK hook | **Plugin-owned** | Single control plane |
| MemPalace role | **Read-path at SessionStart** | Search context, not save |
| Hook impl | **Single compiled Bun binary** | No jq, no multi-process, no shell fragility |
| RTK in binary? | **Yes** | Shells to `rtk rewrite`, protocol in TS |
| LLMLingua | **Optional, measure first** | If skills > ~500 tokens |
| Superpowers | **No conflict** | Different events |
| Caveman | **No conflict** | Style only |

## Architecture

### Single Binary

All hooks → one Bun binary (`dist/claude-toolkit`). Event as CLI arg.

```
hooks.json → dist/claude-toolkit <event>
```

```
orca-env-plugin/
  src/
    index.ts                 # entry: stdin → route by argv[2]
    handlers/
      pre-tool-use.ts        # native-guard + serena-guard + rtk
      session-start.ts       # project detect + context
      prompt-submit.ts       # skill activation
      post-tool-use.ts       # refs-traced tracking
      stop.ts                # transcript stats
    lib/
      constants.ts           # ext sets, paths, project map
      protocol.ts            # hook JSON builders
      logger.ts              # hooks.jsonl
      state.ts               # refs-traced files
  hooks/hooks.json           # single binary per event
  dist/claude-toolkit        # bun --compile output
  skills/                    # SKILL.md per domain
  agents/                    # tool-restricted agents
  package.json / tsconfig.json / build.sh
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

## PreToolUse — Three Paths

### Path 1: Native File Tools

```
Extract file_path from tool_input
  → No path → ALLOW (fail open)
  → Under ~/.claude/ → ALLOW
  → Outside ~/src/ → ALLOW
  → Inside ~/src/:
      → ALLOWED_EXTS → ALLOW
      → Allowed filename prefix → ALLOW
      → Allowed path component (/docs/, /vendor/...) → ALLOW
      → SOURCE_EXTS:
          Read/Grep/Glob/Search → DENY "Use CBM"
          Edit/Write → DENY "Use Serena"
      → Grep/Glob w/ source type/glob → DENY
      → Unknown ext → ALLOW (fail open)
```

Logged to `~/.claude/logs/hooks.jsonl`. Perf: `Set.has()`, `startsWith()`. Zero regex. Sub-ms.

### Path 2: Serena Edit Guard

```
Extract relative_path
  → No path → ALLOW
  → Check state/refs-traced.json
      → Traced → ALLOW
      → Not traced → WARN (exit 1): "find_referencing_symbols first"
```

### Path 3: RTK Rewrite (Bash)

```
Extract command
  → shouldSkipRtk(cmd) → passthrough
      Skip: CLAUDE_RAW=1, pipes, redirects, heredocs, chains, $(), ``
  → Bun.spawn(['rtk', 'rewrite', cmd])
      exit 0 + stdout → ALLOW w/ rewritten cmd
      exit 1 → passthrough
      exit 2 → passthrough
      exit 3 + stdout → rewrite, no auto-allow
```

Single-pass charcode scan, no regex.

## SessionStart — Minimal

~200 tokens (down from ~1500):

**1. Project detection** (by PWD):
```
*/orca-cloud-platform*  → ""
*/orca-runtime-sensor*  → "orca-runtime-sensor"
*/orca-sensor*          → "orca-sensor"
*/helm-charts*          → "helm-charts"
*/src/orca*             → "orca"
*/src                   → "orca-unified"
```

Emits: `IMMEDIATELY call mcp__serena__activate_project(project=<name>)`

**2. MemPalace search** (if available): query project+branch → inject context.

**3. Routing table** (~3 lines): CBM explore, Serena edits, native docs, Bash build.

Skills lazy-loaded via Skill tool.

## UserPromptSubmit — Skill Activation

Keyword + intent matching from `skill-rules.json`:

```json
{
  "skills": {
    "codebase-explorer": {
      "priority": "critical",
      "promptTriggers": {
        "keywords": ["investigate", "explore", "codebase", "search graph", "trace path", "call chain", "callers", "who calls", "impact analysis", "architecture", "find function", "find class", "code snippet", "data flow", "dependencies", "implementation"],
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
        "keywords": ["edit", "modify", "change", "refactor", "rename", "replace", "add method", "implement", "fix bug", "update code", "rewrite"],
        "intentPatterns": [
          "(edit|modify|change|fix|update|refactor|rename|rewrite) .* (function|class|method|code)",
          "(add|create|implement) .* (method|function|class|handler|endpoint)"
        ]
      }
    },
    "web-search": {
      "priority": "high",
      "promptTriggers": {
        "keywords": ["search web", "latest version", "release notes", "changelog", "breaking changes", "CVE", "vulnerability"]
      }
    },
    "docs-lookup": {
      "priority": "medium",
      "promptTriggers": {
        "keywords": ["docs", "documentation", "api reference", "library", "how to use"]
      }
    }
  }
}
```

Output:
```
SKILL ACTIVATION CHECK
REQUIRED: codebase-explorer
ACTION: Use CBM tools (search_graph, trace_path, get_code_snippet)
```

## Agents — Tool-Restricted

**CBM Explorer**: search_graph, search_code, get_code_snippet, trace_path, get_architecture, query_graph, index_*, docs, exa. No Bash/native.

**Serena Editor**: find_symbol, get_symbols_overview, find_referencing_symbols, replace_*, insert_*, rename_symbol, safe_delete_symbol, read_file, search_for_pattern. No Bash/native.

**Explore Escape Hatch**: PreToolUse fires globally → blocks native tools even in subagents.

## Cleanup

**Remove**: `skills/codanna/SKILL.md`, all old shell hooks (pre-tool-router, session-start, skill-activation-prompt, post-serena-refs, stop.js, subagent-stop.js, utils/transcript-parser.js, hooks/package.json)

**Update**: Skills Codanna → CBM, skill-rules.json, hooks.json → binary

**Add**: src/ TS tree, dist/claude-toolkit, agents, skills/codebase-explorer/, build.sh, package.json/tsconfig.json

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

## Token Optimization

1. SessionStart: ~200 tokens (from ~1500)
2. Deny msgs = recovery path — no eager duplication
3. Skills lazy-loaded
4. CLAUDE.md: ~15 lines
5. Optional LLMLingua post-impl

## Validation

| # | Check | Method |
|---|-------|--------|
| A | One RTK source | hooks.json: Bash in single matcher |
| B | One native guard | Same binary |
| C | Read ~/src/*.go denied | Deny → CBM |
| D | Grep source denied | Deny |
| E | Edit source denied | Deny |
| F | Read README.md allowed | Pass |
| G | Read ~/.claude/ allowed | Pass |
| H | Simple Bash → RTK | Rewrite in logs |
| I | CLAUDE_RAW=1 bypass | Skip in logs |
| J | Explorer tools | No Bash/native |
| K | Editor tools | Serena only |
| L | Explore escape | Hook blocks in subagents |
| M | CBM in deny msgs | Not Codanna |
| N | MemPalace read-only | Search, no save |
| O | No stale cache | From source |

## Phases

1. Backup → 2. Scaffold TS → 3. Implement handlers → 4. Compile → 5. Update hooks.json → 6. Update skills → 7. Add agents → 8. Cleanup old hooks → 9. Update CLAUDE.md → 10. Validate → 11. Optional compression
