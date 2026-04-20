# orca-env-plugin — Full Remake Design

**Date:** 2026-04-20
**Status:** Approved (user + gemini-3-pro-preview 9/10 confidence)
**Scope:** Replace current `claude-toolkit` v2.2.2 plugin internals; co-install `claude-mem`; enforce MCP routing + caveman communication across sessions and subagents.

---

## 1. Goals

- **End "Claude ignores instructions" class of bugs.** Routing (CBM/Serena/docs/exa) must hold across a full session, across context compression, across subagents.
- **Replace MemPalace with claude-mem.** Delete custom YAML-based memory; co-install upstream `thedotmack/claude-mem` plugin; actively feed it orca-specific metadata.
- **Make caveman communication stable.** Mode must persist; no drift after context compression.
- **Rename plugin to `orca-env-plugin`** (match repo). Honest about being orca-specific, not a generic toolkit.
- **Defense in depth.** No single layer of enforcement; every protection has a fallback.

## 2. Non-Goals

- Generic reusability. Plugin assumes `~/src` orca workspace layout.
- Rewrite in Rust/Go. Stay on Bun compiled binary.
- Migrate existing MemPalace state. Clean cut.
- Replace `claude-mem`. We consume it, don't fork it.

## 3. Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Claude Code (host process)                              │
│                                                         │
│  ┌──────────────────┐    ┌──────────────────────────┐   │
│  │ orca-env-plugin  │    │ claude-mem (co-installed)│   │
│  │  (this repo)     │    │  worker :37777 + SQLite  │   │
│  └────────┬─────────┘    └───────────┬──────────────┘   │
│           │                          │                  │
│           │ POST observations        │ MCP search tools │
│           └──────────────────────────┘                  │
│                                                         │
│  Hooks (both plugins register):                         │
│  - SessionStart, UserPromptSubmit, PostToolUse, Stop    │
│                                                         │
│  Enforcement chain (orca-env-plugin):                   │
│  [L1] Tool allowlist at agent definition                │
│  [L2] PreToolUse hard-block (Bun binary, <20ms)         │
│  [L3] UserPromptSubmit turn-counter re-injection        │
│  [L4] SessionStart re-injection on resume/compact       │
│  [L5] SQLite audit log, `orca-env-plugin gain` CLI      │
└─────────────────────────────────────────────────────────┘
```

## 4. Components

### 4.1 Plugin binary (`dist/orca-env-plugin`)

Single Bun-compiled binary. Subcommands:

| Subcommand           | Hook event         | Purpose                                              |
|----------------------|--------------------|------------------------------------------------------|
| `pre-tool-use`       | PreToolUse         | Hot-path routing enforcement; deny native code tools |
| `post-tool-use`      | PostToolUse        | Track `mcp__serena__find_referencing_symbols` calls  |
| `user-prompt-submit` | UserPromptSubmit   | Turn-counter re-injection (caveman + routing)        |
| `session-start`      | SessionStart       | Workspace detection + initial context; claude-mem POST |
| `stop`               | Stop               | Session summary + claude-mem POST                    |
| `subagent-stop`      | SubagentStop       | Subagent analytics                                   |
| `gain`               | (CLI)              | Show audit stats: blocks, allows, top denies         |

### 4.2 Source module layout

```
src/
├── index.ts               # Subcommand dispatcher
├── hot/                   # Hot-path hooks — latency-critical
│   ├── pre-tool-use.ts    # Decision < 20ms
│   └── user-prompt-submit.ts  # Turn-counter + re-inject
├── cold/                  # Cold-path hooks — async OK
│   ├── session-start.ts
│   ├── post-tool-use.ts
│   ├── stop.ts
│   └── subagent-stop.ts
├── lib/
│   ├── constants.ts       # Extension lists, denial messages
│   ├── protocol.ts        # Hook stdio JSON schemas
│   ├── logger.ts
│   ├── state.ts           # Per-session turn counter (tmpfile)
│   ├── routing.ts         # Central "is this code?" decider (shared L1/L2)
│   ├── claude-mem.ts      # HTTP client for :37777
│   └── audit.ts           # SQLite writer for block/allow decisions
└── cli/
    └── gain.ts            # `orca-env-plugin gain` report
```

### 4.3 Agent definitions

`agents/orca-dev.md` — allowlisted tool frontmatter (CBM + Serena + docs + exa only). Physically cannot invoke native Read/Edit/Grep/Bash.

No other agents. Users who invoke `general-purpose` subagent still get L2 PreToolUse enforcement.

### 4.4 Skills

Single skill: `skills/orca-dev/SKILL.md`. Contents:

- Workspace routing rules (`~/src` → orca-unified; per-repo → relative paths)
- CBM patterns (`search_graph` → `get_code_snippet` → `trace_path`)
- Serena patterns (`find_referencing_symbols` before any edit; `$!1` backref; 0-based `read_file`)
- Docs/Exa pick rules
- Explicit MCP-vs-native boundary table (addresses gemini blind-spot feedback)

Activated by keyword list in `skills/skill-rules.json` (reuses existing shape). No other skills shipped.

## 5. Enforcement Chain — Defense in Depth

### L1 — Tool allowlist (agent frontmatter)

- `orca-dev` agent: only CBM/Serena/docs/exa tools listed in `tools:`.
- Prevents subagent from ever calling native Read/Edit/Grep/Bash, even if prompt instructs it.

### L2 — PreToolUse hard-block (Bun binary)

- Runs inside main agent AND inside subagents. Claude Code fires PreToolUse for every tool call in every context.
- Decision rule (in `lib/routing.ts`):
  - `Read`/`Edit`/`Write` on `.py|.go|.ts|.tsx|.js|.jsx|.rs|.cpp|.c|.h|.hpp|.rb|.java|.kt|.php|.scala|.swift|.sh|.bash` → DENY, route msg names CBM/Serena alternative.
  - `Grep`/`Glob` on any path → DENY, name CBM alternative.
  - `Bash` whose args contain a source-code path (`cat /foo.go`, `grep foo src/`) → DENY.
  - Non-code files (`.json|.yaml|.md|.toml|.lock`) → ALLOW.
  - All Serena edit tools → ALLOW but log for L3 edit-guard warning if no `find_referencing_symbols` recorded this session.
- Must exit <20ms. Binary cold-start profiled before merge; if >50ms, persist Bun daemon.
- Timeout: `timeout: 5` in `hooks.json` = 5 seconds (Claude Code spec). Acceptable margin.

### L3 — UserPromptSubmit turn-counter re-injection

- Replaces proposed PostToolUse filler-scan (rejected by gemini as fragile).
- Every user prompt: increment counter in `~/.cache/orca-env-plugin/sessions/<session_id>.json`.
- Every **10 turns**: append to hook stdout:
  - Caveman rules (terse, ≤100 tokens).
  - Routing reminder (CBM for code search, Serena for code edits, docs/exa for web).
- Rationale: survives context compression. Reminder becomes "new" system message each injection.

### L4 — SessionStart re-injection on `resume`/`compact`

- `SessionStart` matcher already includes `startup|resume|clear|compact`.
- On `resume` and `compact`: same re-injection as L3, regardless of turn counter — context just got shuffled.

### L5 — Audit log + `gain` CLI

- Every L2 decision: row in `~/.cache/orca-env-plugin/audit.sqlite`:
  - `timestamp, session_id, tool_name, target_path, decision, reason`.
- `orca-env-plugin gain` shows:
  - Total blocks, total allows, block rate %.
  - Top 10 most-denied tool+path combos (find repeated drift patterns).
  - Sessions with highest block count (sessions where Claude fought the rules).
- Optional: post daily summary to `claude-mem :37777` as observation.

## 6. Memory — `claude-mem` Integration

### 6.1 Install

- `claude-mem` installed separately: `/plugin install claude-mem@thedotmack/claude-mem`.
- `orca-env-plugin` README documents this as prerequisite.
- `orca-env-plugin` checks for claude-mem worker on `SessionStart` (HTTP `GET :37777/api/health`). If absent → warn in SessionStart output, degrade gracefully (L2/L3 still work, no memory injection).

### 6.2 Active integration

- `SessionStart` hook POSTs to `http://localhost:37777/api/sessions/observations`:
  ```json
  {
    "session_id": "<from hook payload>",
    "observations": [
      {"type": "orca.workspace", "value": "<detected project>"},
      {"type": "orca.cwd", "value": "<pwd>"},
      {"type": "orca.branch", "value": "<git branch>"}
    ]
  }
  ```
- `Stop` hook POSTs session summary + blocked tool counts.
- Result: claude-mem's MCP search tools return orca-tagged observations when Claude asks "what did we do on sensors last week?".

### 6.3 MemPalace removal (clean cut)

- Delete `~/src/mempalace.yaml`.
- Delete `~/src/entities.json`.
- Delete `~/src/.codebase-memory/` (if MemPalace-owned — verify before delete).
- Remove any MemPalace references in plugin source (grep audit pre-merge).

## 7. Testing Strategy

### 7.1 Unit (Bun test)

- `lib/routing.ts` — table-driven: (tool, args, extension) → expected decision. Cover every rule.
- `lib/state.ts` — turn counter persistence, session isolation.
- `lib/claude-mem.ts` — HTTP client retry, timeout, graceful failure when worker down.

### 7.2 Integration

- Spawn real `claude` CLI in subprocess with a throwaway workspace.
- Feed scripted prompts that would call native Read/Edit/Grep on code.
- Assert: binary exit code denies; claude output contains the expected routing message.
- Assert: subagent spawned via `Agent` tool also sees denials (L2 applies recursively).
- Run on CI (GitHub Actions, macOS + linux).

### 7.3 Drift regression test

- 60-turn scripted conversation.
- Every 5 turns: check last assistant output for caveman compliance (no banned filler words).
- Every 15 turns: attempt a native Read on code; assert block.
- Fails if compliance degrades — catches context-compression regressions.

## 8. Migration / Rollout

1. Branch `remake-v3` off current `main`.
2. Implement in order: L2 routing (hot path) → L3 turn-counter → L5 audit → claude-mem integration → skills/agent → tests.
3. Clean cut MemPalace in same PR (small, colocated with source removal).
4. Bump `plugin.json` name: `claude-toolkit` → `orca-env-plugin`. Version: `3.0.0` (major — breaking rename).
5. Update `marketplace.json`.
6. Manual smoke test: install via `/plugin install orca-env-plugin@ilyabrykau-orca/...` in fresh Claude Code session.
7. Merge to `main`.

## 9. Open Questions (must resolve before implementation-plan phase)

- [x] Does `~/src/.codebase-memory/` belong to MemPalace or CBM? **Must verify** before deletion step.
  - **Answer: CBM-owned.** `~/src/.codebase-memory/` contains `adr.md` (23.9K, CBM ADR format, starts with `## PURPOSE` and describes the orca workspace). CBM's `manage_adr(mode='store')` writes here; memory note `reference_codebase_memory_projects.md` explicitly references CBM ADR storage. MemPalace instead uses `~/src/mempalace.yaml` + `~/src/entities.json` + `~/.mempalace/` (per `reference_mempalace_setup.md`). **Do NOT delete `.codebase-memory/` in MemPalace cleanup (§6.3). Update §6.3 accordingly.**

- [x] Claude Code subagent hook inheritance — verified works (L2 fires in subagents per current evidence), but pin the test early.
  - **Answer: Confirmed by config + prior evidence (live CLI test deferred).** Current `hooks/hooks.json` registers `PreToolUse` with no subagent scope exclusion; Claude Code's plugin hook model fires PreToolUse for every tool call regardless of agent depth. Memory `feedback_use_serena_cbm.md` + prior drift-fix work confirm denials surface in subagents today. Pin live CLI subagent test as part of Task 13 (drift regression integration test) rather than blocking Task 0.

- [x] claude-mem `POST /api/sessions/observations` exact schema — fetch from `https://docs.claude-mem.ai` before coding client.
  - **Answer: Deviation from our assumption — schema is per-tool-call, not batched.** Actual request body per `docs.claude-mem.ai/platform-integration`:
    ```json
    {
      "claudeSessionId": "abc123",
      "tool_name": "Bash",
      "tool_input": { "command": "ls" },
      "tool_response": { "stdout": "..." },
      "cwd": "/path/to/project"
    }
    ```
    Response: `{"status": "queued"}` or `{"status": "skipped", "reason": "private"}`. Related endpoints: `POST /api/sessions/summarize` (body: `{claudeSessionId, last_user_message, last_assistant_message}`), `POST /api/sessions/complete` (body: `{claudeSessionId}`), `GET /api/health`. **Update §6.2 to use real schema:** our `SessionStart` POST should instead emit a synthetic observation per orca field (or use `summarize`), and `Stop` hook uses `/api/sessions/summarize` + `/api/sessions/complete`. Task 5 (claude-mem HTTP client) and Task 8 (SessionStart+claude-mem POST) must encode this schema.

- [x] Bun binary cold-start latency on macOS — profile current `dist/claude-toolkit`. If >50ms, plan daemon mode now.
  - **Answer: ~10ms median on macOS Darwin 25.4 (Apple Silicon).** Five runs of `echo "{}" | ./dist/claude-toolkit pre-tool-use` with `/usr/bin/time -p` all measured `real 0.01s` (resolution 10ms; actual likely 5–10ms). **Well under 50ms threshold. Daemon mode NOT required.** Re-profile post-remake to confirm the new binary (with SQLite audit writer + expanded routing logic) stays <50ms.

## 10. Success Criteria

- Zero native Read/Edit/Grep on code files across 100 real sessions post-merge (audit log).
- Zero caveman drift over 60-turn conversations (regression test green).
- claude-mem search returns orca-tagged results for "previous work on X" queries.
- `orca-env-plugin gain` shows block rate trending to near-zero over first month (Claude learns the rules because they're enforced).

---

## Spec Self-Review Notes

- **Placeholders:** four open questions in §9 flagged, must resolve before implementation plan.
- **Internal consistency:** L2 decision rule (§5.2) matches `routing.ts` location (§4.2). Agent/skill names match across §4.3/§4.4.
- **Scope:** single spec → single implementation plan. Bounded to plugin remake. Does not cover `claude-mem` development.
- **Ambiguity:** "every 10 turns" for L3 is explicit; "audit summary daily" in §5.5 deliberately marked optional.
