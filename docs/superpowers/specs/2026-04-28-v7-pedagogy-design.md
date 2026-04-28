# v7 Design: v1 Pedagogy + v6 Safety Net

**Date:** 2026-04-28
**Branch:** v1 (starting point)
**Target version:** 7.0.0
**Language:** Bash hooks, bash tests. TS migration is a future task.

## Problem

v1 taught the LLM how to think with ~510 lines of skill pedagogy across 4 skills. v6 compressed this to ~53 lines in 1 skill and added 7 enforcement hooks + 149 deny rules. Result: the model spends tokens negotiating blocks instead of working, loses routing context after compaction, and defaults to native tools because it was never taught the CBM query patterns.

## Design Principle

Rich pedagogy (skills) teaches correct tool usage. Lightweight enforcement (hooks) catches mistakes with contextual suggestions. No permissions.deny — hooks handle everything with exit 2 + redirect message, avoiding silent blocks that cause failure spirals.

## Architecture

```
orca-env-plugin/
├── .claude-plugin/
│   └── plugin.json                    # v7.0.0, no settings.json
├── hooks/
│   ├── hooks.json                     # 8 hook entries
│   ├── session-start                  # SessionStart (startup|resume|clear): inject orca-setup skill
│   ├── session-start-compact          # SessionStart (compact): re-inject slim routing (NEW)
│   ├── skill-activation-prompt        # UserPromptSubmit: suggest cbm/serena skills on keywords
│   ├── pre-tool-router                # PreToolUse (Read|Edit|Write|Grep|Glob + Serena writes): 3-layer routing
│   ├── rtk-rewrite-bash               # PreToolUse (Bash): rewrite commands through RTK (NEW)
│   ├── post-serena-refs               # PostToolUse (find_referencing_symbols): track traced files
│   ├── stop.js                        # Stop: session analytics
│   ├── subagent-stop.js               # SubagentStop: subagent analytics
│   └── utils/
│       └── transcript-parser.js       # shared by stop hooks
├── skills/
│   ├── cbm-workflow/SKILL.md          # ~130 lines (NEW, replaces codanna)
│   ├── serena-workflow/SKILL.md       # ~140 lines (updated from v1)
│   ├── orca-setup/SKILL.md            # ~120 lines (updated from v1, CBM refs)
│   ├── orca-dev/SKILL.md              # ~65 lines (compact routing + project names)
│   └── skill-rules.json              # keyword triggers for cbm-workflow + serena-workflow
├── tests/
│   ├── helpers.sh                     # assertions, sandbox, runners
│   ├── run-all.sh                     # unit test runner
│   └── unit/
│       ├── test-pre-tool-use.sh       # block/allow behavioral contracts
│       ├── test-session-output.sh     # JSON shape, content injection
│       ├── test-session-compact.sh    # compact re-injection (NEW)
│       ├── test-rtk-rewrite.sh        # RTK bash rewriting (NEW)
│       ├── test-skill-activation.sh   # keyword matching (NEW)
│       ├── test-serena-guard.sh       # edit guard enforcement
│       ├── test-plugin-structure.sh   # file existence, JSON validity
│       ├── test-skills-lint.sh        # skill frontmatter, correct tool names
│       ├── test-project-detection.sh  # cwd -> project mapping
│       ├── test-hooks-smoke.sh        # all hooks run without error
│       ├── test-json-escaping.sh      # special chars in paths/output
│       ├── test-hook-properties.sh    # timeout, async, matcher validity
│       └── test-failure-modes.sh      # missing jq, bad input, malformed JSON
│   └── e2e/
│       ├── run-e2e.sh                 # parallel launcher + result aggregator
│       ├── matrix/
│       │   ├── orca-python-feature.sh     # User.last_seen_at feature
│       │   ├── sensor-go-feature.sh       # --dry-run flag feature
│       │   ├── runtime-go-feature.sh      # TTL config extraction
│       │   └── helm-yaml-feature.sh       # replicaCount (control: non-code passthrough)
│       └── lib/
│           ├── verify-transcript.sh       # parse stream-json, extract tool calls
│           ├── launch-session.sh          # start claude -p with plugin
│           └── assert-routing.sh          # shared routing assertions
└── README.md
```

## Hook Pipeline

### hooks.json — 8 entries (across 6 hook events)

| # | Hook Event | Matcher | Script | Behavior |
|---|---|---|---|---|
| 1 | SessionStart | `startup\|resume\|clear` | `session-start` | Detect Serena project from cwd. Inject full orca-setup skill content (~120 lines) wrapped in `<EXTREMELY_IMPORTANT>`. |
| 2 | SessionStart | `compact` | `session-start-compact` | Inject slim routing reminder (~30 lines) with tool names + key params. Survives context compaction. |
| 3 | UserPromptSubmit | *(all)* | `skill-activation-prompt` | Match prompt keywords against skill-rules.json. Suggest cbm-workflow or serena-workflow. Exit 0 always. |
| 4 | PreToolUse | `Read\|Edit\|Write\|Grep\|Glob\|mcp__serena__(write tools)` | `pre-tool-router` | Layer 1: Grep/Glob block + CBM suggestion. Layer 2: Read/Edit/Write on code → block + CBM/Serena suggestion. Layer 3: Serena writes → warn if refs not traced. |
| 5 | PreToolUse | `Bash` | `rtk-rewrite-bash` | Rewrite eligible bash commands through RTK. Exit 0 always (rewrite, never block). |
| 6 | PostToolUse | `find_referencing_symbols` | `post-serena-refs` | Record traced file + session_id to state/refs-traced.json. Exit 0 always. |
| 7 | Stop | *(all)* | `stop.js` | Parse transcript, write stats to logs/stats/sessions.jsonl. |
| 8 | SubagentStop | *(all)* | `subagent-stop.js` | Same for subagent sessions. |

### hooks.json structure

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/session-start'", "async": false }]
      },
      {
        "matcher": "compact",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/session-start-compact'", "async": false }]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/skill-activation-prompt'" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Read|Edit|Write|Grep|Glob|mcp__serena__(replace_symbol_body|replace_content|insert_after_symbol|insert_before_symbol|rename_symbol)",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/pre-tool-router'", "timeout": 5 }]
      },
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/rtk-rewrite-bash'", "timeout": 5 }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "mcp__serena__find_referencing_symbols",
        "hooks": [{ "type": "command", "command": "bash '${CLAUDE_PLUGIN_ROOT}/hooks/post-serena-refs'", "timeout": 5 }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "node '${CLAUDE_PLUGIN_ROOT}/hooks/stop.js'", "timeout": 30 }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{ "type": "command", "command": "node '${CLAUDE_PLUGIN_ROOT}/hooks/subagent-stop.js'", "timeout": 30 }]
      }
    ]
  }
}
```

### What was removed from v6

| v6 hook | Why removed |
|---|---|
| PostToolBatch audit | Over-policing. Caused block-retry-block spirals. |
| InstructionsLoaded verify | Unnecessary — SessionStart injection handles this. |
| UserPromptExpansion skill-expansion-context | Replaced by simpler skill-activation-prompt. |
| PreCompact | Not needed — compact SessionStart handler covers this. |
| Compiled binary hooks | Back to plain bash. TS migration is future work. |

### What was removed from v6 (configuration)

| v6 config | Why removed |
|---|---|
| settings.json / permissions.deny (142 rules) | Silent blocks cause failure spirals. Hooks provide contextual redirect. |

## Skills

### cbm-workflow/SKILL.md (~130 lines) — NEW

Replaces codanna skill. Maps developer intents to CBM tools.

**Structure:**
1. Quick Start table — intent → tool → key params
2. Common Patterns — 6 copy-paste recipes:
   - "How does X work?" → `search_code`
   - "Where is class Y?" → `search_graph` with name match
   - "Read source of Z" → `search_graph` → `get_code_snippet(qualified_name=...)`
   - "Who calls X?" → `search_graph` with CALLS edge
   - "What does X call?" → `search_graph` with outgoing CALLS
   - "Full architecture" → `get_architecture`
3. Progressive Disclosure — Power Queries:
   - Multi-hop traversals via `query_graph`
   - Impact radius queries
   - Dead code detection
4. Edge Types Reference — compact table (CALLS, IMPORTS, DEFINES, INHERITS, IMPLEMENTS)
5. Tips — get_architecture first, qualified_name for get_code_snippet, path_filter
6. Wrong vs Right table

### serena-workflow/SKILL.md (~140 lines) — updated from v1

95% identical to v1. Changes:
- "Reading Code" section: replace codanna references with CBM `get_code_snippet`
- All edit content unchanged: replace_symbol_body, replace_content, insert, rename
- Wrong/Right table unchanged
- Memory protocol unchanged
- find_referencing_symbols mandate unchanged
- Backrefs `$!1` guidance unchanged

### orca-setup/SKILL.md (~120 lines) — updated from v1

Injected at SessionStart. Changes from v1:
- "Search Code" → CBM tools instead of codanna
- "Read Code" → CBM `get_code_snippet` primary, Serena `find_symbol` for pre-edit reads
- "Call Graph" → CBM `search_graph` with CALLS edge queries
- Params cheat sheet: remove codanna params, add CBM params (`pattern` not `query`, `qualified_name`, `project` required)
- Projects table unchanged
- Serena params cheat sheet unchanged
- Memory protocol unchanged
- Verification section unchanged

### orca-dev/SKILL.md (~65 lines) — compact routing contract

Invocable as `/orca-dev`. Always-on reference.

**Content:**
- Workspace routing table (cwd → Serena project)
- Tool routing table (intent → CBM/Serena tool, never column)
- Edit protocol (3 steps)
- CBM patterns (get_architecture first, qualified_name lookup)
- Project names table (CBM index strings)
- Parallelism rule

### skill-rules.json

```json
{
  "skills": {
    "cbm-workflow": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "promptTriggers": {
        "keywords": ["search code", "find symbol", "find function", "find class",
                     "who calls", "what calls", "callers", "call graph",
                     "trace", "architecture", "explore code", "investigate",
                     "understand code", "how does", "impact", "use cbm"]
      }
    },
    "serena-workflow": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "promptTriggers": {
        "keywords": ["edit code", "refactor", "rename", "replace", "insert",
                     "modify function", "change method", "fix bug", "add method",
                     "use serena", "edit symbol", "replace content"]
      }
    }
  }
}
```

## Testing

### Principles

1. **Tests define behavioral contracts, not implementation details.** Assert outcomes (denied + correct alternative offered), not mechanisms (exit code 2 + stderr regex).
2. **Written to fail first.** Every test must demonstrate failure against v1 code or empty stubs before implementation makes it pass.
3. **Break to verify.** After passing, intentionally break the implementation and confirm the test fails. If it doesn't, the test is worthless.

### Layer 1: Unit tests (13 files, ~1400 lines)

Run via `bash tests/run-all.sh --unit`. No external dependencies.

**Carried from v1 (10 tests, assertions updated for CBM):**

| Test | Contract |
|---|---|
| `test-pre-tool-use.sh` | Native Grep/Glob denied + CBM alternative offered. Read/Edit/Write on code denied + Serena/CBM alternative. Non-code files pass through. |
| `test-session-output.sh` | SessionStart produces valid dual-shape JSON. Contains EXTREMELY_IMPORTANT wrapper. Contains CBM tool references. Contains Serena activation. |
| `test-serena-guard.sh` | Edit without prior refs → warned. Edit after refs → allowed. State resets per session. |
| `test-plugin-structure.sh` | plugin.json valid. hooks.json valid. All 4 skill dirs exist. All hook scripts exist and are executable. |
| `test-skills-lint.sh` | All skills have name/description frontmatter. Content references correct CBM/Serena tool names. No codanna references. |
| `test-project-detection.sh` | ~/src/orca → "orca". ~/src → "orca-unified". /tmp → empty. |
| `test-hooks-smoke.sh` | Every hook executes without crashing given valid input. |
| `test-json-escaping.sh` | Paths with spaces, quotes, unicode produce valid JSON. |
| `test-hook-properties.sh` | All referenced scripts exist. Timeouts present. Matchers are valid. |
| `test-failure-modes.sh` | Missing jq → fail-open (exit 0). Empty stdin → exit 0. Malformed JSON → exit 0. |

**New tests (3 files):**

| Test | Contract |
|---|---|
| `test-session-compact.sh` | Compact handler produces valid JSON. Contains `<tool_routing>` block. Contains CBM + Serena tool names. Contains backrefs reminder. Is slim (not full skill content). |
| `test-rtk-rewrite.sh` | Git commands rewritten through RTK when available. No rewrite when RTK absent. Non-eligible commands pass through. Exit 0 always. |
| `test-skill-activation.sh` | "search code" → suggests cbm-workflow. "edit function" → suggests serena-workflow. "hello" → no suggestion. "find callers and edit" → suggests both. |

### Layer 2: E2E tests (parallel project matrix)

Run via `E2E=1 bash tests/e2e/run-e2e.sh`. Requires `claude` CLI + real repos at `~/src/`.

**All 4 projects launch in parallel from `~/src/` (orca-unified).** Each runs a realistic feature task as sequential transcript segments.

| Project | Feature task | Language |
|---|---|---|
| orca | Add `last_seen_at` field to User model, update login handler | Python |
| orca-sensor | Add `--dry-run` flag to collector CLI | Go |
| orca-runtime-sensor | Extract process cache TTL to config constant | Go+eBPF |
| helm-charts | Add `replicaCount` to sensor chart (control case: non-code) | YAML |

**Execution model:**

```
Time ->
  orca-python:    [explore] -> [plan] -> [edit] -> [verify]
  sensor-go:      [explore] -> [plan] -> [edit] -> [verify]
  runtime-go:     [explore] -> [plan] -> [edit] -> [verify]
  helm-yaml:      [explore] -> [plan] -> [edit] -> [verify]
  |-- parallel across projects, sequential within each --|
```

**Per-segment assertions:**

| Segment | Must use | Must NOT use | Ordering |
|---|---|---|---|
| Explore | `mcp__codebase-memory-mcp__*` | native Grep, Glob, Read on source | — |
| Plan | `find_referencing_symbols` | native Grep for callers | — |
| Edit | `mcp__serena__*` | native Edit, Write on source | refs before edit |
| Verify | Bash | — | — |

**Cross-cutting assertions (all transcripts):**

- First transcript: session start injected orca-unified activation
- helm-yaml: uses native Read/Edit on .yaml (control case — proves no over-blocking)
- RTK: any Bash with git/grep/find shows rtk rewrite

**E2E file structure:**

```
tests/e2e/
  run-e2e.sh                      # parallel launcher, aggregator
  matrix/
    orca-python-feature.sh         # 4 transcript segments
    sensor-go-feature.sh
    runtime-go-feature.sh
    helm-yaml-feature.sh
  lib/
    verify-transcript.sh           # parse stream-json, extract tool calls
    launch-session.sh              # start claude -p with plugin-dir
    assert-routing.sh              # routing assertion helpers
```

## Implementation Order

1. Skills: cbm-workflow (new), orca-setup (update), serena-workflow (update), orca-dev (update), skill-rules.json (update)
2. Hooks: pre-tool-router (update CBM names), session-start (update CBM refs in injected skill), session-start-compact (new), rtk-rewrite-bash (new from v6)
3. Unchanged hooks: skill-activation-prompt, post-serena-refs, stop.js, subagent-stop.js
4. Tests: unit tests first (TDD against stubs), then e2e matrix
5. plugin.json: bump to 7.0.0

## Decisions Log

| Decision | Rationale |
|---|---|
| No permissions.deny | Hooks provide contextual redirect; silent blocks cause failure spirals |
| No compiled binary | Bash hooks, TS migration later |
| 4 skills (~455 lines total) | v1's pedagogy depth, updated for CBM |
| Compact handler added | v1 had no compact handling, routing degraded in long sessions |
| RTK rewrite added | Validated in v6, transparent token savings |
| UserPromptSubmit suggests cbm + serena only | orca-setup fires at session start, orca-dev is slash command |
| E2E tests parallel from ~/src/ | Tests real project detection + routing in orca-unified mode |
| helm-yaml as control case | Proves non-code passthrough works, no over-blocking |
| Tests are behavioral contracts | Survives bash→TS migration — same tests must pass |
