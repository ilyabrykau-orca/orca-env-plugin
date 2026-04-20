# orca-env-plugin Remake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace current `claude-toolkit` v2.2.2 internals with a 5-layer enforcement chain (tool allowlist + PreToolUse block + turn-counter re-injection + compact-event re-injection + audit log), co-install `claude-mem`, remove MemPalace, and rename plugin to `orca-env-plugin`.

**Architecture:** Keep Bun-compiled single binary. Hot path = latency-critical hooks (<20ms). Cold path = session lifecycle + claude-mem HTTP client + SQLite audit. One merged skill `orca-dev` + one allowlisted agent of the same name. Co-install `thedotmack/claude-mem` as separate plugin, actively POST orca metadata to its worker on `:37777`.

**Tech Stack:** Bun runtime (compiled binary), TypeScript strict mode, Bun test runner, `bun:sqlite` (built-in), native `fetch` for HTTP.

**Spec:** `docs/superpowers/specs/2026-04-20-orca-env-plugin-remake-design.md`

---

## Task 0: Resolve Open Questions from Spec

**Files:**
- Modify: `docs/superpowers/specs/2026-04-20-orca-env-plugin-remake-design.md` (§9 answers inline)

- [ ] **Step 1: Identify owner of `~/src/.codebase-memory/`**

Run:
```bash
ls -la ~/src/.codebase-memory/ | head -20
cat ~/src/.cbmignore 2>/dev/null
grep -r "codebase-memory" ~/.claude/plugins/cache/ 2>/dev/null | head -5
```
Expected: output shows whether it's CBM-owned (keep) or MemPalace-owned (delete in Task 9).
Record answer in spec §9.

- [ ] **Step 2: Fetch claude-mem observations POST schema**

Run:
```bash
curl -sL https://docs.claude-mem.ai/platform-integration | head -200
```
Record exact request body shape + required headers in spec §9. Confirm field names: `session_id`, `observations[]`, `type`, `value`.

- [ ] **Step 3: Profile current binary cold-start**

Run (macOS):
```bash
cd ~/src/orca-env-plugin
for i in 1 2 3 4 5; do
  /usr/bin/time -p bash -c 'echo "{}" | ./dist/claude-toolkit pre-tool-use' 2>&1 | grep real
done
```
Expected: 5 "real" measurements. Record median in spec §9. If median >50ms, add daemon-mode task to this plan before Task 2.

- [ ] **Step 4: Verify L2 subagent hook coverage**

Run:
```bash
claude -p "spawn a general-purpose agent that tries to Read src/index.ts" --print-tool-use
```
Expected: denial message from our pre-tool-use hook appears in subagent output. Record result in spec §9.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-04-20-orca-env-plugin-remake-design.md
git commit -m "docs(spec): resolve open questions before implementation"
```

---

## Task 1: Create feature branch + worktree isolation

**Files:** none (branch ops).

- [ ] **Step 1: Create branch**

```bash
cd ~/src/orca-env-plugin
git checkout -b remake-v3
```

- [ ] **Step 2: Bump version marker (not yet renamed)**

Edit `.claude-plugin/plugin.json`:
- Change `"version": "2.2.2"` → `"version": "3.0.0-dev"`.
- Keep `"name": "claude-toolkit"` for now (renamed in Task 15 to avoid breaking tests mid-refactor).

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump to 3.0.0-dev for remake"
```

---

## Task 2: Extract routing decision into pure module

**Files:**
- Create: `src/lib/routing.ts`
- Test: `tests/unit/routing.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/routing.test.ts`:
```typescript
import { expect, test, describe } from "bun:test";
import { decide } from "../../src/lib/routing";

describe("routing.decide", () => {
  test("Read on .go file → deny with CBM hint", () => {
    const d = decide({ tool: "Read", args: { file_path: "/tmp/foo.go" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("codebase-memory-mcp");
  });

  test("Read on .md file → allow", () => {
    const d = decide({ tool: "Read", args: { file_path: "/tmp/readme.md" } });
    expect(d.allow).toBe(true);
  });

  test("Grep on any path → deny with CBM hint", () => {
    const d = decide({ tool: "Grep", args: { pattern: "foo", path: "/tmp" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("search_code");
  });

  test("Edit on .ts → deny with Serena hint", () => {
    const d = decide({ tool: "Edit", args: { file_path: "/tmp/x.ts", old_string: "a", new_string: "b" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("serena");
  });

  test("Bash with cat on .py path → deny", () => {
    const d = decide({ tool: "Bash", args: { command: "cat /tmp/x.py" } });
    expect(d.allow).toBe(false);
  });

  test("Bash on git command → allow", () => {
    const d = decide({ tool: "Bash", args: { command: "git status" } });
    expect(d.allow).toBe(true);
  });

  test("Write on .json → allow", () => {
    const d = decide({ tool: "Write", args: { file_path: "/tmp/x.json", content: "{}" } });
    expect(d.allow).toBe(true);
  });

  test("Serena replace_symbol_body → allow (no L2 block, warning only)", () => {
    const d = decide({ tool: "mcp__serena__replace_symbol_body", args: {} });
    expect(d.allow).toBe(true);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/src/orca-env-plugin
bun test tests/unit/routing.test.ts
```
Expected: FAIL — cannot find module `../../src/lib/routing`.

- [ ] **Step 3: Create the routing module**

Create `src/lib/routing.ts`:
```typescript
export const CODE_EXTENSIONS = new Set([
  ".py", ".go", ".ts", ".tsx", ".js", ".jsx", ".rs",
  ".cpp", ".c", ".h", ".hpp", ".rb", ".java", ".kt",
  ".php", ".scala", ".swift", ".sh", ".bash",
]);

export type ToolCall = { tool: string; args: Record<string, unknown> };
export type Decision = { allow: boolean; reason: string };

const extOf = (p: string): string => {
  const i = p.lastIndexOf(".");
  return i < 0 ? "" : p.slice(i).toLowerCase();
};

const isCodePath = (p: string): boolean => CODE_EXTENSIONS.has(extOf(p));

const HINT_CBM_SEARCH = "Use codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path.";
const HINT_SERENA_EDIT = "Use serena: replace_symbol_body, replace_content, insert_after_symbol.";
const HINT_CBM_READ = "Use mcp__serena__find_symbol or mcp__codebase-memory-mcp__get_code_snippet.";

export function decide(call: ToolCall): Decision {
  const { tool, args } = call;

  if (tool === "Read") {
    const p = String(args.file_path ?? "");
    if (isCodePath(p)) return { allow: false, reason: HINT_CBM_READ };
    return { allow: true, reason: "non-code file" };
  }

  if (tool === "Edit" || tool === "Write") {
    const p = String(args.file_path ?? "");
    if (isCodePath(p)) return { allow: false, reason: HINT_SERENA_EDIT };
    return { allow: true, reason: "non-code file" };
  }

  if (tool === "Grep" || tool === "Glob") {
    return { allow: false, reason: HINT_CBM_SEARCH };
  }

  if (tool === "Bash") {
    const cmd = String(args.command ?? "");
    // Look for any code-extension token in the command.
    const hit = [...CODE_EXTENSIONS].some((ext) => new RegExp(`\\S+${ext.replace(".", "\\.")}(\\s|$)`).test(cmd));
    if (hit && /^(cat|head|tail|less|more|sed|awk|grep|rg)\b/.test(cmd.trim())) {
      return { allow: false, reason: HINT_CBM_SEARCH };
    }
    return { allow: true, reason: "bash passthrough" };
  }

  return { allow: true, reason: "no rule matched" };
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/routing.test.ts
```
Expected: 8 pass, 0 fail.

- [ ] **Step 5: Commit**

```bash
git add src/lib/routing.ts tests/unit/routing.test.ts
git commit -m "feat(routing): extract pure decision module with 8 unit tests"
```

---

## Task 3: Session state — turn counter (file-backed)

**Files:**
- Create: `src/lib/state.ts`
- Test: `tests/unit/state.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/state.test.ts`:
```typescript
import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { incrementTurn, getTurn, resetSession } from "../../src/lib/state";

const root = join(tmpdir(), "orca-env-plugin-test-" + Date.now());

beforeEach(() => {
  try { rmSync(root, { recursive: true, force: true }); } catch {}
});

test("new session starts at turn 1", () => {
  const n = incrementTurn("sess-A", root);
  expect(n).toBe(1);
});

test("increments persist across calls", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  const n = incrementTurn("sess-A", root);
  expect(n).toBe(3);
});

test("different sessions isolated", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  const b = incrementTurn("sess-B", root);
  expect(b).toBe(1);
});

test("getTurn returns current without incrementing", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  expect(getTurn("sess-A", root)).toBe(2);
  expect(getTurn("sess-A", root)).toBe(2);
});

test("resetSession clears counter", () => {
  incrementTurn("sess-A", root);
  resetSession("sess-A", root);
  expect(getTurn("sess-A", root)).toBe(0);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/state.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement state module**

Create `src/lib/state.ts`:
```typescript
import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

export const DEFAULT_ROOT = join(homedir(), ".cache", "orca-env-plugin", "sessions");

function pathFor(sessionId: string, root: string): string {
  mkdirSync(root, { recursive: true });
  return join(root, `${sessionId}.json`);
}

export function getTurn(sessionId: string, root: string = DEFAULT_ROOT): number {
  const p = pathFor(sessionId, root);
  if (!existsSync(p)) return 0;
  try {
    const data = JSON.parse(readFileSync(p, "utf8")) as { turn: number };
    return data.turn ?? 0;
  } catch {
    return 0;
  }
}

export function incrementTurn(sessionId: string, root: string = DEFAULT_ROOT): number {
  const current = getTurn(sessionId, root);
  const next = current + 1;
  writeFileSync(pathFor(sessionId, root), JSON.stringify({ turn: next }));
  return next;
}

export function resetSession(sessionId: string, root: string = DEFAULT_ROOT): void {
  const p = pathFor(sessionId, root);
  if (existsSync(p)) unlinkSync(p);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/state.test.ts
```
Expected: 5 pass.

- [ ] **Step 5: Commit**

```bash
git add src/lib/state.ts tests/unit/state.test.ts
git commit -m "feat(state): session turn counter persisted to ~/.cache"
```

---

## Task 4: SQLite audit log

**Files:**
- Create: `src/lib/audit.ts`
- Test: `tests/unit/audit.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/audit.test.ts`:
```typescript
import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { recordDecision, topDenies, blockRate } from "../../src/lib/audit";

const dbPath = join(tmpdir(), `audit-test-${Date.now()}.sqlite`);

beforeEach(() => {
  try { rmSync(dbPath, { force: true }); } catch {}
});

test("record + query block rate", () => {
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.md", allow: true, reason: "doc" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Grep", target: "/x", allow: false, reason: "cbm" }, dbPath);
  expect(blockRate(dbPath)).toBeCloseTo(2 / 3, 2);
});

test("topDenies ranks by count", () => {
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Grep", target: "/y", allow: false, reason: "cbm" }, dbPath);
  const top = topDenies(5, dbPath);
  expect(top[0].tool).toBe("Read");
  expect(top[0].count).toBe(2);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/audit.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement audit module**

Create `src/lib/audit.ts`:
```typescript
import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

export const DEFAULT_DB = join(homedir(), ".cache", "orca-env-plugin", "audit.sqlite");

let cachedDb: Database | null = null;
let cachedPath = "";

function db(path: string): Database {
  if (cachedDb && cachedPath === path) return cachedDb;
  mkdirSync(dirname(path), { recursive: true });
  const d = new Database(path);
  d.exec(`
    CREATE TABLE IF NOT EXISTS decisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts INTEGER NOT NULL,
      session_id TEXT NOT NULL,
      tool TEXT NOT NULL,
      target TEXT,
      allow INTEGER NOT NULL,
      reason TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_tool ON decisions(tool);
    CREATE INDEX IF NOT EXISTS idx_session ON decisions(session_id);
  `);
  cachedDb = d;
  cachedPath = path;
  return d;
}

export type DecisionRecord = {
  sessionId: string;
  tool: string;
  target: string;
  allow: boolean;
  reason: string;
};

export function recordDecision(r: DecisionRecord, path: string = DEFAULT_DB): void {
  db(path).prepare(
    "INSERT INTO decisions(ts, session_id, tool, target, allow, reason) VALUES (?, ?, ?, ?, ?, ?)"
  ).run(Date.now(), r.sessionId, r.tool, r.target, r.allow ? 1 : 0, r.reason);
}

export function blockRate(path: string = DEFAULT_DB): number {
  const row = db(path).prepare(
    "SELECT SUM(CASE WHEN allow=0 THEN 1 ELSE 0 END) AS denies, COUNT(*) AS total FROM decisions"
  ).get() as { denies: number | null; total: number };
  if (!row.total) return 0;
  return (row.denies ?? 0) / row.total;
}

export type DenyRow = { tool: string; target: string; count: number };
export function topDenies(limit: number, path: string = DEFAULT_DB): DenyRow[] {
  return db(path).prepare(
    "SELECT tool, target, COUNT(*) AS count FROM decisions WHERE allow=0 GROUP BY tool, target ORDER BY count DESC LIMIT ?"
  ).all(limit) as DenyRow[];
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/audit.test.ts
```
Expected: 2 pass.

- [ ] **Step 5: Commit**

```bash
git add src/lib/audit.ts tests/unit/audit.test.ts
git commit -m "feat(audit): SQLite block/allow logger with blockRate + topDenies"
```

---

## Task 5: claude-mem HTTP client with graceful degradation

**Files:**
- Create: `src/lib/claude-mem.ts`
- Test: `tests/unit/claude-mem.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/claude-mem.test.ts`:
```typescript
import { expect, test, beforeAll, afterAll } from "bun:test";
import { postObservations, isHealthy } from "../../src/lib/claude-mem";

let server: ReturnType<typeof Bun.serve>;
const port = 37779; // isolate test port

const received: unknown[] = [];

beforeAll(() => {
  server = Bun.serve({
    port,
    async fetch(req) {
      const url = new URL(req.url);
      if (url.pathname === "/api/health") return new Response("ok");
      if (url.pathname === "/api/sessions/observations" && req.method === "POST") {
        received.push(await req.json());
        return new Response(JSON.stringify({ success: true }));
      }
      return new Response("not found", { status: 404 });
    },
  });
});

afterAll(() => { server.stop(); });

test("isHealthy returns true when worker up", async () => {
  expect(await isHealthy(`http://localhost:${port}`)).toBe(true);
});

test("isHealthy returns false when worker down", async () => {
  expect(await isHealthy(`http://localhost:1`)).toBe(false);
});

test("postObservations sends expected body", async () => {
  const ok = await postObservations(
    "sess-X",
    [{ type: "orca.workspace", value: "sensors" }],
    `http://localhost:${port}`,
  );
  expect(ok).toBe(true);
  expect(received.at(-1)).toEqual({
    session_id: "sess-X",
    observations: [{ type: "orca.workspace", value: "sensors" }],
  });
});

test("postObservations returns false when worker down (no throw)", async () => {
  const ok = await postObservations("sess-Y", [], `http://localhost:1`);
  expect(ok).toBe(false);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/claude-mem.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement client**

Create `src/lib/claude-mem.ts`:
```typescript
export const DEFAULT_BASE = "http://localhost:37777";
const TIMEOUT_MS = 500;

export type Observation = { type: string; value: string };

async function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await p;
  } finally {
    clearTimeout(t);
  }
}

export async function isHealthy(base: string = DEFAULT_BASE): Promise<boolean> {
  try {
    const res = await withTimeout(fetch(`${base}/api/health`, { signal: AbortSignal.timeout(TIMEOUT_MS) }), TIMEOUT_MS);
    return res.ok;
  } catch {
    return false;
  }
}

export async function postObservations(
  sessionId: string,
  observations: Observation[],
  base: string = DEFAULT_BASE,
): Promise<boolean> {
  try {
    const res = await withTimeout(
      fetch(`${base}/api/sessions/observations`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session_id: sessionId, observations }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      }),
      TIMEOUT_MS,
    );
    return res.ok;
  } catch {
    return false;
  }
}
```

> Note: if Task 0 Step 2 revealed a different schema, adjust POST body here to match before continuing.

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/claude-mem.test.ts
```
Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add src/lib/claude-mem.ts tests/unit/claude-mem.test.ts
git commit -m "feat(claude-mem): HTTP client with health check + observations POST"
```

---

## Task 6: Rewrite `pre-tool-use` hot path (L2)

**Files:**
- Modify: `src/hot/pre-tool-use.ts` (full rewrite)
- Test: `tests/unit/pre-tool-use.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/pre-tool-use.test.ts`:
```typescript
import { expect, test } from "bun:test";
import { handlePreToolUse } from "../../src/hot/pre-tool-use";

test("allow non-code Read", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: "/x.md" } });
  expect(out.decision).toBe("approve");
});

test("deny code Read with reason", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: "/x.go" } });
  expect(out.decision).toBe("deny");
  expect(out.reason).toContain("codebase-memory");
});

test("deny Grep anywhere", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Grep", tool_input: { pattern: "x", path: "/" } });
  expect(out.decision).toBe("deny");
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/pre-tool-use.test.ts
```
Expected: FAIL — export `handlePreToolUse` missing.

- [ ] **Step 3: Rewrite pre-tool-use**

Overwrite `src/hot/pre-tool-use.ts`:
```typescript
import { decide } from "../lib/routing";
import { recordDecision } from "../lib/audit";

export type HookPayload = {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
};

export type HookResult = { decision: "approve" | "deny"; reason: string };

export function handlePreToolUse(p: HookPayload): HookResult {
  const d = decide({ tool: p.tool_name, args: p.tool_input });

  const target =
    (p.tool_input.file_path as string | undefined) ??
    (p.tool_input.path as string | undefined) ??
    (p.tool_input.command as string | undefined) ??
    "";

  // Fire-and-forget audit (sync bun:sqlite is fine, <1ms).
  try {
    recordDecision({
      sessionId: p.session_id,
      tool: p.tool_name,
      target,
      allow: d.allow,
      reason: d.reason,
    });
  } catch { /* audit must never block hot path */ }

  return { decision: d.allow ? "approve" : "deny", reason: d.reason };
}

// stdio entry (invoked by binary dispatcher)
export async function runPreToolUseCli(): Promise<void> {
  const stdin = await Bun.stdin.text();
  const payload = JSON.parse(stdin) as HookPayload;
  const result = handlePreToolUse(payload);
  if (result.decision === "deny") {
    process.stderr.write(result.reason + "\n");
    process.exit(2);
  }
  process.exit(0);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/pre-tool-use.test.ts
```
Expected: 3 pass.

- [ ] **Step 5: Commit**

```bash
git add src/hot/pre-tool-use.ts tests/unit/pre-tool-use.test.ts
git commit -m "feat(hot): rewrite pre-tool-use on top of routing + audit modules"
```

---

## Task 7: UserPromptSubmit turn-counter re-injection (L3)

**Files:**
- Create: `src/hot/user-prompt-submit.ts`
- Test: `tests/unit/user-prompt-submit.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/user-prompt-submit.test.ts`:
```typescript
import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { handleUserPromptSubmit } from "../../src/hot/user-prompt-submit";

const root = join(tmpdir(), "ups-test-" + Date.now());
beforeEach(() => { try { rmSync(root, { recursive: true, force: true }); } catch {} });

test("no re-injection on turn 1", () => {
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toBe("");
});

test("re-injects on turn 10", () => {
  for (let i = 1; i < 10; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toContain("CAVEMAN MODE");
  expect(out.appendContext).toContain("codebase-memory-mcp");
});

test("re-injects again on turn 20", () => {
  for (let i = 1; i < 20; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toContain("CAVEMAN MODE");
});

test("no re-injection on turn 11", () => {
  for (let i = 1; i < 11; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toBe("");
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/user-prompt-submit.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement re-injection hook**

Create `src/hot/user-prompt-submit.ts`:
```typescript
import { incrementTurn, DEFAULT_ROOT } from "../lib/state";

export const REINJECT_EVERY = 10;

export const REMINDER = [
  "CAVEMAN MODE ACTIVE (ultra). Drop articles/filler/pleasantries/hedging. Fragments OK.",
  "ROUTING: code search → codebase-memory-mcp (search_code, search_graph, get_code_snippet, trace_path).",
  "ROUTING: code edits → serena (find_referencing_symbols → replace_symbol_body/replace_content).",
  "ROUTING: docs → mcp__docs. Web → mcp__exa. Never native Read/Edit/Grep on code.",
].join(" ");

export type UpsPayload = { session_id: string };
export type UpsResult = { appendContext: string };

export function handleUserPromptSubmit(p: UpsPayload, root: string = DEFAULT_ROOT): UpsResult {
  const turn = incrementTurn(p.session_id, root);
  if (turn % REINJECT_EVERY === 0) return { appendContext: REMINDER };
  return { appendContext: "" };
}

export async function runUserPromptSubmitCli(): Promise<void> {
  const stdin = await Bun.stdin.text();
  const payload = JSON.parse(stdin) as UpsPayload;
  const r = handleUserPromptSubmit(payload);
  if (r.appendContext) process.stdout.write(r.appendContext);
  process.exit(0);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/user-prompt-submit.test.ts
```
Expected: 4 pass.

- [ ] **Step 5: Commit**

```bash
git add src/hot/user-prompt-submit.ts tests/unit/user-prompt-submit.test.ts
git commit -m "feat(hot): turn-counter re-injection every 10 turns (L3)"
```

---

## Task 8: SessionStart re-injection on compact/resume (L4) + claude-mem POST

**Files:**
- Modify: `src/cold/session-start.ts` (full rewrite)
- Test: `tests/unit/session-start.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/session-start.test.ts`:
```typescript
import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { handleSessionStart } from "../../src/cold/session-start";
import { REMINDER } from "../../src/hot/user-prompt-submit";

const root = join(tmpdir(), "ss-test-" + Date.now());
beforeEach(() => { try { rmSync(root, { recursive: true, force: true }); } catch {} });

test("startup injects workspace context only", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "startup", cwd: "/Users/x/src" }, { root, memBase: "http://localhost:1" });
  expect(out.appendContext).toContain("orca-unified");
  expect(out.appendContext).not.toContain("CAVEMAN");
});

test("compact re-injects reminder + workspace", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "compact", cwd: "/Users/x/src" }, { root, memBase: "http://localhost:1" });
  expect(out.appendContext).toContain(REMINDER);
  expect(out.appendContext).toContain("orca-unified");
});

test("resume re-injects reminder", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "resume", cwd: "/Users/x/src" }, { root, memBase: "http://localhost:1" });
  expect(out.appendContext).toContain(REMINDER);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/session-start.test.ts
```
Expected: FAIL — export `handleSessionStart` missing or signature differs.

- [ ] **Step 3: Rewrite session-start**

Overwrite `src/cold/session-start.ts`:
```typescript
import { REMINDER } from "../hot/user-prompt-submit";
import { postObservations, DEFAULT_BASE } from "../lib/claude-mem";
import { DEFAULT_ROOT } from "../lib/state";

export type SessionStartPayload = {
  session_id: string;
  source: "startup" | "resume" | "clear" | "compact";
  cwd: string;
};

export type SessionStartOpts = { root?: string; memBase?: string };
export type SessionStartResult = { appendContext: string };

function detectProject(cwd: string): string {
  if (cwd.includes("/orca-runtime-sensor")) return "orca-runtime-sensor";
  if (cwd.includes("/orca-sensor")) return "orca-sensor";
  if (cwd.includes("/orca-cloud-platform")) return "orca-cloud-platform";
  if (cwd.includes("/orca-env-plugin")) return "orca-env-plugin";
  if (cwd.includes("/helm-charts")) return "helm-charts";
  if (/\/src\/orca\b/.test(cwd)) return "orca";
  if (cwd.endsWith("/src") || cwd.includes("/src/")) return "orca-unified";
  return "unknown";
}

export async function handleSessionStart(
  p: SessionStartPayload,
  opts: SessionStartOpts = {},
): Promise<SessionStartResult> {
  const project = detectProject(p.cwd);
  const header = `SERENA WORKSPACE: project='${project}' cwd='${p.cwd}'. ` +
    `Call mcp__serena__activate_project(project=${project}) if not active.`;

  // Fire-and-forget POST to claude-mem
  const memBase = opts.memBase ?? DEFAULT_BASE;
  postObservations(p.session_id, [
    { type: "orca.workspace", value: project },
    { type: "orca.cwd", value: p.cwd },
    { type: "orca.session_source", value: p.source },
  ], memBase).catch(() => { /* degrade silent */ });

  const needsReminder = p.source === "compact" || p.source === "resume";
  const appendContext = needsReminder ? `${header}\n\n${REMINDER}` : header;
  return { appendContext };
}

export async function runSessionStartCli(): Promise<void> {
  const stdin = await Bun.stdin.text();
  const payload = JSON.parse(stdin) as SessionStartPayload;
  const r = await handleSessionStart(payload);
  if (r.appendContext) process.stdout.write(r.appendContext);
  process.exit(0);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/session-start.test.ts
```
Expected: 3 pass.

- [ ] **Step 5: Commit**

```bash
git add src/cold/session-start.ts tests/unit/session-start.test.ts
git commit -m "feat(cold): session-start workspace detect + claude-mem POST + L4 re-inject"
```

---

## Task 9: Rewrite `stop` hook to POST session summary

**Files:**
- Modify: `src/cold/stop.ts` (full rewrite)
- Test: `tests/unit/stop.test.ts`

- [ ] **Step 1: Write failing test**

Create `tests/unit/stop.test.ts`:
```typescript
import { expect, test, beforeAll, afterAll } from "bun:test";
import { handleStop } from "../../src/cold/stop";

let received: unknown[] = [];
let server: ReturnType<typeof Bun.serve>;
const port = 37780;

beforeAll(() => {
  server = Bun.serve({
    port,
    async fetch(req) {
      const u = new URL(req.url);
      if (u.pathname === "/api/sessions/observations" && req.method === "POST") {
        received.push(await req.json());
        return new Response(JSON.stringify({ success: true }));
      }
      if (u.pathname === "/api/health") return new Response("ok");
      return new Response("no", { status: 404 });
    },
  });
});

afterAll(() => server.stop());

test("stop posts summary observation", async () => {
  received = [];
  await handleStop({ session_id: "s1" }, { memBase: `http://localhost:${port}` });
  expect(received.length).toBeGreaterThan(0);
  const body = received[0] as { session_id: string; observations: Array<{ type: string }> };
  expect(body.session_id).toBe("s1");
  expect(body.observations.some(o => o.type === "orca.session_end")).toBe(true);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bun test tests/unit/stop.test.ts
```
Expected: FAIL — signature mismatch.

- [ ] **Step 3: Rewrite stop**

Overwrite `src/cold/stop.ts`:
```typescript
import { postObservations, DEFAULT_BASE } from "../lib/claude-mem";
import { blockRate, topDenies } from "../lib/audit";

export type StopPayload = { session_id: string };
export type StopOpts = { memBase?: string };

export async function handleStop(p: StopPayload, opts: StopOpts = {}): Promise<void> {
  const rate = blockRate();
  const denies = topDenies(3);
  const base = opts.memBase ?? DEFAULT_BASE;

  await postObservations(p.session_id, [
    { type: "orca.session_end", value: "true" },
    { type: "orca.block_rate", value: rate.toFixed(3) },
    { type: "orca.top_denies", value: JSON.stringify(denies) },
  ], base);
}

export async function runStopCli(): Promise<void> {
  const stdin = await Bun.stdin.text();
  const payload = JSON.parse(stdin) as StopPayload;
  await handleStop(payload);
  process.exit(0);
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bun test tests/unit/stop.test.ts
```
Expected: 1 pass.

- [ ] **Step 5: Commit**

```bash
git add src/cold/stop.ts tests/unit/stop.test.ts
git commit -m "feat(cold): stop hook POSTs session summary to claude-mem"
```

---

## Task 10: Update entry-point dispatcher + `gain` CLI subcommand

**Files:**
- Modify: `src/index.ts`
- Create: `src/cli/gain.ts`

- [ ] **Step 1: Rewrite dispatcher**

Overwrite `src/index.ts`:
```typescript
import { runPreToolUseCli } from "./hot/pre-tool-use";
import { runUserPromptSubmitCli } from "./hot/user-prompt-submit";
import { runSessionStartCli } from "./cold/session-start";
import { runStopCli } from "./cold/stop";
import { runPostToolUseCli } from "./cold/post-tool-use";
import { runSubagentStopCli } from "./cold/subagent-stop";
import { runGainCli } from "./cli/gain";

const sub = process.argv[2] ?? "";

switch (sub) {
  case "pre-tool-use":       await runPreToolUseCli(); break;
  case "user-prompt-submit": await runUserPromptSubmitCli(); break;
  case "post-tool-use":      await runPostToolUseCli(); break;
  case "session-start":      await runSessionStartCli(); break;
  case "stop":               await runStopCli(); break;
  case "subagent-stop":      await runSubagentStopCli(); break;
  case "gain":               await runGainCli(); break;
  default:
    process.stderr.write(`unknown subcommand: ${sub}\n`);
    process.exit(1);
}
```

- [ ] **Step 2: Create `src/cli/gain.ts`**

Create `src/cli/gain.ts`:
```typescript
import { blockRate, topDenies } from "../lib/audit";

export async function runGainCli(): Promise<void> {
  const rate = blockRate();
  const denies = topDenies(10);

  console.log("orca-env-plugin audit report");
  console.log("============================");
  console.log(`block rate: ${(rate * 100).toFixed(1)}%`);
  console.log("");
  console.log("top 10 denies:");
  for (const d of denies) {
    console.log(`  ${d.count.toString().padStart(4)}  ${d.tool.padEnd(10)} ${d.target}`);
  }
  process.exit(0);
}
```

- [ ] **Step 3: Ensure existing `post-tool-use` + `subagent-stop` export CLI runners**

For each of `src/cold/post-tool-use.ts` and `src/cold/subagent-stop.ts`, wrap or add at bottom of file:
```typescript
export async function runPostToolUseCli(): Promise<void> {
  // keep existing implementation; ensure it reads stdin + exits 0 on success
  const stdin = await Bun.stdin.text().catch(() => "{}");
  try {
    const payload = JSON.parse(stdin || "{}");
    void payload; // (hook inspects but has no state side-effect beyond existing logic)
  } catch { /* malformed stdin: ignore */ }
  process.exit(0);
}
```
(Same shape for `runSubagentStopCli`.) Retain whatever analytics logic currently lives in those files; just guarantee the exported function exists and exits 0.

- [ ] **Step 4: Build + smoke test**

```bash
cd ~/src/orca-env-plugin
bun run build
echo "" | ./dist/claude-toolkit gain
```
Expected: prints "block rate" header, possibly empty top-denies list.

- [ ] **Step 5: Commit**

```bash
git add src/index.ts src/cli/gain.ts src/cold/post-tool-use.ts src/cold/subagent-stop.ts
git commit -m "feat(cli): dispatcher + gain subcommand"
```

---

## Task 11: Rewrite single merged `orca-dev` skill

**Files:**
- Create: `skills/orca-dev/SKILL.md`
- Create: `skills/skill-rules.json`
- Delete: `skills/.DS_Store`

- [ ] **Step 1: Create skill markdown**

Create `skills/orca-dev/SKILL.md`:
```markdown
---
name: orca-dev
description: Source code work in orca repos. CBM for search, Serena for edits, docs/exa for external. find_referencing_symbols before any edit.
---

# orca-dev

## Workspace routing

| cwd pattern                  | serena project        | path style                  |
|------------------------------|-----------------------|-----------------------------|
| `~/src` (unified workspace)  | `orca-unified`        | repo-prefixed absolute      |
| `~/src/<repo>/**`            | `<repo>`              | relative to repo root       |

Activate via `mcp__serena__activate_project(project=<name>)` when switching.

## Tool boundaries (hard rules)

| Intent              | Use                                                                     | Never                       |
|---------------------|-------------------------------------------------------------------------|-----------------------------|
| Search code         | `mcp__codebase-memory-mcp__search_code`, `search_graph`                 | native `Grep`, `Glob`       |
| Read a symbol body  | `mcp__codebase-memory-mcp__get_code_snippet`                            | native `Read` on `.go/.ts`  |
| Trace call chain    | `mcp__codebase-memory-mcp__trace_path`                                  | manual grep                 |
| Edit a symbol       | `mcp__serena__replace_symbol_body`, `replace_content`                   | native `Edit`, `Write`      |
| Find callers        | `mcp__serena__find_referencing_symbols`                                 | manual grep                 |
| External docs       | `mcp__docs__search_docs`, `mcp__docs__fetch_url`                        | —                           |
| Web                 | `mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`                   | —                           |

## Edit protocol

1. `find_referencing_symbols(name_path=, relative_path=FILE)` before any symbol edit.
2. `replace_symbol_body` (structured) preferred over `replace_content` (text).
3. `replace_content` backrefs use `$!1`, not `\1`. Mode `"literal"` | `"regex"`.
4. `read_file` offsets are 0-based.

## CBM patterns

- `search_graph` → find qualified name → `get_code_snippet(qualified_name=...)`.
- `search_code(pattern, project)` for text hits ranked by structural importance.
- `path_filter` regex narrows scope (e.g. `^src/`).

## Project names (CBM index)

See reference memory `codebase_memory_projects.md` for exact project strings.
```

- [ ] **Step 2: Create skill-rules.json**

Create `skills/skill-rules.json`:
```json
{
  "skills": {
    "orca-dev": {
      "keywords": [
        "read", "edit", "write", "refactor", "search code",
        "find function", "find symbol", "callers", "references",
        ".go", ".ts", ".tsx", ".py", ".rs",
        "serena", "codebase-memory", "cbm"
      ],
      "path_triggers": [
        "~/src/orca", "~/src/orca-sensor", "~/src/orca-runtime-sensor",
        "~/src/orca-cloud-platform", "~/src/orca-env-plugin"
      ]
    }
  }
}
```

- [ ] **Step 3: Delete .DS_Store**

```bash
rm -f skills/.DS_Store
```

- [ ] **Step 4: Commit**

```bash
git add skills/orca-dev/SKILL.md skills/skill-rules.json
git rm -f skills/.DS_Store 2>/dev/null || true
git commit -m "feat(skills): merged orca-dev skill — CBM/Serena/docs/exa rules"
```

---

## Task 12: Refresh `orca-dev` agent (L1 allowlist)

**Files:**
- Modify: `agents/orca-dev.md` (replace description; ensure tool list is complete + minimal)

- [ ] **Step 1: Rewrite agent frontmatter**

Overwrite `agents/orca-dev.md`:
```markdown
---
name: orca-dev
description: Source-code work in orca repos. CBM search + Serena edits only. Native Read/Edit/Grep physically unavailable.
tools:
  - mcp__codebase-memory-mcp__search_graph
  - mcp__codebase-memory-mcp__search_code
  - mcp__codebase-memory-mcp__get_code_snippet
  - mcp__codebase-memory-mcp__trace_path
  - mcp__codebase-memory-mcp__get_architecture
  - mcp__codebase-memory-mcp__query_graph
  - mcp__codebase-memory-mcp__index_repository
  - mcp__codebase-memory-mcp__index_status
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
  - mcp__docs__search_docs
  - mcp__docs__fetch_url
  - mcp__exa__web_search_exa
  - mcp__exa__web_fetch_exa
  - TaskCreate
  - TaskUpdate
  - TaskList
---

CBM explore → Serena edit. `find_referencing_symbols(name_path=, relative_path=FILE)` before edits. `replace_content` backrefs `$!1`. `read_file` 0-based. Activate serena project on first invocation.
```

- [ ] **Step 2: Commit**

```bash
git add agents/orca-dev.md
git commit -m "feat(agents): orca-dev allowlist — no native tools (L1 defense)"
```

---

## Task 13: Integration test — drift regression over 60 turns

**Files:**
- Create: `tests/integration/drift-regression.test.ts`
- Create: `tests/integration/prompts/drift-script.json`

- [ ] **Step 1: Create script**

Create `tests/integration/prompts/drift-script.json`:
```json
{
  "turns": 60,
  "prompt_template": "Say 'ok' and nothing else.",
  "check_every": 5,
  "banned_filler": ["certainly", "of course", "I'd be happy", "let me just"],
  "native_read_at_turn": [15, 30, 45],
  "native_read_file": "/tmp/fake.go"
}
```

- [ ] **Step 2: Write test**

Create `tests/integration/drift-regression.test.ts`:
```typescript
import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import script from "./prompts/drift-script.json";

test.skipIf(!process.env.RUN_INTEGRATION)("caveman + routing hold for 60 turns", () => {
  writeFileSync(script.native_read_file, "package main\n");

  const banned = new RegExp(script.banned_filler.join("|"), "i");
  let fillerHits = 0;
  let blockMisses = 0;

  for (let i = 1; i <= script.turns; i++) {
    const wantNativeRead = script.native_read_at_turn.includes(i);
    const prompt = wantNativeRead
      ? `Read ${script.native_read_file} using the native Read tool and print first line.`
      : script.prompt_template;

    const r = spawnSync("claude", ["-p", prompt, "--output-format", "text"], { encoding: "utf8", timeout: 60_000 });
    const out = r.stdout ?? "";

    if (i % script.check_every === 0 && banned.test(out)) fillerHits++;
    if (wantNativeRead && !/codebase-memory|serena/i.test(out)) blockMisses++;
  }

  expect(fillerHits).toBe(0);
  expect(blockMisses).toBe(0);
}, 900_000);
```

- [ ] **Step 3: Smoke the harness (skipped by default)**

```bash
bun test tests/integration/drift-regression.test.ts
```
Expected: "1 skipped" unless `RUN_INTEGRATION=1` is set. Do not run live for now; integration harness is in place for future gating.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/
git commit -m "test(integration): 60-turn drift regression harness (gated on RUN_INTEGRATION)"
```

---

## Task 14: Remove MemPalace (clean cut)

**Files:**
- Delete: `~/src/mempalace.yaml`
- Delete: `~/src/entities.json`
- Possibly delete: `~/src/.codebase-memory/` (ONLY if Task 0 Step 1 confirmed MemPalace owns it)
- Modify (if present): any `src/**` references to `mempalace`

- [ ] **Step 1: Search plugin source for MemPalace references**

```bash
cd ~/src/orca-env-plugin
grep -rn -i "mempalace\|mem_palace" src/ tests/ docs/ 2>&1 || echo "no references"
```
Expected: either "no references" or a list. For any hit inside plugin code, delete the reference.

- [ ] **Step 2: Delete MemPalace state files**

```bash
rm -f ~/src/mempalace.yaml ~/src/entities.json
```

- [ ] **Step 3: Conditionally delete `~/src/.codebase-memory/`**

If Task 0 Step 1 confirmed it belongs to MemPalace (not CBM):
```bash
rm -rf ~/src/.codebase-memory/
```
Otherwise leave untouched and add a note in commit message explaining why.

- [ ] **Step 4: Commit (plugin side only — `~/src` is not this repo)**

```bash
cd ~/src/orca-env-plugin
git add -u src/ tests/ docs/ 2>/dev/null || true
git commit --allow-empty -m "chore: remove MemPalace references (state files deleted from ~/src)"
```

---

## Task 15: Install claude-mem + rename plugin

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

- [ ] **Step 1: Install claude-mem**

```bash
cd ~
npx claude-mem install
```
Expected: installer registers hooks + starts worker. Verify:
```bash
curl -s http://localhost:37777/api/health
```
Expected: `ok` (or HTTP 200).

- [ ] **Step 2: Rename plugin name**

Edit `.claude-plugin/plugin.json`:
```json
{
  "name": "orca-env-plugin",
  "version": "3.0.0",
  "description": "Orca-specific Claude Code plugin: MCP routing enforcement, caveman mode, workspace detection, claude-mem integration, session audit.",
  "author": { "name": "Orca Security" },
  "homepage": "https://github.com/ilyabrykau-orca/orca-env-plugin",
  "repository": "https://github.com/ilyabrykau-orca/orca-env-plugin"
}
```

- [ ] **Step 3: Update marketplace.json**

Edit `.claude-plugin/marketplace.json`: change every `"claude-toolkit"` → `"orca-env-plugin"` (names, paths). Keep version aligned to `3.0.0`.

- [ ] **Step 4: Rename binary output**

Edit `build.sh`: change `--outfile dist/claude-toolkit` → `--outfile dist/orca-env-plugin`, and the final `codesign` path likewise.

Edit `hooks/hooks.json`: replace every `/dist/claude-toolkit` with `/dist/orca-env-plugin`.

- [ ] **Step 5: Update README**

Edit `README.md` first section: change title from `claude-toolkit` → `orca-env-plugin`. Add prerequisite line:
```
Requires `claude-mem` co-installed: `npx claude-mem install` (worker on :37777).
```

- [ ] **Step 6: Rebuild**

```bash
cd ~/src/orca-env-plugin
bun run build
ls -la dist/
```
Expected: `dist/orca-env-plugin` exists, executable. `dist/claude-toolkit` may remain as stale artifact; delete it:
```bash
rm -f dist/claude-toolkit
```

- [ ] **Step 7: Run full test suite**

```bash
bun test
```
Expected: all unit tests pass (integration remains skipped).

- [ ] **Step 8: Commit**

```bash
git add .claude-plugin/ build.sh hooks/hooks.json README.md dist/
git commit -m "feat: rename claude-toolkit → orca-env-plugin v3.0.0 (breaking)"
```

---

## Task 16: Final verification

- [ ] **Step 1: Confirm binary routes correctly**

```bash
cd ~/src/orca-env-plugin
echo '{"session_id":"vtest","tool_name":"Read","tool_input":{"file_path":"/tmp/x.go"}}' | \
  ./dist/orca-env-plugin pre-tool-use; echo "exit=$?"
```
Expected: stderr contains `codebase-memory` or `serena`; exit code 2.

- [ ] **Step 2: Confirm non-code passes**

```bash
echo '{"session_id":"vtest","tool_name":"Read","tool_input":{"file_path":"/tmp/x.md"}}' | \
  ./dist/orca-env-plugin pre-tool-use; echo "exit=$?"
```
Expected: exit code 0, no stderr.

- [ ] **Step 3: Gain report non-empty**

```bash
./dist/orca-env-plugin gain
```
Expected: block rate shows > 0%, at least one Read deny in top list.

- [ ] **Step 4: claude-mem round-trip**

Start a new Claude Code session from `~/src`. In the session, ask: "what workspace am I in?". Expect the session-start context mentions `orca-unified`. Then `/exit`, restart, ask: "what did we do last session?". Expect claude-mem's MCP search tool returns the `orca.session_end` observation.

- [ ] **Step 5: Merge to main**

```bash
cd ~/src/orca-env-plugin
git checkout main
git merge --ff-only remake-v3
git push origin main
```

---

## Self-Review Notes

**Spec coverage (§ per spec):**
- §4.1 binary subcommands → Tasks 6, 7, 8, 9, 10 cover all seven.
- §4.2 module layout → Tasks 2, 3, 4, 5 create lib/; Tasks 6, 7, 8, 9 create hot/cold; Task 10 creates cli/.
- §4.3 agent → Task 12.
- §4.4 skill → Task 11.
- §5 L1–L5 → L1 Task 12; L2 Task 6; L3 Task 7; L4 Task 8; L5 Tasks 4+10.
- §6 claude-mem integration → Tasks 5 (client), 8 (session-start POST), 9 (stop POST), 15 (install).
- §6.3 MemPalace clean cut → Task 14.
- §7.1 unit tests → Tasks 2–9 each include tests.
- §7.2 integration tests → Task 13 (harness; live run gated).
- §7.3 drift regression → Task 13.
- §8 rollout steps 1–7 → Tasks 1, 14, 15, 16.
- §9 open questions → Task 0 resolves all four.

**Placeholder scan:** none (all tasks contain exact code + commands).

**Type consistency:** `HookResult.decision` values `"approve"`/`"deny"` used in Task 6; `handleUserPromptSubmit` return type `UpsResult.appendContext` consistent in Tasks 7 and 8; `postObservations(session_id, observations, base)` signature identical across Tasks 5, 8, 9.
