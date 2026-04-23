---
name: plugin-creator
description: Create CLAUDE.md and hooks following context-mode patterns — context window protection, tool routing enforcement, session continuity via SQLite + XML snapshots
type: flexible
---

# Plugin Creator: CLAUDE.md + Hooks

Use when creating or improving CLAUDE.md files and Claude Code hooks following the context-mode architecture. The goal is **context window protection**: route tool output to sandbox, enforce preferred tools, and survive compaction.

---

## CLAUDE.md Patterns

### 1. Framing — MANDATORY language

Every section that enforces a constraint opens with **MANDATORY** or similar imperative:

```markdown
# [Project] — MANDATORY routing rules

You have [MCP tools] available. These rules are NOT optional — they protect your context window
from flooding. A single unrouted command can dump 56 KB into context and waste the entire session.
```

**Why**: Soft suggestions are ignored. Hard framing + consequences ("waste the entire session") changes behavior.

### 2. "Think in Code" section

```markdown
## Think in Code — MANDATORY

When you need to analyze, count, filter, compare, search, parse, transform, or process data:
**write code** via `ctx_execute(language, code)`. Do NOT read raw data into context to process
mentally. Your role is to PROGRAM the analysis, not to COMPUTE it.
Write robust, pure JavaScript — no npm dependencies, only Node.js built-ins (`fs`, `path`,
`child_process`). Always use `try/catch`, handle `null`/`undefined`.
One script replaces ten tool calls and saves 100x context.
```

### 3. BLOCKED commands — name them explicitly

List every blocked command with what to do instead:

```markdown
## BLOCKED commands — do NOT attempt these

### curl / wget — BLOCKED
Any Bash command containing `curl` or `wget` is intercepted. Do NOT retry.
Instead use:
- `ctx_fetch_and_index(url, source)` to fetch and index web pages
- `ctx_execute(language: "javascript", code: "const r = await fetch(...)")` for HTTP calls

### WebFetch — BLOCKED
WebFetch calls are denied entirely. Use `ctx_fetch_and_index` instead.
```

**Pattern**: Name the blocked thing → "Do NOT retry" → explicit alternative.

### 4. REDIRECTED tools — distinguish analyze vs. edit

```markdown
## REDIRECTED tools

### Read (for analysis)
If reading to **Edit** → Read is correct (Edit needs content in context).
If reading to **analyze/explore** → use `ctx_execute_file(path, language, code)` instead.

### Bash (>20 lines output)
Bash is ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, short-output commands.
For everything else use `ctx_batch_execute(commands, queries)`.

### Grep (large results)
Use `ctx_execute(language: "shell", code: "grep ...")` — only your summary enters context.
```

### 5. Tool selection hierarchy — numbered, canonical

```markdown
## Tool selection hierarchy

1. **GATHER**: `ctx_batch_execute(commands, queries)` — Primary. Runs commands, auto-indexes,
   searches. ONE call replaces 30+. Each command: `{label: "descriptive header", command: "..."}`.
   Label becomes FTS5 chunk title — descriptive labels improve search.
2. **FOLLOW-UP**: `ctx_search(queries: ["q1", "q2"])` — Query indexed content. Batch ALL questions.
3. **PROCESSING**: `ctx_execute(language, code)` | `ctx_execute_file(path, language, code)`
4. **WEB**: `ctx_fetch_and_index(url, source)` then `ctx_search(queries)`
5. **INDEX**: `ctx_index(content, source)` — Store content in FTS5 for later search.
```

### 6. File writing policy — absolute rule

```markdown
## File writing policy

ALWAYS use native Write to create files, Edit to modify files.
NEVER use `ctx_execute`, `ctx_execute_file`, or Bash to write file content.
Applies to all types: code, configs, specs, YAML, JSON, markdown.
```

### 7. Output constraints section — XML block

Embed as `<context_window_protection>` XML injected via SessionStart (and copied to CLAUDE.md).
This is the **single source of truth** — it lives in the plugin's routing-block and is injected
at SessionStart AND duplicated in CLAUDE.md:

```xml
<context_window_protection>
  <priority_instructions>
    Raw tool output floods your context window. You MUST use context-mode MCP tools to keep
    raw data in the sandbox.
  </priority_instructions>

  <tool_selection_hierarchy>
    1. GATHER: ctx_batch_execute(commands, queries)
    2. FOLLOW-UP: ctx_search(queries: [...])
    3. PROCESSING: ctx_execute(language, code) | ctx_execute_file(path, language, code)
  </tool_selection_hierarchy>

  <forbidden_actions>
    - DO NOT use Bash for commands producing >20 lines of output.
    - DO NOT use Read for analysis (use execute_file).
    - DO NOT use WebFetch (use ctx_fetch_and_index instead).
    - Bash is ONLY for git/mkdir/rm/mv/navigation.
    - DO NOT use ctx_execute/ctx_execute_file to create, modify, or overwrite files.
  </forbidden_actions>

  <file_writing_policy>
    ALWAYS use native Write to create files and Edit to modify files.
  </file_writing_policy>

  <output_constraints>
    <word_limit>Keep your final response under 500 words.</word_limit>
    <artifact_policy>
      Write artifacts to FILES using native Write. NEVER return them as inline text.
      Return only: file path + 1-line description.
    </artifact_policy>
    <response_format>
      - Actions taken (2-3 bullets)
      - File paths created/modified
      - Knowledge base source labels
      - Key findings
    </response_format>
  </output_constraints>
</context_window_protection>
```

---

## Hooks Patterns

### hooks.json structure

```json
{
  "description": "Purpose — PreToolUse routing, PostToolUse capture, PreCompact snapshot, SessionStart injection",
  "hooks": {
    "PostToolUse": [{
      "matcher": "Bash|Read|Write|Edit|Glob|Grep|TodoWrite|TaskCreate|TaskUpdate|mcp__",
      "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/posttooluse.mjs\"" }]
    }],
    "PreCompact": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/precompact.mjs\"" }]
    }],
    "PreToolUse": [
      { "matcher": "Bash",    "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs\"" }] },
      { "matcher": "WebFetch","hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs\"" }] },
      { "matcher": "Read",    "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs\"" }] },
      { "matcher": "Grep",    "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs\"" }] },
      { "matcher": "Agent",   "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs\"" }] }
    ],
    "UserPromptSubmit": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/userpromptsubmit.mjs\"" }]
    }],
    "SessionStart": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/sessionstart.mjs\"" }]
    }]
  }
}
```

**Patterns**:
- Use `${CLAUDE_PLUGIN_ROOT}` — never hardcode paths
- PostToolUse has one broad matcher covering all tools
- PreToolUse splits by tool (one entry per intercepted tool)
- PreCompact and SessionStart use empty matcher (`""`) = catch-all

### PreToolUse hook — routing logic

Decision types returned:
```
{ action: "deny", reason: string }      — block the tool call
{ action: "modify", updatedInput: obj } — rewrite the tool input
{ action: "context", additionalContext: string } — inject guidance text
null                                    — passthrough (allow)
```

**Cross-platform tool name normalization** — always normalize before routing:
```javascript
const TOOL_ALIASES = {
  "run_shell_command": "Bash",  // Gemini CLI
  "bash": "Bash",               // OpenCode
  "shell": "Bash",              // Codex
  "run_in_terminal": "Bash",    // VS Code Copilot
  "read_file": "Read",
  "grep_search": "Grep",
  "web_fetch": "WebFetch",
};
const canonical = TOOL_ALIASES[tool_name] ?? tool_name;
```

**guidanceOnce throttle** — show each advisory type at most once per session:
```javascript
// Hybrid: in-memory Set (same process) + O_EXCL file markers (cross-process)
// Session scoped via process.ppid (= host PID, constant for session lifetime)
const _guidanceDir = resolve(tmpdir(), `context-mode-guidance-${process.ppid}`);

function guidanceOnce(type, content) {
  if (_guidanceShown.has(type)) return null;
  const fd = openSync(marker, O_CREAT | O_EXCL | O_WRONLY); // atomic, throws EEXIST
  closeSync(fd);
  _guidanceShown.add(type);
  return { action: "context", additionalContext: content };
}
```

**mcpRedirect guard** — don't deny if MCP isn't ready:
```javascript
function mcpRedirect(result) {
  if (!isMCPReady()) return null; // passthrough when MCP unavailable
  return result;
}
```

**Strip heredocs before pattern matching**:
```javascript
function stripHeredocs(cmd) {
  return cmd.replace(/<<-?\s*["']?(\w+)["']?[\s\S]*?\n\s*\1/g, "");
}
```

### PostToolUse hook — session event capture

Rules:
- Must be fast (<20ms). No network, no LLM — SQLite writes only.
- Read stdin JSON → extract events → `db.insertEvent(sessionId, event, "PostToolUse")`
- Never block: wrap everything in `try/catch` with silent fallback.
- No hookSpecificOutput needed (PostToolUse doesn't return output).

Session event categories (priority order):
| Category | Priority | Captured By |
|---|---|---|
| Files (read/edit/write/glob/grep) | P1 Critical | PostToolUse |
| Tasks (create/update/complete) | P1 Critical | PostToolUse |
| Rules (CLAUDE.md paths + content) | P1 Critical | SessionStart |
| User prompts | P1 Critical | UserPromptSubmit |
| Decisions (corrections, preferences) | P2 High | UserPromptSubmit |
| Git (checkout/commit/merge/push) | P2 High | PostToolUse |
| Errors (tool failures, non-zero exit) | P2 High | PostToolUse |
| Environment (cwd, venv, nvm changes) | P2 High | PostToolUse |
| MCP tool calls (with usage counts) | P3 Normal | PostToolUse |
| Subagents, Skills | P3 Normal | PostToolUse |
| Role/persona directives | P3 Normal | UserPromptSubmit |
| Intent (investigate/implement/debug) | P4 Low | UserPromptSubmit |

### PreCompact hook — snapshot builder

```javascript
// Build priority-tiered XML snapshot ≤2 KB, store for post-compact injection
const events = db.getEvents(sessionId);
const snapshot = buildResumeSnapshot(events, { compactCount: stats.compact_count + 1 });
db.upsertResume(sessionId, snapshot, events.length);
db.incrementCompactCount(sessionId);
// Always: console.log(JSON.stringify({}));  ← PreCompact needs empty output
```

### SessionStart hook — lifecycle routing

```javascript
const source = input.source ?? "startup"; // "startup" | "compact" | "resume" | "clear"

if (source === "compact") {
  // Inject resume directive only (events already written pre-compact)
} else if (source === "resume") {
  // User used --continue: clear cleanup flag, inject last session events
} else if (source === "startup") {
  // Fresh session: inject ROUTING_BLOCK + previous session knowledge, cleanup old data
}
// Always prepend: additionalContext = ROUTING_BLOCK (the XML block)
```

**Output format** (SessionStart must return `additionalContext`):
```javascript
console.log(JSON.stringify({ additionalContext }));
```

### UserPromptSubmit hook — prompt capture

```javascript
// Skip system-generated messages
const isSystemMessage = trimmed.startsWith("<task-notification>")
  || trimmed.startsWith("<system-reminder>")
  || trimmed.startsWith("<context_guidance>")
  || trimmed.startsWith("<tool-result>");
// Only save genuine user prompts + extract intent/decisions/role from them
```

### Universal hook rules

1. **Silent fallback**: Every hook wraps logic in `try/catch {}` — hooks must NEVER block sessions.
2. **Path resolution**: Always use `dirname(fileURLToPath(import.meta.url))` for absolute paths — hooks run from arbitrary CWDs.
3. **stdin**: Read via `readStdin()` helper, parse as JSON.
4. **Session ID**: Get via `getSessionId(input)` — from env or input.
5. **Suppress stderr**: Import `./suppress-stderr.mjs` to keep hook stderr silent.
6. **Deps**: Import `./ensure-deps.mjs` to auto-install SQLite if missing.
7. **Speed**: PostToolUse < 20ms, UserPromptSubmit < 10ms.

---

## settings.json Patterns

```json
{
  "permissions": {
    "deny": [
      "Bash(sudo *)",
      "Bash(rm -rf /*)",
      "Read(.env)",
      "Read(**/.env*)"
    ],
    "allow": [
      "Bash(git:*)",
      "Bash(ls:*)",
      "Bash(npm:*)",
      "Bash(npx:*)"
    ]
  }
}
```

**Pattern**: deny destructive/secret-leaking ops; allow short-output safe commands explicitly.

---

## Quick Checklist

When creating CLAUDE.md:
- [ ] "MANDATORY" framing with consequence stated
- [ ] "Think in Code" section for data processing
- [ ] BLOCKED section: curl/wget, WebFetch, inline HTTP
- [ ] REDIRECTED section: Bash (>20 lines), Read (analysis), Grep
- [ ] Tool hierarchy: numbered GATHER→FOLLOW-UP→PROCESSING→WEB→INDEX
- [ ] File writing policy: Write/Edit only, never ctx_execute
- [ ] `<context_window_protection>` XML block (same content as SessionStart injects)

When creating hooks:
- [ ] hooks.json: 5 events — PostToolUse (broad), PreCompact, PreToolUse (per-tool), UserPromptSubmit, SessionStart
- [ ] Use `${CLAUDE_PLUGIN_ROOT}` in all command paths
- [ ] PreToolUse: normalize tool names → canonical, then route with decision objects
- [ ] guidanceOnce: atomic O_EXCL file markers + in-memory Set, scoped to process.ppid
- [ ] PostToolUse: SQLite writes only, <20ms, silent fallback, no output needed
- [ ] PreCompact: build ≤2KB XML snapshot, `console.log(JSON.stringify({}))`
- [ ] SessionStart: lifecycle branch (startup/compact/resume/clear), return `{ additionalContext }`
- [ ] All hooks: `try/catch {}` silent fallback, `fileURLToPath` for paths, suppress-stderr
