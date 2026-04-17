import { readFileSync, writeSync, appendFileSync, mkdirSync } from "fs";
import { homedir } from "os";

// ===========================================================================
// COMPILE-TIME CONSTANTS -- resolved once at module load, zero cost at runtime
// ===========================================================================

const HOME = homedir();
const SRC_PFX = `${HOME}/src/`;
const DOT_CLAUDE_PFX = `${HOME}/.claude/`;
const LOG_DIR = `${HOME}/.claude/logs`;
const LOG_FILE = `${LOG_DIR}/hooks.jsonl`;
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT ?? "";
const STATE_FILE = `${PLUGIN_ROOT}/state/refs-traced.json`;

// Source-code extensions -- switch for JIT jump table
function isSourceExt(ext: string): boolean {
  switch (ext) {
    case "go": case "ts": case "tsx": case "js": case "jsx":
    case "rs": case "py": case "c": case "cc": case "cpp":
    case "h": case "hpp": case "rb": case "java": case "kt":
    case "php": case "scala": case "swift":
      return true;
    default:
      return false;
  }
}

// Allowed extensions -- switch for JIT jump table
function isAllowedExt(ext: string): boolean {
  switch (ext) {
    case "md": case "txt": case "rst": case "json": case "yaml":
    case "yml": case "toml": case "ini": case "cfg": case "conf":
    case "sh": case "bash": case "zsh": case "fish":
    case "env": case "lock": case "sum": case "mod":
    case "csv": case "svg": case "png": case "jpg": case "gif": case "ico":
    case "html": case "css": case "scss": case "less":
    case "xml": case "xsd": case "proto": case "tmpl": case "tpl":
    case "hcl": case "tf": case "tfvars":
    case "sql": case "graphql": case "gql":
    case "log": case "out": case "pid": case "sock":
    case "patch": case "diff":
      return true;
    default:
      return false;
  }
}

// Pre-serialized deny responses -- ZERO allocation at call time
const DENY_EXPLORE = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use codebase-memory-mcp for source-code exploration: search_code, search_graph, get_code_snippet, trace_path."}}';
const DENY_EDIT = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use Serena for source-code edits: replace_symbol_body, replace_content, insert_after_symbol."}}';

// Allowed filename prefixes
const ALLOWED_NAMES = [
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

// Allowed path components
const ALLOWED_PATHS = [
  "/docs/", "/doc/", "/documentation/",
  "/generated/", "/gen/",
  "/vendor/", "/node_modules/",
  "/testdata/", "/test_data/", "/fixtures/",
  "/.github/", "/.vscode/", "/.idea/",
  "/scripts/", "/hack/",
  "/deploy/", "/chart/", "/charts/", "/templates/",
];

// Source type names for Grep type= filter
function isSourceType(t: string): boolean {
  switch (t) {
    case "go": case "ts": case "tsx": case "js": case "jsx":
    case "rust": case "py": case "python": case "c": case "cpp":
    case "h": case "rb": case "ruby": case "java": case "kt":
    case "kotlin": case "php": case "scala": case "swift":
      return true;
    default:
      return false;
  }
}

// ===========================================================================
// FAST FIELD EXTRACTION -- no JSON.parse, indexOf on raw string
// ===========================================================================

function extractStr(raw: string, key: string): string {
  const needle = `"${key}":"`;
  const i = raw.indexOf(needle);
  if (i < 0) return "";
  const start = i + needle.length;
  let end = start;
  while (end < raw.length) {
    if (raw.charCodeAt(end) === 34 /* " */ && raw.charCodeAt(end - 1) !== 92 /* \ */) break;
    end++;
  }
  return raw.substring(start, end);
}

// Extract extension from path -- inline, no allocation except substring
function extOf(path: string): string {
  const lastSlash = path.lastIndexOf("/");
  const lastDot = path.lastIndexOf(".");
  if (lastDot <= lastSlash) return "";
  return path.substring(lastDot + 1);
}

// Extract basename
function baseOf(path: string): string {
  const i = path.lastIndexOf("/");
  return i < 0 ? path : path.substring(i + 1);
}

// Resolve to absolute
function resolve(p: string): string {
  if (p.charCodeAt(0) === 47) return p; // starts with /
  if (p.charCodeAt(0) === 126 && p.charCodeAt(1) === 47) return HOME + p.substring(1); // ~/
  return process.cwd() + "/" + p;
}

// ===========================================================================
// SYNC LOGGER -- only called on deny (cold path), never on allow
// ===========================================================================

let logDirReady = false;
function logSync(action: string, tool: string, path: string, reason: string): void {
  try {
    if (!logDirReady) { mkdirSync(LOG_DIR, { recursive: true }); logDirReady = true; }
    const ts = Date.now();
    appendFileSync(LOG_FILE, `{"ts":${ts},"h":"ct","a":"${action}","t":"${tool}","p":"${path.substring(0, 80).replace(/"/g, '')}","r":"${reason}"}\n`);
  } catch {}
}

// ===========================================================================
// SHELL CHAR CHECK -- single pass, no regex, charcode scan
// ===========================================================================

function hasShellChars(cmd: string): boolean {
  const len = cmd.length;
  for (let i = 0; i < len; i++) {
    const c = cmd.charCodeAt(i);
    // | & ; > < $ ( ) `
    if (c === 124 || c === 38 || c === 59 || c === 62 || c === 60 ||
        c === 36 || c === 40 || c === 41 || c === 96) return true;
  }
  return cmd.indexOf("<<") >= 0;
}

// ===========================================================================
// SERENA EDIT TOOLS -- check via startsWith for hot inline check
// ===========================================================================

const SERENA_EDIT_PREFIXES = [
  "mcp__serena__replace_symbol_body",
  "mcp__serena__replace_content",
  "mcp__serena__insert_after_symbol",
  "mcp__serena__insert_before_symbol",
  "mcp__serena__rename_symbol",
];

function isSerenaEditTool(name: string): boolean {
  for (let i = 0; i < SERENA_EDIT_PREFIXES.length; i++) {
    if (name === SERENA_EDIT_PREFIXES[i]) return true;
  }
  return false;
}

// ===========================================================================
// NATIVE FILE TOOLS -- switch for JIT jump table
// ===========================================================================

function isNativeFileTool(name: string): boolean {
  switch (name) {
    case "Read": case "Edit": case "Write":
    case "Grep": case "Glob": case "Search":
      return true;
    default:
      return false;
  }
}

// ===========================================================================
// MAIN HANDLER -- the hot path
// ===========================================================================

export function handlePreToolUse(raw: string): void {
  const toolName = extractStr(raw, "tool_name");
  if (!toolName) { process.exit(0); }

  // --- BASH / RTK REWRITE ---
  if (toolName === "Bash") {
    const cmd = extractStr(raw, "command");
    if (!cmd) { process.exit(0); }
    if (process.env.CLAUDE_RAW === "1" || hasShellChars(cmd)) {
      process.exit(0);
    }
    // RTK rewrite -- only non-sync part, but only for Bash commands
    try {
      const result = Bun.spawnSync(["rtk", "rewrite", cmd], {
        stdout: "pipe",
        stderr: "pipe",
      });
      const rewritten = result.stdout.toString().trim();
      const ec = result.exitCode;

      if (ec === 0 && rewritten && rewritten !== cmd) {
        // Need to parse full input to build updatedInput
        const input = JSON.parse(raw);
        const updatedInput = { ...input.tool_input, command: rewritten };
        logSync("rewrite", "Bash", cmd.substring(0, 80), "rtk");
        writeSync(1, JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: "RTK auto-rewrite",
            updatedInput,
          }
        }));
      } else if (ec === 3 && rewritten) {
        const input = JSON.parse(raw);
        const updatedInput = { ...input.tool_input, command: rewritten };
        writeSync(1, JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            updatedInput,
          }
        }));
      }
      // ec 1 or 2 or no rewrite = passthrough = exit 0
    } catch {}
    process.exit(0);
  }

  // --- SERENA EDIT GUARD ---
  if (isSerenaEditTool(toolName)) {
    const relPath = extractStr(raw, "relative_path");
    if (!relPath) { process.exit(0); }
    const sessionId = extractStr(raw, "session_id");
    try {
      const stateRaw = readFileSync(STATE_FILE, "utf-8");
      const sidNeedle = '"session_id":"';
      const sidStart = stateRaw.indexOf(sidNeedle);
      if (sidStart >= 0) {
        const sidValStart = sidStart + sidNeedle.length;
        const sidEnd = stateRaw.indexOf('"', sidValStart);
        const stateSid = stateRaw.substring(sidValStart, sidEnd);
        if (stateSid === sessionId && stateRaw.indexOf(`"${relPath}"`) >= 0) {
          process.exit(0); // refs traced, allow
        }
      }
    } catch {} // no state file = warn
    process.stderr.write(
      `[serena-edit-guard] Editing '${relPath}' without tracing references.\nCall mcp__serena__find_referencing_symbols first to check downstream impact.\n`,
    );
    process.exit(1);
  }

  // --- NATIVE FILE TOOLS ---
  if (!isNativeFileTool(toolName)) {
    process.exit(0); // unknown tool, fail open
  }

  // Priority matches original: file_path ?? pattern ?? path
  const filePath = extractStr(raw, "file_path") || extractStr(raw, "pattern") || extractStr(raw, "path");

  // No path -> fail open (FAST EXIT)
  if (!filePath) { process.exit(0); }

  const abs = resolve(filePath);

  // Allow ~/.claude/ (FAST EXIT)
  if (abs.startsWith(DOT_CLAUDE_PFX)) { process.exit(0); }

  // Allow outside ~/src/ (FAST EXIT)
  if (!abs.startsWith(SRC_PFX)) { process.exit(0); }

  // -- Inside ~/src/ -- check extension --
  const ext = extOf(abs);

  // Allowed extension -> FAST EXIT
  if (ext && isAllowedExt(ext)) { process.exit(0); }

  // Allowed filename
  const base = baseOf(abs);
  for (let i = 0; i < ALLOWED_NAMES.length; i++) {
    if (base.startsWith(ALLOWED_NAMES[i])) { process.exit(0); }
  }

  // Allowed path component
  for (let i = 0; i < ALLOWED_PATHS.length; i++) {
    if (abs.indexOf(ALLOWED_PATHS[i]) >= 0) { process.exit(0); }
  }

  // Source extension -> DENY
  if (ext && isSourceExt(ext)) {
    if (toolName === "Edit" || toolName === "Write") {
      logSync("deny", toolName, filePath, "src_edit");
      writeSync(1, DENY_EDIT);
      process.exit(0);
    }
    // Read, Grep, Glob, Search
    logSync("deny", toolName, filePath, "src_explore");
    writeSync(1, DENY_EXPLORE);
    process.exit(0);
  }

  // Grep/Glob type/glob filter check
  if (toolName === "Grep" || toolName === "Search") {
    const grepType = extractStr(raw, "type");
    if (grepType && isSourceType(grepType)) {
      logSync("deny", toolName, filePath, "grep_src_type");
      writeSync(1, DENY_EXPLORE);
      process.exit(0);
    }
    const grepGlob = extractStr(raw, "glob");
    if (grepGlob) {
      const gExt = extOf(grepGlob);
      if (gExt && isSourceExt(gExt)) {
        logSync("deny", toolName, filePath, "grep_src_glob");
        writeSync(1, DENY_EXPLORE);
        process.exit(0);
      }
    }
  }
  if (toolName === "Glob") {
    const pattern = extractStr(raw, "pattern");
    if (pattern) {
      const cleaned = pattern.replace(/[{}*?,]/g, "");
      const pExt = extOf(cleaned);
      if (pExt && isSourceExt(pExt)) {
        logSync("deny", toolName, filePath, "glob_src_pattern");
        writeSync(1, DENY_EXPLORE);
        process.exit(0);
      }
    }
  }

  // Unknown -> fail open
  process.exit(0);
}
