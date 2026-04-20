import { readFileSync, writeSync, appendFileSync, mkdirSync } from "fs";
import { homedir } from "os";

// ===========================================================================
// COMPILE-TIME CONSTANTS
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

// Resolve to absolute + normalize ../ segments (prevent path traversal bypass)
function resolve(p: string): string {
  let abs: string;
  if (p.charCodeAt(0) === 47) abs = p;
  else if (p.charCodeAt(0) === 126 && p.charCodeAt(1) === 47) abs = HOME + p.substring(1);
  else abs = process.cwd() + "/" + p;
  // Normalize ../ to prevent path traversal bypass on ALLOWED_PATHS
  if (abs.indexOf("..") >= 0) {
    const parts = abs.split("/");
    const normalized: string[] = [];
    for (const part of parts) {
      if (part === "..") { if (normalized.length > 1) normalized.pop(); }
      else if (part !== ".") normalized.push(part);
    }
    abs = normalized.join("/") || "/";
  }
  return abs;
}

// ===========================================================================
// SYNC LOGGER -- only called on deny (cold path)
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
// BASH SOURCE GUARD -- universal path scan
// Scan entire cmd for paths under ~/src/. Any source-ext path → deny.
// ===========================================================================

function isBashEditWord(w: string): boolean {
  switch (w) {
    case "sed": case "awk": case "perl": case "ruby":
    case "python": case "python3": case "node": case "bun": case "deno": case "tsx":
    case "cp": case "mv": case "rm": case "ln": case "chmod": case "chown":
    case "touch": case "dd": case "tee":
      return true;
    default:
      return false;
  }
}

function bashHasSourcePath(cmd: string): "read" | "edit" | "" {
  let firstPathStart = -1;
  let pos = 0;
  while (pos < cmd.length) {
    // Find nearest marker: absolute SRC_PFX or tilde form ~/src/
    const aIdx = cmd.indexOf(SRC_PFX, pos);
    const tIdx = cmd.indexOf("~/src/", pos);
    let start: number;
    if (aIdx < 0 && tIdx < 0) break;
    if (aIdx < 0) start = tIdx;
    else if (tIdx < 0) start = aIdx;
    else start = aIdx < tIdx ? aIdx : tIdx;

    // Extract path: stop on whitespace/quotes/parens/shell-separators/backslash
    let end = start;
    while (end < cmd.length) {
      const c = cmd.charCodeAt(end);
      if (c === 32 || c === 9 || c === 10 || c === 13 ||
          c === 34 || c === 39 || c === 96 ||
          c === 40 || c === 41 || c === 44 || c === 59 ||
          c === 124 || c === 38 || c === 60 || c === 62 ||
          c === 92) break;
      end++;
    }
    let path = cmd.substring(start, end);
    // strip trailing punctuation that's unlikely part of a path
    while (path.length > 0) {
      const last = path.charCodeAt(path.length - 1);
      if (last === 58 /* : */ || last === 46 /* . */) path = path.substring(0, path.length - 1);
      else break;
    }
    // Tilde expand
    if (path.charCodeAt(0) === 126) path = HOME + path.substring(1);
    const abs = resolve(path);
    pos = end > pos ? end : pos + 1;
    if (!abs.startsWith(SRC_PFX)) continue;
    if (abs.startsWith(DOT_CLAUDE_PFX)) continue;
    // Allowed path component
    let skip = false;
    for (let i = 0; i < ALLOWED_PATHS.length; i++) {
      if (abs.indexOf(ALLOWED_PATHS[i]) >= 0) { skip = true; break; }
    }
    if (skip) continue;
    // Allowed filename
    const base = baseOf(abs);
    for (let i = 0; i < ALLOWED_NAMES.length; i++) {
      if (base.startsWith(ALLOWED_NAMES[i])) { skip = true; break; }
    }
    if (skip) continue;
    const ext = extOf(abs);
    if (!ext) continue;
    if (isAllowedExt(ext)) continue;
    if (!isSourceExt(ext)) continue;
    // First source path found
    if (firstPathStart < 0) firstPathStart = start;
  }
  // cd-relative check: cd <src-dir> && <cmd> <relative-file.ext>
  if (firstPathStart < 0) {
    const cdMatch = cmd.match(/\bcd\s+(~\/src\/[^\s;&|]+|\/?Users\/[^\s;&|]*\/src\/[^\s;&|]+)/);
    if (cdMatch) {
      let cdDir = cdMatch[1];
      if (cdDir.charCodeAt(0) === 126) cdDir = HOME + cdDir.substring(1);
      const cdAbs = resolve(cdDir);
      if (cdAbs.startsWith(SRC_PFX)) {
        const afterCd = cmd.substring(cmd.indexOf(cdMatch[0]) + cdMatch[0].length);
        const tokens = afterCd.replace(/^[\s;&|]+/, "").split(/\s+/);
        for (let ti = 0; ti < tokens.length; ti++) {
          const tok = tokens[ti];
          if (tok.startsWith("-")) continue;
          const te = extOf(tok);
          if (te && isSourceExt(te) && !isAllowedExt(te)) {
            firstPathStart = cmd.indexOf(cdMatch[0]);
            break;
          }
        }
      }
    }
  }
  if (firstPathStart < 0) return "";

  // Read vs edit: check text before first source path
  const prefix = cmd.substring(0, firstPathStart);
  if (prefix.indexOf(">") >= 0) return "edit";
  if (/\btee\b/.test(prefix)) return "edit";
  // last segment (after &&, ||, ;, |)
  const segs = prefix.split(/&&|\|\||;|\|/);
  const lastSeg = segs[segs.length - 1];
  const parts = lastSeg.trim().split(/\s+/);
  let idx = 0;
  while (idx < parts.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(parts[idx])) idx++;
  const word = parts[idx] ? baseOf(parts[idx]) : "";
  if (isBashEditWord(word)) return "edit";
  return "read";
}

// ===========================================================================
// SERENA EDIT TOOLS
// ===========================================================================

const SERENA_EDIT_PREFIXES = [
  "mcp__serena__replace_symbol_body",
  "mcp__serena__replace_content",
  "mcp__serena__insert_after_symbol",
  "mcp__serena__insert_before_symbol",
  "mcp__serena__rename_symbol",
  "mcp__serena__safe_delete_symbol",
];

function isSerenaEditTool(name: string): boolean {
  for (let i = 0; i < SERENA_EDIT_PREFIXES.length; i++) {
    if (name === SERENA_EDIT_PREFIXES[i]) return true;
  }
  return false;
}

// ===========================================================================
// NATIVE FILE TOOLS
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
// MAIN HANDLER
// ===========================================================================

export function handlePreToolUse(raw: string): void {
  const toolName = extractStr(raw, "tool_name");
  if (!toolName) { process.exit(0); }

  // --- BASH ---
  if (toolName === "Bash") {
    const cmd = extractStr(raw, "command");
    if (!cmd) { process.exit(0); }
    if (process.env.CLAUDE_RAW === "1") { process.exit(0); }

    // Universal path scan: deny any cmd referencing source path under ~/src/
    const srcHit = bashHasSourcePath(cmd);
    if (srcHit === "read") {
      logSync("deny", "Bash", cmd.substring(0, 80), "bash_src_read");
      writeSync(1, DENY_EXPLORE);
      process.exit(0);
    }
    if (srcHit === "edit") {
      logSync("deny", "Bash", cmd.substring(0, 80), "bash_src_edit");
      writeSync(1, DENY_EDIT);
      process.exit(0);
    }

    if (hasShellChars(cmd)) { process.exit(0); }

    // RTK rewrite -- only for simple commands
    try {
      const result = Bun.spawnSync(["rtk", "rewrite", cmd], {
        stdout: "pipe",
        stderr: "pipe",
      });
      const rewritten = result.stdout.toString().trim();
      const ec = result.exitCode;

      if (ec === 0 && rewritten && rewritten !== cmd) {
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
    } catch {}
    process.stderr.write(
      `[serena-edit-guard] Editing '${relPath}' without tracing references.\nCall mcp__serena__find_referencing_symbols first to check downstream impact.\n`,
    );
    process.exit(1);
  }

  // --- NATIVE FILE TOOLS ---
  if (!isNativeFileTool(toolName)) {
    process.exit(0);
  }

  let filePath: string;
  if (toolName === "Grep" || toolName === "Search" || toolName === "Glob") {
    filePath = extractStr(raw, "path") || process.cwd();
  } else {
    filePath = extractStr(raw, "file_path");
  }

  if (!filePath) { process.exit(0); }

  const abs = resolve(filePath);

  if (abs.startsWith(DOT_CLAUDE_PFX)) { process.exit(0); }

  if (!abs.startsWith(SRC_PFX) && abs !== SRC_PFX.slice(0, -1)) { process.exit(0); }

  const ext = extOf(abs);

  if (ext && isAllowedExt(ext)) { process.exit(0); }

  const base = baseOf(abs);
  for (let i = 0; i < ALLOWED_NAMES.length; i++) {
    if (base.startsWith(ALLOWED_NAMES[i])) { process.exit(0); }
  }

  for (let i = 0; i < ALLOWED_PATHS.length; i++) {
    if (abs.indexOf(ALLOWED_PATHS[i]) >= 0) { process.exit(0); }
  }

  if (ext && isSourceExt(ext)) {
    if (toolName === "Edit" || toolName === "Write") {
      logSync("deny", toolName, filePath, "src_edit");
      writeSync(1, DENY_EDIT);
      process.exit(0);
    }
    logSync("deny", toolName, filePath, "src_explore");
    writeSync(1, DENY_EXPLORE);
    process.exit(0);
  }

  if (!ext && abs.startsWith(SRC_PFX) && (toolName === "Grep" || toolName === "Search" || toolName === "Glob")) {
    let isExempt = false;
    const absSlash = abs + "/";
    for (let i = 0; i < ALLOWED_PATHS.length; i++) {
      if (abs.indexOf(ALLOWED_PATHS[i]) >= 0 || absSlash.endsWith(ALLOWED_PATHS[i])) { isExempt = true; break; }
    }
    if (!isExempt) {
      if (toolName === "Grep" || toolName === "Search") {
        const grepType = extractStr(raw, "type");
        const grepGlob = extractStr(raw, "glob");
        if (!grepType && !grepGlob) {
          logSync("deny", toolName, filePath, "grep_src_dir");
          writeSync(1, DENY_EXPLORE);
          process.exit(0);
        }
      }
    }
  }

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
      const braceMatch = pattern.match(/\.\{([^}]+)\}/);
      if (braceMatch) {
        const exts = braceMatch[1].split(",");
        for (const e of exts) {
          if (isSourceExt(e.trim())) {
            logSync("deny", toolName, filePath, "glob_src_multi_ext");
            writeSync(1, DENY_EXPLORE);
            process.exit(0);
          }
        }
      }
      const cleaned = pattern.replace(/[{}*?,]/g, "");
      const pExt = extOf(cleaned);
      if (pExt && isSourceExt(pExt)) {
        logSync("deny", toolName, filePath, "glob_src_pattern");
        writeSync(1, DENY_EXPLORE);
        process.exit(0);
      }
    }
  }

  process.exit(0);
}
