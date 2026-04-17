# Claude Toolkit v2 Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace shell-based hooks with a single compiled Bun binary, restore v1-style native-tool enforcement routing to CBM/Serena, and add explicit tool-restricted agents.

**Architecture:** Single TypeScript entry point compiled with `bun build --compile`. Routes all hook events (PreToolUse, SessionStart, UserPromptSubmit, PostToolUse, Stop, SubagentStop) through one binary. RTK shells out to `rtk rewrite`. Native-tool-guard uses `Set.has()` lookups on pre-computed extension/path sets.

**Tech Stack:** Bun 1.3+, TypeScript, `rtk` binary (installed from source)

---

## File Map

### Create

| File | Responsibility |
|------|---------------|
| `src/index.ts` | Entry point: read stdin, route by `process.argv[2]` |
| `src/handlers/pre-tool-use.ts` | Native-tool-guard + Serena edit guard + RTK rewrite |
| `src/handlers/session-start.ts` | Project detection + MemPalace search + minimal context injection |
| `src/handlers/prompt-submit.ts` | Keyword/intent skill activation from skill-rules.json |
| `src/handlers/post-tool-use.ts` | Refs-traced state tracking for Serena edit guard |
| `src/handlers/stop.ts` | Transcript stats (Stop + SubagentStop) |
| `src/lib/constants.ts` | Extension sets, path prefixes, project map, allowed filenames/paths |
| `src/lib/protocol.ts` | Hook JSON response builders (deny, allow, warn, rewrite, context) |
| `src/lib/logger.ts` | Append JSON lines to `~/.claude/logs/hooks.jsonl` |
| `src/lib/state.ts` | Atomic read/write of state files (refs-traced) |
| `src/lib/stdin.ts` | Read all stdin into buffer, parse JSON |
| `package.json` | Bun project config + build script |
| `tsconfig.json` | TypeScript config |
| `build.sh` | Build + compile script |
| `agents/cbm-explorer.md` | CBM-only exploration agent |
| `agents/serena-editor.md` | Serena-only editing agent |
| `skills/codebase-explorer/SKILL.md` | New: replaces codanna skill |
| `scripts/compress-prompts.py` | Optional LLMLingua compression (Phase 11) |

### Modify

| File | Change |
|------|--------|
| `hooks/hooks.json` | Replace all entries to route to compiled binary |
| `skills/orca-setup/SKILL.md` | Codanna → CBM, reduce to essential content |
| `skills/docs/SKILL.md` | Remove Codanna references |
| `skills/skill-rules.json` | Richer keywords/intents, remove add-language, add web-search |
| `.gitignore` | Add `dist/` exception for compiled binary |

### Delete (after binary is working)

| File | Reason |
|------|--------|
| `hooks/pre-tool-router` | Replaced by `src/handlers/pre-tool-use.ts` |
| `hooks/session-start` | Replaced by `src/handlers/session-start.ts` |
| `hooks/skill-activation-prompt` | Replaced by `src/handlers/prompt-submit.ts` |
| `hooks/post-serena-refs` | Replaced by `src/handlers/post-tool-use.ts` |
| `hooks/stop.js` | Replaced by `src/handlers/stop.ts` |
| `hooks/subagent-stop.js` | Replaced by `src/handlers/stop.ts` |
| `hooks/utils/transcript-parser.js` | Folded into `src/handlers/stop.ts` |
| `hooks/package.json` | No longer needed |
| `skills/codanna/SKILL.md` | Dead — Codanna gone |

### Tests to update

| File | Change |
|------|--------|
| `tests/unit/test-pre-tool-use.sh` | Point at compiled binary, update expected messages (CBM not Codanna) |
| `tests/unit/test-hooks-smoke.sh` | Point at binary, update expected messages |
| `tests/unit/test-session-output.sh` | Update expected content (no Codanna refs, minimal injection) |
| `tests/unit/test-serena-guard.sh` | Point at binary for edit guard + refs tracker |
| `tests/unit/test-project-detection.sh` | Point at binary |
| `tests/helpers.sh` | Update `HOOK_SS`, `HOOK_PT` paths to binary |

---

### Task 1: Scaffold TypeScript project

**Files:**
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `build.sh`
- Modify: `.gitignore`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "claude-toolkit",
  "version": "2.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "build": "bash build.sh",
    "typecheck": "bun run --bun tsc --noEmit"
  },
  "devDependencies": {
    "@types/bun": "latest",
    "typescript": "^5.8"
  }
}
```

Write to `package.json` in plugin root (replaces nothing — there's no root package.json, only `hooks/package.json`).

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "types": ["bun-types"],
    "rootDir": "src",
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src/**/*.ts"]
}
```

- [ ] **Step 3: Create build.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p dist

bun build src/index.ts \
  --compile \
  --minify \
  --bytecode \
  --sourcemap=inline \
  --target=bun \
  --outfile dist/claude-toolkit

chmod +x dist/claude-toolkit
echo "Built dist/claude-toolkit ($(wc -c < dist/claude-toolkit | tr -d ' ') bytes)"
```

- [ ] **Step 4: Update .gitignore — add dist exception**

Append to `.gitignore`:
```
# Build artifacts
dist/
!dist/claude-toolkit
```

- [ ] **Step 5: Install deps and verify typecheck**

Run: `cd /Users/ilyabrykau/src/orca-env-plugin && bun install`
Expected: clean install

Run: `bun run typecheck`
Expected: no errors (no source files yet, so vacuous pass)

- [ ] **Step 6: Commit**

```bash
git add package.json tsconfig.json build.sh .gitignore
git commit -m "feat: scaffold TypeScript project for v2 binary hooks"
```

---

### Task 2: Shared libraries (constants, protocol, logger, state, stdin)

**Files:**
- Create: `src/lib/constants.ts`
- Create: `src/lib/protocol.ts`
- Create: `src/lib/logger.ts`
- Create: `src/lib/state.ts`
- Create: `src/lib/stdin.ts`

- [ ] **Step 1: Create src/lib/stdin.ts**

```typescript
const chunks: Buffer[] = [];
for await (const chunk of Bun.stdin.stream()) {
  chunks.push(Buffer.from(chunk));
}
const raw = Buffer.concat(chunks).toString("utf-8");

export function readStdin(): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function getRaw(): string {
  return raw;
}
```

Note: stdin must be consumed at module load time (before any handler runs) because stdin is a one-shot stream. Import this module early in index.ts.

- [ ] **Step 2: Create src/lib/constants.ts**

```typescript
import { homedir } from "os";

export const HOME = homedir();
export const SRC_PREFIX = `${HOME}/src/`;
export const CLAUDE_PREFIX = `${HOME}/.claude/`;
export const LOG_DIR = `${HOME}/.claude/logs`;
export const LOG_FILE = `${LOG_DIR}/hooks.jsonl`;
export const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT ?? "";

export const SOURCE_EXTS = new Set([
  "go", "ts", "tsx", "js", "jsx", "rs", "py",
  "c", "cc", "cpp", "h", "hpp",
  "rb", "java", "kt", "php", "scala", "swift",
]);

export const ALLOWED_EXTS = new Set([
  "md", "txt", "rst", "json", "yaml", "yml", "toml", "ini", "cfg", "conf",
  "sh", "bash", "zsh", "fish",
  "env", "lock", "sum", "mod",
  "csv", "svg", "png", "jpg", "gif", "ico",
  "html", "css", "scss", "less",
  "xml", "xsd", "proto", "tmpl", "tpl",
  "hcl", "tf", "tfvars",
  "sql", "graphql", "gql",
  "log", "out", "pid", "sock",
  "patch", "diff",
]);

export const ALLOWED_FILENAME_PREFIXES = [
  "README", "LICENSE", "CHANGELOG", "CONTRIBUTING",
  "Makefile", "Dockerfile", "docker-compose",
  "Taskfile", "Justfile", "Vagrantfile", "Brewfile",
  "Gemfile", "Procfile",
  ".gitignore", ".gitattributes", ".dockerignore",
  ".editorconfig", ".prettierrc", ".eslintrc", ".golangci", ".goreleaser",
  "go.mod", "go.sum",
  "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
  "Cargo.toml", "Cargo.lock",
  "pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "poetry.lock",
  "tsconfig",
  "jest.config", "vite.config", "webpack.config", "rollup.config", "babel.config",
];

export const ALLOWED_PATH_COMPONENTS = [
  "/docs/", "/doc/", "/documentation/",
  "/generated/", "/gen/",
  "/vendor/", "/node_modules/",
  "/testdata/", "/test_data/", "/fixtures/",
  "/.github/", "/.vscode/", "/.idea/",
  "/scripts/", "/hack/",
  "/deploy/", "/chart/", "/charts/", "/templates/",
];

export const SERENA_EDIT_TOOLS = new Set([
  "mcp__serena__replace_symbol_body",
  "mcp__serena__replace_content",
  "mcp__serena__insert_after_symbol",
  "mcp__serena__insert_before_symbol",
  "mcp__serena__rename_symbol",
]);

export const NATIVE_FILE_TOOLS = new Set([
  "Read", "Edit", "Write", "Grep", "Glob", "Search",
]);

export const PROJECT_MAP: Record<string, string> = {
  "orca-cloud-platform": "",
  "orca-runtime-sensor": "orca-runtime-sensor",
  "orca-sensor": "orca-sensor",
  "helm-charts": "helm-charts",
  "grafana-provisioning": "grafana-provisioning",
};

export const DENY_MSG_EXPLORE =
  "Use codebase-memory-mcp for source-code exploration: search_code, search_graph, get_code_snippet, trace_path.";
export const DENY_MSG_EDIT =
  "Use Serena for source-code edits: replace_symbol_body, replace_content, insert_after_symbol.";
export const WARN_MSG_REFS =
  "Call mcp__serena__find_referencing_symbols first to check downstream impact.";
```

- [ ] **Step 3: Create src/lib/protocol.ts**

```typescript
interface HookOutput {
  hookSpecificOutput: {
    hookEventName: string;
    permissionDecision?: "allow" | "deny";
    permissionDecisionReason?: string;
    updatedInput?: unknown;
    additionalContext?: string;
  };
  additional_context?: string;
}

export function deny(reason: string): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: reason,
    },
  };
  return JSON.stringify(out);
}

export function allow(reason: string, updatedInput?: unknown): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: reason,
      ...(updatedInput !== undefined && { updatedInput }),
    },
  };
  return JSON.stringify(out);
}

export function rewriteNoAllow(updatedInput: unknown): string {
  const out: HookOutput = {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      updatedInput,
    },
  };
  return JSON.stringify(out);
}

export function sessionContext(ctx: string): string {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ctx,
    },
  });
}
```

- [ ] **Step 4: Create src/lib/logger.ts**

```typescript
import { appendFileSync, mkdirSync } from "fs";
import { LOG_DIR, LOG_FILE } from "./constants";

let dirEnsured = false;

export function log(
  action: string,
  tool: string,
  path: string,
  reason: string,
): void {
  if (!dirEnsured) {
    try {
      mkdirSync(LOG_DIR, { recursive: true });
    } catch {}
    dirEnsured = true;
  }
  const entry = JSON.stringify({
    ts: new Date().toISOString(),
    hook: "claude-toolkit",
    action,
    tool,
    path,
    reason,
  });
  try {
    appendFileSync(LOG_FILE, entry + "\n");
  } catch {}
}
```

- [ ] **Step 5: Create src/lib/state.ts**

```typescript
import { readFileSync, writeFileSync, mkdirSync, renameSync } from "fs";
import { dirname } from "path";

export interface RefsState {
  session_id: string | null;
  traced: Record<string, number>;
}

export function readState(path: string): RefsState {
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return { session_id: null, traced: {} };
  }
}

export function writeState(path: string, state: RefsState): void {
  const dir = dirname(path);
  try {
    mkdirSync(dir, { recursive: true });
  } catch {}
  const tmp = `${path}.tmp.${process.pid}`;
  writeFileSync(tmp, JSON.stringify(state) + "\n");
  renameSync(tmp, path);
}
```

- [ ] **Step 6: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 7: Commit**

```bash
git add src/lib/
git commit -m "feat: add shared libraries — constants, protocol, logger, state, stdin"
```

---

### Task 3: PreToolUse handler — native-tool-guard

**Files:**
- Create: `src/handlers/pre-tool-use.ts`

- [ ] **Step 1: Create the handler**

```typescript
import {
  HOME, SRC_PREFIX, CLAUDE_PREFIX,
  SOURCE_EXTS, ALLOWED_EXTS, ALLOWED_FILENAME_PREFIXES, ALLOWED_PATH_COMPONENTS,
  NATIVE_FILE_TOOLS, SERENA_EDIT_TOOLS,
  DENY_MSG_EXPLORE, DENY_MSG_EDIT, WARN_MSG_REFS,
  PLUGIN_ROOT,
} from "../lib/constants";
import { deny, allow, rewriteNoAllow } from "../lib/protocol";
import { log } from "../lib/logger";
import { readState } from "../lib/state";

interface ToolInput {
  tool_name: string;
  tool_input: Record<string, unknown>;
  session_id?: string;
}

export function handlePreToolUse(input: ToolInput): {
  stdout?: string;
  exitCode: number;
} {
  const { tool_name } = input;

  // Route to correct sub-handler
  if (tool_name === "Bash") {
    return handleRtk(input);
  }
  if (SERENA_EDIT_TOOLS.has(tool_name)) {
    return handleSerenaGuard(input);
  }
  if (NATIVE_FILE_TOOLS.has(tool_name)) {
    return handleNativeGuard(input);
  }

  // Unknown tool — allow
  return { exitCode: 0 };
}

function handleNativeGuard(input: ToolInput): {
  stdout?: string;
  exitCode: number;
} {
  const { tool_name, tool_input } = input;
  const filePath =
    (tool_input.file_path as string) ??
    (tool_input.pattern as string) ??
    (tool_input.path as string) ??
    "";

  // No path → fail open
  if (!filePath) {
    log("skip", tool_name, "(no path)", "no_file_path");
    return { exitCode: 0 };
  }

  // Resolve to absolute
  let absPath: string;
  if (filePath.startsWith("/")) {
    absPath = filePath;
  } else if (filePath.startsWith("~/")) {
    absPath = HOME + filePath.slice(1);
  } else {
    absPath = process.cwd() + "/" + filePath;
  }

  // Allow ~/.claude/
  if (absPath.startsWith(CLAUDE_PREFIX)) {
    log("allow", tool_name, filePath, "dotclaude_path");
    return { exitCode: 0 };
  }

  // Allow outside ~/src/
  if (!absPath.startsWith(SRC_PREFIX)) {
    log("allow", tool_name, filePath, "outside_src");
    return { exitCode: 0 };
  }

  // Inside ~/src/ — extract extension
  const basename = absPath.slice(absPath.lastIndexOf("/") + 1);
  const dotIdx = basename.lastIndexOf(".");
  const ext = dotIdx > 0 ? basename.slice(dotIdx + 1) : "";

  // Allowed extensions
  if (ext && ALLOWED_EXTS.has(ext)) {
    log("allow", tool_name, filePath, "allowed_ext");
    return { exitCode: 0 };
  }

  // Allowed filename prefixes
  for (const prefix of ALLOWED_FILENAME_PREFIXES) {
    if (basename.startsWith(prefix) || basename === prefix) {
      log("allow", tool_name, filePath, "allowed_filename");
      return { exitCode: 0 };
    }
  }

  // Allowed path components
  for (const component of ALLOWED_PATH_COMPONENTS) {
    if (absPath.includes(component)) {
      log("allow", tool_name, filePath, "allowed_path_component");
      return { exitCode: 0 };
    }
  }

  // Source-code extensions → DENY
  if (ext && SOURCE_EXTS.has(ext)) {
    if (
      tool_name === "Read" ||
      tool_name === "Grep" ||
      tool_name === "Glob" ||
      tool_name === "Search"
    ) {
      log("deny", tool_name, filePath, "source_code_exploration");
      return { stdout: deny(DENY_MSG_EXPLORE), exitCode: 0 };
    }
    if (tool_name === "Edit" || tool_name === "Write") {
      log("deny", tool_name, filePath, "source_code_edit");
      return { stdout: deny(DENY_MSG_EDIT), exitCode: 0 };
    }
  }

  // Grep/Glob with source type or glob filter
  if (tool_name === "Grep" || tool_name === "Search") {
    const grepType = (tool_input.type as string) ?? "";
    const grepGlob = (tool_input.glob as string) ?? "";
    if (isSourceTypeOrGlob(grepType, grepGlob)) {
      log("deny", tool_name, filePath, "grep_source_type");
      return { stdout: deny(DENY_MSG_EXPLORE), exitCode: 0 };
    }
  }
  if (tool_name === "Glob") {
    const pattern = (tool_input.pattern as string) ?? "";
    if (isSourceGlobPattern(pattern)) {
      log("deny", tool_name, filePath, "glob_source_pattern");
      return { stdout: deny(DENY_MSG_EXPLORE), exitCode: 0 };
    }
  }

  // Unknown extension — fail open
  log("skip", tool_name, filePath, "unrecognized_extension");
  return { exitCode: 0 };
}

function isSourceTypeOrGlob(type: string, glob: string): boolean {
  const srcTypes = new Set([
    "go", "ts", "tsx", "js", "jsx", "rust", "py", "python",
    "c", "cpp", "h", "rb", "ruby", "java", "kt", "kotlin",
    "php", "scala", "swift",
  ]);
  if (type && srcTypes.has(type)) return true;
  if (glob) {
    const dotIdx = glob.lastIndexOf(".");
    if (dotIdx >= 0) {
      const ext = glob.slice(dotIdx + 1);
      if (SOURCE_EXTS.has(ext)) return true;
    }
  }
  return false;
}

function isSourceGlobPattern(pattern: string): boolean {
  const dotIdx = pattern.lastIndexOf(".");
  if (dotIdx >= 0) {
    const ext = pattern.slice(dotIdx + 1);
    // Remove trailing glob chars like }
    const cleanExt = ext.replace(/[{}*?,]/g, "");
    if (SOURCE_EXTS.has(cleanExt)) return true;
  }
  return false;
}

function handleSerenaGuard(input: ToolInput): {
  stdout?: string;
  exitCode: number;
} {
  const relativePath = (input.tool_input.relative_path as string) ?? "";
  if (!relativePath) return { exitCode: 0 };

  const sessionId = input.session_id ?? "";
  const stateFile = `${PLUGIN_ROOT}/state/refs-traced.json`;
  const state = readState(stateFile);

  if (state.session_id === sessionId && state.traced[relativePath] != null) {
    return { exitCode: 0 };
  }

  // Warn — not block
  process.stderr.write(
    `[serena-edit-guard] Editing '${relativePath}' without tracing references.\n${WARN_MSG_REFS}\n`,
  );
  return { exitCode: 1 };
}

function handleRtk(input: ToolInput): { stdout?: string; exitCode: number } {
  const cmd = (input.tool_input.command as string) ?? "";
  if (!cmd) return { exitCode: 0 };

  if (shouldSkipRtk(cmd)) {
    log("skip", "Bash", cmd.slice(0, 80), "rtk_skip");
    return { exitCode: 0 };
  }

  try {
    const result = Bun.spawnSync(["rtk", "rewrite", cmd], {
      stdout: "pipe",
      stderr: "pipe",
    });
    const rewritten = result.stdout.toString().trim();
    const exitCode = result.exitCode;

    switch (exitCode) {
      case 0: {
        if (rewritten === cmd || !rewritten) return { exitCode: 0 };
        log("rewrite", "Bash", cmd.slice(0, 80), "rtk_rewrite");
        const updatedInput = { ...input.tool_input, command: rewritten };
        return { stdout: allow("RTK auto-rewrite", updatedInput), exitCode: 0 };
      }
      case 1: // No RTK equivalent
        return { exitCode: 0 };
      case 2: // Deny rule — pass through
        return { exitCode: 0 };
      case 3: {
        if (!rewritten) return { exitCode: 0 };
        log("rewrite_ask", "Bash", cmd.slice(0, 80), "rtk_ask");
        const updatedInput = { ...input.tool_input, command: rewritten };
        return { stdout: rewriteNoAllow(updatedInput), exitCode: 0 };
      }
      default:
        return { exitCode: 0 };
    }
  } catch {
    // rtk not available — pass through
    return { exitCode: 0 };
  }
}

function shouldSkipRtk(cmd: string): boolean {
  if (process.env.CLAUDE_RAW === "1") return true;
  if (cmd.includes("<<")) return true;
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd.charCodeAt(i);
    // | & ; > < $ ( ) `
    if (
      c === 124 || c === 38 || c === 59 ||
      c === 62 || c === 60 || c === 36 ||
      c === 40 || c === 41 || c === 96
    ) {
      return true;
    }
  }
  return false;
}
```

- [ ] **Step 2: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add src/handlers/pre-tool-use.ts
git commit -m "feat: add PreToolUse handler — native-tool-guard, serena-edit-guard, rtk-rewrite"
```

---

### Task 4: SessionStart handler

**Files:**
- Create: `src/handlers/session-start.ts`

- [ ] **Step 1: Create the handler**

```typescript
import { PROJECT_MAP, SRC_PREFIX } from "../lib/constants";
import { sessionContext } from "../lib/protocol";

interface SessionInput {
  cwd?: string;
  gitBranch?: string;
}

export function handleSessionStart(input: SessionInput): {
  stdout?: string;
  exitCode: number;
} {
  const cwd = input.cwd ?? process.cwd();
  const branch = input.gitBranch ?? "";

  const project = detectProject(cwd);
  const parts: string[] = [];

  // 1. Project activation
  if (project) {
    parts.push(
      `SERENA WORKSPACE DETECTED: project='${project}' at ${cwd}\n` +
      `IMMEDIATELY call: mcp__serena__activate_project(project=${project})\n` +
      `Then: mcp__serena__list_memories() and read relevant memories.`,
    );
  }

  // 2. Routing table (always injected)
  parts.push(
    `TOOL ROUTING (hooks enforce — violations are hard-blocked):\n` +
    `• Source-code exploration → codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path\n` +
    `• Source-code reads → Serena: find_symbol(include_body=True), read_file\n` +
    `• Source-code edits → Serena: replace_symbol_body, replace_content, insert_after_symbol\n` +
    `• Docs/config/logs/diffs → native Read/Edit/Write\n` +
    `• Build/test/git → Bash (RTK auto-rewrites simple commands)\n` +
    `• External docs/web → mcp__docs__search_docs, mcp__exa__web_search_exa`,
  );

  const ctx = parts.join("\n\n");
  return { stdout: sessionContext(ctx), exitCode: 0 };
}

function detectProject(cwd: string): string {
  // Check specific repo dirs first
  for (const [dir, project] of Object.entries(PROJECT_MAP)) {
    if (cwd.includes(`/${dir}`)) return project;
  }

  // Fallback patterns
  if (cwd.includes("/src/orca")) return "orca";
  if (cwd === SRC_PREFIX.slice(0, -1) || cwd + "/" === SRC_PREFIX) {
    return "orca-unified";
  }

  return "";
}
```

- [ ] **Step 2: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add src/handlers/session-start.ts
git commit -m "feat: add SessionStart handler — project detection + minimal routing context"
```

---

### Task 5: UserPromptSubmit handler

**Files:**
- Create: `src/handlers/prompt-submit.ts`

- [ ] **Step 1: Create the handler**

```typescript
import { readFileSync } from "fs";
import { PLUGIN_ROOT } from "../lib/constants";

interface PromptInput {
  prompt?: string;
  user_prompt?: string;
}

interface SkillRule {
  priority?: string;
  description?: string;
  promptTriggers?: {
    keywords?: string[];
    intentPatterns?: string[];
  };
}

interface SkillRules {
  skills: Record<string, SkillRule>;
}

export function handlePromptSubmit(input: PromptInput): {
  stdout?: string;
  exitCode: number;
} {
  const prompt = ((input.prompt ?? input.user_prompt) ?? "").toLowerCase();
  if (!prompt) return { exitCode: 0 };

  let rules: SkillRules;
  try {
    const rulesPath = `${PLUGIN_ROOT}/skills/skill-rules.json`;
    rules = JSON.parse(readFileSync(rulesPath, "utf-8"));
  } catch {
    return { exitCode: 0 };
  }

  const matches: { priority: string; name: string; action?: string }[] = [];

  for (const [name, rule] of Object.entries(rules.skills)) {
    const triggers = rule.promptTriggers;
    if (!triggers) continue;

    let matched = false;

    // Keyword match
    if (triggers.keywords) {
      for (const kw of triggers.keywords) {
        if (prompt.includes(kw.toLowerCase())) {
          matched = true;
          break;
        }
      }
    }

    // Intent pattern match
    if (!matched && triggers.intentPatterns) {
      for (const pattern of triggers.intentPatterns) {
        try {
          if (new RegExp(pattern, "i").test(prompt)) {
            matched = true;
            break;
          }
        } catch {}
      }
    }

    if (matched) {
      matches.push({
        priority: rule.priority ?? "medium",
        name,
        action: rule.description,
      });
    }
  }

  if (matches.length === 0) return { exitCode: 0 };

  // Build output grouped by priority
  const priorityOrder = ["critical", "high", "medium", "low"];
  const lines: string[] = ["SKILL ACTIVATION CHECK"];

  for (const level of priorityOrder) {
    const group = matches.filter((m) => m.priority === level);
    if (group.length === 0) continue;
    const label =
      level === "critical" ? "REQUIRED" :
      level === "high" ? "RECOMMENDED" :
      level === "medium" ? "SUGGESTED" : "OPTIONAL";
    const names = group.map((m) => m.name).join(", ");
    lines.push(`${label}: ${names}`);
  }

  lines.push("ACTION: Use Skill tool or appropriate MCP tools BEFORE responding");

  return { stdout: lines.join("\n"), exitCode: 0 };
}
```

- [ ] **Step 2: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add src/handlers/prompt-submit.ts
git commit -m "feat: add UserPromptSubmit handler — keyword/intent skill activation"
```

---

### Task 6: PostToolUse handler

**Files:**
- Create: `src/handlers/post-tool-use.ts`

- [ ] **Step 1: Create the handler**

```typescript
import { PLUGIN_ROOT } from "../lib/constants";
import { readState, writeState } from "../lib/state";

interface PostToolInput {
  tool_name: string;
  tool_input: Record<string, unknown>;
  tool_response?: { is_error?: boolean };
  session_id?: string;
}

export function handlePostToolUse(input: PostToolInput): {
  stdout?: string;
  exitCode: number;
} {
  if (input.tool_name !== "mcp__serena__find_referencing_symbols") {
    return { exitCode: 0 };
  }

  if (input.tool_response?.is_error) {
    return { exitCode: 0 };
  }

  const relativePath = (input.tool_input.relative_path as string) ?? "";
  if (!relativePath) return { exitCode: 0 };

  const sessionId = input.session_id ?? "unknown";
  const stateFile = `${PLUGIN_ROOT}/state/refs-traced.json`;
  const state = readState(stateFile);

  // Reset if session changed
  if (state.session_id !== sessionId) {
    state.session_id = sessionId;
    state.traced = {};
  }

  state.traced[relativePath] = Math.floor(Date.now() / 1000);
  writeState(stateFile, state);

  return { exitCode: 0 };
}
```

- [ ] **Step 2: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add src/handlers/post-tool-use.ts
git commit -m "feat: add PostToolUse handler — refs-traced state tracking"
```

---

### Task 7: Stop/SubagentStop handler

**Files:**
- Create: `src/handlers/stop.ts`

- [ ] **Step 1: Create the handler**

This ports the existing `stop.js` / `subagent-stop.js` / `transcript-parser.js` logic into one TypeScript module.

```typescript
import { createReadStream, existsSync, appendFileSync, writeFileSync, mkdirSync } from "fs";
import { createInterface } from "readline";
import { join } from "path";

interface StopInput {
  transcript_path?: string;
  agent_transcript_path?: string;
  agent_id?: string;
  cwd?: string;
  gitBranch?: string;
}

interface Stats {
  tokens: {
    input: number;
    output: number;
    cache_read: number;
    cache_creation: number;
    total: number;
  };
  tools: Record<string, number>;
  messages: { user: number; assistant: number };
  timestamps: { start: Date | null; end: Date | null };
  session_id: string | null;
  model: string | null;
  duration_seconds?: number;
  hook_event?: string;
  agent_id?: string;
  cwd?: string;
  git_branch?: string;
  analyzed_at?: string;
}

export async function handleStop(
  input: StopInput,
  isSubagent: boolean,
): Promise<{ stdout?: string; exitCode: number }> {
  const transcriptPath = isSubagent
    ? (input.agent_transcript_path ?? input.transcript_path)
    : input.transcript_path;

  if (!transcriptPath || !existsSync(transcriptPath)) {
    return { exitCode: 0 };
  }

  const stats = await parseTranscript(transcriptPath);
  stats.hook_event = isSubagent ? "SubagentStop" : "Stop";
  if (isSubagent) stats.agent_id = input.agent_id;
  stats.cwd = input.cwd;
  stats.git_branch = input.gitBranch;
  stats.analyzed_at = new Date().toISOString();

  const projectDir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
  const statsDir = join(projectDir, "logs", "stats");
  mkdirSync(statsDir, { recursive: true });

  const logName = isSubagent ? "subagent-sessions.jsonl" : "sessions.jsonl";
  const logPath = join(statsDir, logName);
  appendFileSync(logPath, JSON.stringify(stats) + "\n");

  const latestName = isSubagent
    ? "latest-subagent-session.json"
    : "latest-session.json";
  writeFileSync(join(statsDir, latestName), JSON.stringify(stats, null, 2));

  const t = stats.tokens;
  process.stderr.write(
    `\n ${isSubagent ? "Subagent " : ""}Session Statistics:\n` +
    `   Tokens: ${t.total.toLocaleString()} (${t.input.toLocaleString()} in, ${t.output.toLocaleString()} out)\n` +
    `   Cache: ${t.cache_read.toLocaleString()} read, ${t.cache_creation.toLocaleString()} created\n` +
    `   Tools: ${Object.keys(stats.tools).length} types, ${Object.values(stats.tools).reduce((a, b) => a + b, 0)} total uses\n` +
    `   Duration: ${stats.duration_seconds ?? 0}s\n` +
    `   Saved to: ${logPath}\n\n`,
  );

  return { exitCode: 0 };
}

async function parseTranscript(path: string): Promise<Stats> {
  const stats: Stats = {
    tokens: { input: 0, output: 0, cache_read: 0, cache_creation: 0, total: 0 },
    tools: {},
    messages: { user: 0, assistant: 0 },
    timestamps: { start: null, end: null },
    session_id: null,
    model: null,
  };

  const rl = createInterface({
    input: createReadStream(path),
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    try {
      const entry = JSON.parse(line);

      if (!stats.session_id && entry.sessionId) {
        stats.session_id = entry.sessionId;
      }

      if (entry.timestamp) {
        const ts = new Date(entry.timestamp);
        if (!stats.timestamps.start || ts < stats.timestamps.start) stats.timestamps.start = ts;
        if (!stats.timestamps.end || ts > stats.timestamps.end) stats.timestamps.end = ts;
      }

      if (entry.type === "user") {
        stats.messages.user++;
      } else if (entry.type === "assistant") {
        stats.messages.assistant++;
        if (entry.message?.model) stats.model = entry.message.model;
        else if (entry.model) stats.model = entry.model;

        const usage = entry.message?.usage;
        if (usage) {
          stats.tokens.input += usage.input_tokens ?? 0;
          stats.tokens.output += usage.output_tokens ?? 0;
          stats.tokens.cache_read += usage.cache_read_input_tokens ?? 0;
          stats.tokens.cache_creation += usage.cache_creation_input_tokens ?? 0;
        }

        const content = entry.message?.content;
        if (Array.isArray(content)) {
          for (const item of content) {
            if (item.type === "tool_use") {
              stats.tools[item.name] = (stats.tools[item.name] ?? 0) + 1;
            }
          }
        }
      }
    } catch {}
  }

  stats.tokens.total =
    stats.tokens.input + stats.tokens.output +
    stats.tokens.cache_read + stats.tokens.cache_creation;

  if (stats.timestamps.start && stats.timestamps.end) {
    stats.duration_seconds = Math.floor(
      (stats.timestamps.end.getTime() - stats.timestamps.start.getTime()) / 1000,
    );
  }

  return stats;
}
```

- [ ] **Step 2: Verify typecheck**

Run: `bun run typecheck`
Expected: 0 errors

- [ ] **Step 3: Commit**

```bash
git add src/handlers/stop.ts
git commit -m "feat: add Stop/SubagentStop handler — transcript stats"
```

---

### Task 8: Entry point + compile

**Files:**
- Create: `src/index.ts`

- [ ] **Step 1: Create the entry point**

```typescript
import { readStdin } from "./lib/stdin";
import { handlePreToolUse } from "./handlers/pre-tool-use";
import { handleSessionStart } from "./handlers/session-start";
import { handlePromptSubmit } from "./handlers/prompt-submit";
import { handlePostToolUse } from "./handlers/post-tool-use";
import { handleStop } from "./handlers/stop";

const event = process.argv[2];
const input = readStdin() as Record<string, unknown> | null;

if (!input) {
  process.exit(0);
}

let result: { stdout?: string; exitCode: number };

switch (event) {
  case "pre-tool-use":
    result = handlePreToolUse(input as any);
    break;
  case "session-start":
    result = handleSessionStart(input as any);
    break;
  case "prompt-submit":
    result = handlePromptSubmit(input as any);
    break;
  case "post-tool-use":
    result = handlePostToolUse(input as any);
    break;
  case "stop":
    result = await handleStop(input as any, false);
    break;
  case "subagent-stop":
    result = await handleStop(input as any, true);
    break;
  default:
    process.exit(0);
}

if (result.stdout) {
  process.stdout.write(result.stdout);
}
process.exit(result.exitCode);
```

- [ ] **Step 2: Compile the binary**

Run: `cd /Users/ilyabrykau/src/orca-env-plugin && bash build.sh`
Expected: `Built dist/claude-toolkit (N bytes)` — binary exists at `dist/claude-toolkit`

- [ ] **Step 3: Smoke test the binary**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/Users/ilyabrykau/src/orca/base_api/views.py"}}' | ./dist/claude-toolkit pre-tool-use
```
Expected: JSON output with `permissionDecision: "deny"` and message mentioning `codebase-memory-mcp`

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' | ./dist/claude-toolkit pre-tool-use
```
Expected: empty output (exit 0, allowed)

Run:
```bash
echo '{"cwd":"/Users/ilyabrykau/src","gitBranch":"main"}' | ./dist/claude-toolkit session-start
```
Expected: JSON with `additionalContext` containing routing table and `orca-unified` activation

- [ ] **Step 4: Commit**

```bash
git add src/index.ts dist/claude-toolkit
git commit -m "feat: add entry point + compile binary"
```

---

### Task 9: Update hooks.json to route to binary

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Replace hooks.json**

Write to `hooks/hooks.json`:

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

- [ ] **Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: route all hook events to compiled binary"
```

---

### Task 10: Update skills — Codanna → CBM

**Files:**
- Modify: `skills/orca-setup/SKILL.md`
- Modify: `skills/docs/SKILL.md`
- Modify: `skills/skill-rules.json`
- Create: `skills/codebase-explorer/SKILL.md`
- Delete: `skills/codanna/SKILL.md`

- [ ] **Step 1: Create skills/codebase-explorer/SKILL.md**

```markdown
---
name: codebase-explorer
description: Source-code exploration via codebase-memory-mcp. Use for ALL code search, symbol lookup, call graphs, and impact analysis in orca repos.
---

# Codebase Explorer (codebase-memory-mcp)

Native Grep/Glob/Read are HARD-BLOCKED on code files. Use CBM for all code exploration.

## Tools Reference

| Tool | When | Key Params |
|------|------|-----------|
| `search_graph` | Find symbols by name/label/pattern | `name_pattern`, `label`, `qn_pattern` |
| `search_code` | Text search across indexed repos | `pattern`, `file_pattern` |
| `get_code_snippet` | Read source by qualified name | `qualified_name` |
| `trace_path` | Call chains and data flow | `function_name`, `mode` (calls/data_flow/cross_service) |
| `get_architecture` | Project structure overview | `aspects` |
| `query_graph` | Complex Cypher graph patterns | `query` |
| `index_repository` | Index a new repo | `path` |
| `index_status` | Check indexing status | |

## Common Patterns

### "How does authentication work?"
```
mcp__codebase-memory-mcp__search_code(pattern="auth", file_pattern="*.py")
mcp__codebase-memory-mcp__search_graph(name_pattern="auth")
```

### "Where is class SensorBase?"
```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase", label="class")
```

### "Who calls process_event?"
```
mcp__codebase-memory-mcp__trace_path(function_name="process_event", mode="calls")
```

### "What's the impact of changing SensorBase?"
```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase")
mcp__codebase-memory-mcp__trace_path(function_name="SensorBase", mode="calls")
```

### "Search project docs"
```
mcp__codebase-memory-mcp__search_code(pattern="deployment", file_pattern="*.md")
```
```

- [ ] **Step 2: Update skills/orca-setup/SKILL.md**

Replace all Codanna references with CBM equivalents. The full content should be:

```markdown
---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, CBM/Serena patterns, memory protocol.
---

# Orca Workspace Setup

## TOOL ENFORCEMENT ACTIVE

Native `Read`, `Edit`, `Write`, `Grep`, `Glob` are **HARD-BLOCKED** on code files.
A PreToolUse hook returns deny if you attempt to use them. Use MCP tools instead.

Non-code files (.json, .yaml, .md, .toml, .cfg, .sh, Makefile, Dockerfile) → native tools allowed.

---

## Step 1: Activate Project

Execute immediately:

```
mcp__serena__activate_project(project=<detected-project>)
```

Then load memories:

```
mcp__serena__list_memories()
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Step 2: Tool Routing

### Search Code (codebase-memory-mcp)

```
mcp__codebase-memory-mcp__search_graph(name_pattern="SensorBase", label="class")
mcp__codebase-memory-mcp__search_code(pattern="kafka offset commit", file_pattern="*.py")
mcp__codebase-memory-mcp__get_code_snippet(qualified_name="orca.sensors.base.AbstractSensor")
mcp__codebase-memory-mcp__trace_path(function_name="process_event", mode="calls")
mcp__codebase-memory-mcp__get_architecture(aspects=["overview"])
```

### Read Code (Serena)

```
mcp__serena__find_symbol(name_path_pattern="AbstractSensor", include_body=True, relative_path="orca/sensors/")
mcp__serena__read_file(relative_path="orca/sensors/base.py", start_line=10, end_line=50)
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codebase-memory-mcp__search_graph(name_pattern="...")`
2. **Locate**: `mcp__codebase-memory-mcp__get_code_snippet(qualified_name="...")`
3. **Trace**: `mcp__serena__find_referencing_symbols(name_path="TargetFunc", relative_path="orca/module/file.py")` — **FILE path, not directory. MANDATORY before any edit.**
4. **Edit**: Serena tools (replace_symbol_body, replace_content, insert_after_symbol)
5. **Verify**: `pytest` / `go test`

### External Docs / Web

```
mcp__docs__search_docs(library="fastapi", query="dependency injection", limit=5)
mcp__exa__web_search_exa(query="Go 1.25 breaking changes")
```

---

## Step 3: Memory Protocol

At session start: `mcp__serena__list_memories()` → read relevant ones.

```
mcp__serena__write_memory(memory_file_name="kafka_migration", content="...")
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Projects

| Project | Path | Language |
|---------|------|----------|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

---

## Params Cheat Sheet

| Tool | Param | Correct | WRONG |
|------|-------|---------|-------|
| `search_graph` (CBM) | symbol name | `name_pattern` | `name`, `query` |
| `get_code_snippet` (CBM) | symbol | `qualified_name` | `name`, `symbol_id` |
| `trace_path` (CBM) | function | `function_name` + `mode` | `symbol_name` |
| `find_referencing_symbols` | symbol | `name_path` + `relative_path` (FILE) | `symbol_name`, dir path |
| `replace_content` | params | `needle`, `repl`, `mode` | `pattern`, `replacement` |
| `replace_content` | mode values | `"literal"` or `"regex"` | `True`, `false` |
| `replace_content` | backrefs | `$!1`, `$!2` | `\1`, `\2` |
| All memory tools | key | `memory_file_name` | `memory_name`, `name` |
| `find_symbol` (Serena) | symbol | `name_path_pattern` | `name`, `symbol_name` |
| `read_file` | lines | 0-based, `end_line` inclusive | 1-based |
```

- [ ] **Step 3: Update skills/docs/SKILL.md — remove Codanna refs**

```markdown
---
name: docs
description: Library documentation lookup via Docs MCP server. Use for external library/framework docs. NOT for code search — use codebase-memory-mcp for that.
---

# Docs MCP — Library Documentation

Use for external library documentation. NOT for searching project code (use codebase-memory-mcp for that).

## Search Indexed Docs

```
mcp__docs__search_docs(library="fastapi", query="dependency injection middleware", limit=5)
```

## Fetch Any URL

```
mcp__docs__fetch_url(url="https://docs.example.com/api/reference")
```

## Index New Library Docs

```
mcp__docs__scrape_docs(library="confluent-kafka", url="https://docs.confluent.io/...", version="2.3")
```

## Check What's Indexed

```
mcp__docs__list_libraries()
```

## When To Use

| Need | Tool |
|------|------|
| External library API | `mcp__docs__search_docs` or `mcp__docs__fetch_url` |
| Internal project code | `mcp__codebase-memory-mcp__search_code` — NOT Docs MCP |
```

- [ ] **Step 4: Update skills/skill-rules.json**

```json
{
  "version": "2.0",
  "description": "Skill activation triggers for Claude Code. Controls when skills suggest or block.",
  "skills": {
    "codebase-explorer": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "critical",
      "description": "Source-code exploration via codebase-memory-mcp",
      "promptTriggers": {
        "keywords": [
          "investigate", "explore", "understand code", "codebase",
          "search graph", "trace path", "call chain", "callers",
          "who calls", "what calls", "impact analysis", "architecture",
          "find function", "find class", "find symbol", "code snippet",
          "data flow", "dependencies", "implementation",
          "search code", "index repository"
        ],
        "intentPatterns": [
          "(how|where|what|who) does .* (work|call|depend|use)",
          "(find|locate|search|trace|show) .* (function|class|method|symbol|callers|calls)",
          "(explore|understand|investigate) .* (code|module|package|service)"
        ]
      }
    },
    "serena-editor": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "critical",
      "description": "Source-code editing via Serena symbolic tools",
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
      "type": "domain",
      "enforcement": "suggest",
      "priority": "high",
      "description": "Web search via Exa for external/time-sensitive information",
      "promptTriggers": {
        "keywords": [
          "search web", "find online", "latest version", "release notes",
          "changelog", "breaking changes", "migration guide",
          "CVE", "vulnerability", "security advisory", "deprecation"
        ]
      }
    },
    "docs-lookup": {
      "type": "domain",
      "enforcement": "suggest",
      "priority": "medium",
      "description": "External library documentation via Docs MCP",
      "promptTriggers": {
        "keywords": [
          "docs", "documentation", "api reference", "library",
          "how to use", "example of", "fastapi", "pydantic",
          "pytest", "kafka", "boto3"
        ]
      }
    }
  }
}
```

- [ ] **Step 5: Delete skills/codanna/SKILL.md**

Run: `git rm skills/codanna/SKILL.md`

- [ ] **Step 6: Commit**

```bash
git add skills/
git commit -m "feat: update skills — Codanna → CBM, add codebase-explorer, enrich skill-rules"
```

---

### Task 11: Add tool-restricted agents

**Files:**
- Create: `agents/cbm-explorer.md`
- Create: `agents/serena-editor.md`

- [ ] **Step 1: Create agents/cbm-explorer.md**

```markdown
---
name: cbm-explorer
description: "MUST BE USED for source-code exploration in orca repos: symbol lookup, call chains, data flow, implementation discovery, architecture and impact analysis. Uses codebase-memory-mcp and docs tools only."
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
---

Source-code exploration agent. Uses codebase-memory-mcp graph for symbol search, call tracing, and impact analysis.

## Available tools

- `search_graph` — find symbols by name, label, or qualified name pattern
- `search_code` — text search across indexed repositories
- `get_code_snippet` — read source code by qualified name
- `trace_path` — trace call chains and data flow
- `get_architecture` — project structure overview
- `query_graph` — complex Cypher queries on the code graph
- `index_repository` / `index_status` — manage repository indexing
- `search_docs` / `fetch_url` — external library documentation
- `web_search_exa` / `web_fetch_exa` — web search
```

- [ ] **Step 2: Create agents/serena-editor.md**

```markdown
---
name: serena-editor
description: "MUST BE USED for source-code edits in orca repos. Serena symbolic tools only. Always call find_referencing_symbols before editing."
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
---

Source-code editing agent. Uses Serena symbolic tools for safe, reference-aware edits.

## Workflow

1. `find_referencing_symbols` — trace downstream impact (MANDATORY before edits)
2. `replace_symbol_body` — replace entire function/class/method
3. `replace_content` — targeted literal or regex edit
4. `insert_after_symbol` / `insert_before_symbol` — add new code
5. `rename_symbol` — rename across codebase

## Key rules

- `relative_path` in `find_referencing_symbols` must be a FILE, not a directory
- `replace_content` backreferences: `$!1`, `$!2` (NOT `\1`, `\2`)
- `mode` values: exactly `"literal"` or `"regex"`
- `replace_symbol_body` body = implementation only, no docstrings
- `read_file` lines are 0-based, `end_line` is inclusive
```

- [ ] **Step 3: Commit**

```bash
git add agents/
git commit -m "feat: add tool-restricted agents — cbm-explorer and serena-editor"
```

---

### Task 12: Clean up old shell hooks

**Files:**
- Delete: `hooks/pre-tool-router`
- Delete: `hooks/session-start`
- Delete: `hooks/skill-activation-prompt`
- Delete: `hooks/post-serena-refs`
- Delete: `hooks/stop.js`
- Delete: `hooks/subagent-stop.js`
- Delete: `hooks/utils/transcript-parser.js`
- Delete: `hooks/package.json`

- [ ] **Step 1: Remove old hook files**

Run:
```bash
cd /Users/ilyabrykau/src/orca-env-plugin
git rm hooks/pre-tool-router hooks/session-start hooks/skill-activation-prompt hooks/post-serena-refs hooks/stop.js hooks/subagent-stop.js hooks/utils/transcript-parser.js hooks/package.json
rmdir hooks/utils 2>/dev/null || true
```

- [ ] **Step 2: Commit**

```bash
git commit -m "chore: remove old shell/JS hooks — replaced by compiled binary"
```

---

### Task 13: Clean up ~/.claude/hooks/disabled/

**Files:**
- Archive and clean `~/.claude/hooks/disabled/`

- [ ] **Step 1: Archive disabled hooks**

Run:
```bash
cd ~/.claude/hooks
tar czf ~/disabled-hooks-backup-$(date +%Y%m%d).tar.gz disabled/
rm -rf disabled/
mkdir disabled  # keep dir to avoid errors
```

- [ ] **Step 2: Clean remaining files in ~/.claude/hooks/**

The `package.json` and `utils/` are leftovers. Archive them too:
```bash
cd ~/.claude/hooks
mv package.json disabled/ 2>/dev/null || true
mv utils/ disabled/ 2>/dev/null || true
```

No git commit — this is outside any repo.

---

### Task 14: Update tests

**Files:**
- Modify: `tests/helpers.sh`
- Modify: `tests/unit/test-pre-tool-use.sh`
- Modify: `tests/unit/test-hooks-smoke.sh`
- Modify: `tests/unit/test-session-output.sh`
- Modify: `tests/unit/test-project-detection.sh`
- Modify: `tests/unit/test-serena-guard.sh`

- [ ] **Step 1: Update tests/helpers.sh**

Add binary path constant. In the existing file, after `PLUGIN_ROOT=...` add:

```bash
BINARY="${PLUGIN_ROOT}/dist/claude-toolkit"
```

Update `run_enforcement` / `run_hook_from` functions to use binary when available:

```bash
run_binary() {
    local event="$1"
    local json="$2"
    echo "$json" | "$BINARY" "$event"
}
```

Export the new function:
```bash
export -f run_binary
export BINARY
```

- [ ] **Step 2: Update tests/unit/test-pre-tool-use.sh**

Replace `HOOK="${PLUGIN_ROOT}/hooks/pre-tool-router"` with `HOOK="${PLUGIN_ROOT}/dist/claude-toolkit"`.

Replace all `echo "$json" | bash "$HOOK"` with `echo "$json" | "$HOOK" pre-tool-use`.

Update expected error messages from `mcp__codanna__` to `codebase-memory-mcp`.

Fix the test cases that currently expect Grep/Glob blocked unconditionally — the new guard checks paths, so:
- `Grep` with no `file_path` → now ALLOWED (fail open), not blocked
- `Glob` with `**/*.md` → now ALLOWED (not source ext), not blocked
- `Read .sh` → now ALLOWED (shell scripts are in ALLOWED_EXTS), not blocked

Update these test expectations accordingly:

```bash
# These should now ALLOW (behavior change from v1):
test_allow '{"tool_name":"Grep","tool_input":{"pattern":"TODO"}}' \
    "Grep no path → fail open (allowed)"
test_allow '{"tool_name":"Glob","tool_input":{"pattern":"**/*.md"}}' \
    "Glob *.md → allowed (not source ext)"
test_allow '{"tool_name":"Read","tool_input":{"file_path":"deploy.sh"}}' \
    "Read .sh → allowed (shell script)"

# Grep with source type filter should still block:
test_block '{"tool_name":"Grep","tool_input":{"path":"/Users/ilyabrykau/src/orca","type":"go"}}' \
    "Grep type=go under ~/src blocked" "codebase-memory-mcp"
```

- [ ] **Step 3: Update tests/unit/test-hooks-smoke.sh**

Replace hook paths to use binary. Update expected messages from `mcp__codanna__` to `codebase-memory-mcp`. Update session-start expectations to match minimal injection (no `HARD-BLOCKED`, no `Params Cheat Sheet` — those are in lazy-loaded skills now). Replace `mcp__codanna__` checks with routing table content.

- [ ] **Step 4: Update tests/unit/test-session-output.sh**

Remove assertion for `mcp__codanna__` content. Add assertions for routing table keywords:
```bash
if assert_contains "$output" "codebase-memory-mcp" "contains CBM routing"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
if assert_contains "$output" "TOOL ROUTING" "contains routing table"; then
    passed=$((passed+1)); else failed=$((failed+1))
fi
```

- [ ] **Step 5: Update tests/unit/test-project-detection.sh**

Replace `HOOK="${PLUGIN_ROOT}/hooks/session-start"` with binary. Update `run_test` to use:
```bash
output=$(cd "$dir" 2>/dev/null && echo '{"cwd":"'"$dir"'"}' | "$BINARY" session-start 2>/dev/null || echo '{"error":"hook_failed"}')
```

- [ ] **Step 6: Update tests/unit/test-serena-guard.sh**

Point `HOOK_EDIT` at `"$BINARY" pre-tool-use` and `HOOK_REFS` at `"$BINARY" post-tool-use`. The serena guard is now inside the pre-tool-use handler, so the same binary handles both.

- [ ] **Step 7: Run all unit tests**

Run: `cd /Users/ilyabrykau/src/orca-env-plugin && bash tests/run-all.sh`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add tests/
git commit -m "test: update unit tests for v2 binary hooks"
```

---

### Task 15: Update CLAUDE.md

**Files:**
- Modify: `/Users/ilyabrykau/.claude/CLAUDE.md`

- [ ] **Step 1: Replace CLAUDE.md content**

```markdown
Claude Code
 Workspace
 - macOS zsh Homebrew
 - src repos - runtime - cloud - platform - charts - plugin - provisioning
 - unified workspace path repo - prefixed - runtime - sensor pkg
 - single - repo workspace Serena paths repo - relative
 Scope discipline
 -
 - scope
 - Treat memory hints Re - check upstream PRs issues CI releases tickets
 decision tree
 - External time - sensitive truth → web/docs/exa first
 - Indexed source-code exploration → CBM (search_graph, search_code, get_code_snippet, trace_path)
 - Source-code reads → Serena (find_symbol, read_file)
 - Source-code edits → Serena (replace_symbol_body, replace_content, insert_after_symbol)
 - Docs/config/logs/diffs/debugging/raw text → native tools
 - Build/test/git/filesystem facts → Bash
 - RTK default simple Bash commands
 - Unified workspace Serena paths repo-prefixed (e.g. orca/sensors/base.py)
 - No python -c / perl / ruby / sed -i source-code edits
 - source-code exploration - CBM ( - )
 - source-code edits - Serena ( - )
 -
 - edits - Serena ( - )
 -
 -
Build test git formatters local inspection shell facts - Bash
 - single - command.
 - Commands pipes redirects heredocs |
 guardrails
 - ad string files.
 - Serena fails path mismatch text
 - edit
 - stable rules
 - notes
 - verify memory.
 - inspectable outputs raw path.
 - scope suppress single - clarifying - question rule.

@RTK.md
```

- [ ] **Step 2: No commit needed** — this is outside the plugin repo.

---

### Task 16: Live validation

- [ ] **Step 1: Verify one RTK hook source (A)**

Run: `cat /Users/ilyabrykau/src/orca-env-plugin/hooks/hooks.json | grep -c 'Bash'`
Expected: `1` (Bash appears once in matcher)

- [ ] **Step 2: Verify one native-tool-guard (B)**

Run: `cat /Users/ilyabrykau/src/orca-env-plugin/hooks/hooks.json | grep -c 'pre-tool-use'`
Expected: `1`

- [ ] **Step 3: Test Read ~/src/*.go denied (C)**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/Users/ilyabrykau/src/orca-sensor/cmd/main.go"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: JSON with `"permissionDecision":"deny"` and `"codebase-memory-mcp"` in reason

- [ ] **Step 4: Test Grep on source denied (D)**

Run:
```bash
echo '{"tool_name":"Grep","tool_input":{"path":"/Users/ilyabrykau/src/orca","type":"go","pattern":"func main"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: JSON with `"permissionDecision":"deny"`

- [ ] **Step 5: Test Edit on source denied (E)**

Run:
```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"/Users/ilyabrykau/src/orca/base_api/views.py"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: JSON with `"permissionDecision":"deny"` mentioning Serena

- [ ] **Step 6: Test Read README.md allowed (F)**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/Users/ilyabrykau/src/orca/README.md"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: empty output (exit 0)

- [ ] **Step 7: Test Read ~/.claude/settings.json allowed (G)**

Run:
```bash
echo '{"tool_name":"Read","tool_input":{"file_path":"/Users/ilyabrykau/.claude/settings.json"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: empty output (exit 0)

- [ ] **Step 8: Test simple Bash → RTK (H)**

Run:
```bash
echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: either rewritten command JSON (if rtk has a rewrite for git status) or empty output (if no rewrite). Check `~/.claude/logs/hooks.jsonl` for log entry.

- [ ] **Step 9: Test CLAUDE_RAW=1 bypass (I)**

Run:
```bash
CLAUDE_RAW=1 echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | /Users/ilyabrykau/src/orca-env-plugin/dist/claude-toolkit pre-tool-use
```
Expected: empty output (passthrough, no RTK). Check `~/.claude/logs/hooks.jsonl` for `rtk_skip` entry.

- [ ] **Step 10: Verify explorer agent tools (J)**

Run: `grep -c 'Bash\|Read\|Grep\|Glob\|Search\|Edit\|Write' /Users/ilyabrykau/src/orca-env-plugin/agents/cbm-explorer.md`
Expected: `0` (none of these tools listed)

- [ ] **Step 11: Verify editor agent tools (K)**

Run: `grep -c 'Bash\|Read\b\|Grep\|Glob\|Search\b\|Edit\|Write' /Users/ilyabrykau/src/orca-env-plugin/agents/serena-editor.md`
Expected: `0`

- [ ] **Step 12: Verify CBM in deny messages (M)**

Run: `grep 'codebase-memory-mcp' /Users/ilyabrykau/src/orca-env-plugin/src/lib/constants.ts`
Expected: matches in DENY_MSG_EXPLORE

Run: `grep -r 'codanna' /Users/ilyabrykau/src/orca-env-plugin/src/ /Users/ilyabrykau/src/orca-env-plugin/skills/ /Users/ilyabrykau/src/orca-env-plugin/agents/`
Expected: no matches

- [ ] **Step 13: Verify no stale cache (O)**

Run: `ls /Users/ilyabrykau/.claude/plugins/cache/orca-sensor-marketplace/ 2>/dev/null`
Expected: empty or not found (plugin loads from source dir)

- [ ] **Step 14: Run full test suite**

Run: `cd /Users/ilyabrykau/src/orca-env-plugin && bash tests/run-all.sh`
Expected: all pass

---

### Task 17: Optional — LLMLingua prompt compression (Phase 11)

**Files:**
- Create: `scripts/compress-prompts.py`

This task is conditional — only execute if skill files exceed ~500 tokens each after Tasks 1-16 are complete.

- [ ] **Step 1: Measure skill token counts**

Run:
```bash
for f in skills/*/SKILL.md; do echo "$f: $(wc -w < "$f") words"; done
```

If any skill is under ~400 words (~500 tokens), skip this task entirely.

- [ ] **Step 2: Create scripts/compress-prompts.py**

```python
#!/usr/bin/env python3
"""Optional build-time prompt compression using LLMLingua-2."""

import sys
from pathlib import Path

try:
    from llmlingua import PromptCompressor
except ImportError:
    print("LLMLingua not installed. Skipping compression.", file=sys.stderr)
    sys.exit(0)

SKILLS_DIR = Path(__file__).parent.parent / "skills"
FORCE_TOKENS = [
    "mcp__", "serena", "codebase-memory-mcp", "search_graph", "search_code",
    "get_code_snippet", "trace_path", "get_architecture", "query_graph",
    "replace_symbol_body", "replace_content", "insert_after_symbol",
    "find_symbol", "find_referencing_symbols", "name_path_pattern",
    "relative_path", "memory_file_name", "include_body",
]

compressor = PromptCompressor(
    model_name="microsoft/llmlingua-2-bert-base-multilingual-cased-meetingbank",
)

for skill_file in SKILLS_DIR.glob("*/SKILL.md"):
    text = skill_file.read_text()
    original_words = len(text.split())
    if original_words < 400:
        print(f"SKIP {skill_file.name}: {original_words} words (under threshold)")
        continue

    result = compressor.compress_prompt(
        [text],
        rate=0.5,
        force_tokens=FORCE_TOKENS,
    )
    compressed = result["compressed_prompt"]
    new_words = len(compressed.split())
    print(f"COMPRESS {skill_file.name}: {original_words} → {new_words} words ({new_words/original_words:.0%})")
    skill_file.write_text(compressed)
```

- [ ] **Step 3: Test compression (dry run)**

Run: `cd /Users/ilyabrykau/src/orca-env-plugin && python3 scripts/compress-prompts.py`
Expected: reports compression ratios per skill file, or skips small files

- [ ] **Step 4: If compression applied, rebuild binary and re-run tests**

Run: `bash build.sh && bash tests/run-all.sh`

- [ ] **Step 5: Commit if changes made**

```bash
git add scripts/compress-prompts.py skills/
git commit -m "feat: add optional LLMLingua prompt compression"
```
