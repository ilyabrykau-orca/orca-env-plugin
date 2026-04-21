import { homedir } from "node:os";

const HOME = homedir();
const SRC_PFX = `${HOME}/src/`;
const DOT_CLAUDE_PFX = `${HOME}/.claude/`;

// ---------------------------------------------------------------------------
// Canonical extension / filename / path tables
// ---------------------------------------------------------------------------

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

const SOURCE_GREP_TYPES = new Set([
  "go", "ts", "tsx", "js", "jsx", "rust", "py", "python",
  "c", "cpp", "h", "rb", "ruby", "java", "kt", "kotlin", "php", "scala", "swift",
]);

export const ALLOWED_NAMES = [
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

export const ALLOWED_PATHS = [
  "/docs/", "/doc/", "/documentation/",
  "/generated/", "/gen/",
  "/vendor/", "/node_modules/",
  "/testdata/", "/test_data/", "/fixtures/",
  "/.github/", "/.vscode/", "/.idea/",
  "/scripts/", "/hack/",
  "/deploy/", "/chart/", "/charts/", "/templates/",
];

const BASH_EDIT_WORDS = new Set([
  "sed", "awk", "perl", "ruby",
  "python", "python3", "node", "bun", "deno", "tsx",
  "cp", "mv", "rm", "ln", "chmod", "chown",
  "touch", "dd", "tee",
]);

// Deny reasons (HINT_* retained for public API compat)
export const HINT_CBM_SEARCH = "Use codebase-memory-mcp for source-code exploration: search_code, search_graph, get_code_snippet, trace_path.";
export const HINT_SERENA_EDIT = "Use Serena for source-code edits: replace_symbol_body, replace_content, insert_after_symbol.";
export const HINT_CBM_READ = HINT_CBM_SEARCH;

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

export function extOf(path: string): string {
  const lastSlash = path.lastIndexOf("/");
  const lastDot = path.lastIndexOf(".");
  if (lastDot <= lastSlash) return "";
  return path.substring(lastDot + 1).toLowerCase();
}

export function baseOf(path: string): string {
  const i = path.lastIndexOf("/");
  return i < 0 ? path : path.substring(i + 1);
}

export function resolvePath(p: string, cwd: string = process.cwd()): string {
  let abs: string;
  if (p.length === 0) return p;
  if (p.charCodeAt(0) === 47) abs = p;
  else if (p.charCodeAt(0) === 126 && p.charCodeAt(1) === 47) abs = HOME + p.substring(1);
  else abs = cwd + "/" + p;
  if (abs.indexOf("..") >= 0) {
    const parts = abs.split("/");
    const out: string[] = [];
    for (const part of parts) {
      if (part === "..") { if (out.length > 1) out.pop(); }
      else if (part !== ".") out.push(part);
    }
    abs = out.join("/") || "/";
  }
  return abs;
}

function isAllowedName(base: string): boolean {
  for (const n of ALLOWED_NAMES) if (base.startsWith(n)) return true;
  return false;
}

function isAllowedPathComponent(abs: string): boolean {
  const normalized = abs.endsWith("/") ? abs : abs + "/";
  for (const c of ALLOWED_PATHS) if (normalized.indexOf(c) >= 0) return true;
  return false;
}

function isSourceCodePath(abs: string): { code: boolean; exempt: boolean } {
  if (abs.startsWith(DOT_CLAUDE_PFX)) return { code: false, exempt: true };
  if (!abs.startsWith(SRC_PFX) && abs !== SRC_PFX.slice(0, -1)) return { code: false, exempt: true };
  const ext = extOf(abs);
  if (ext && ALLOWED_EXTS.has(ext)) return { code: false, exempt: true };
  if (isAllowedName(baseOf(abs))) return { code: false, exempt: true };
  if (isAllowedPathComponent(abs)) return { code: false, exempt: true };
  if (ext && SOURCE_EXTS.has(ext)) return { code: true, exempt: false };
  return { code: false, exempt: false };
}

// ---------------------------------------------------------------------------
// Bash source-path scan (ports bashHasSourcePath from legacy hot path)
// ---------------------------------------------------------------------------

function bashSourceHit(cmd: string, cwd: string): "read" | "edit" | "" {
  let firstPathStart = -1;
  let pos = 0;
  while (pos < cmd.length) {
    const aIdx = cmd.indexOf(SRC_PFX, pos);
    const tIdx = cmd.indexOf("~/src/", pos);
    let start: number;
    if (aIdx < 0 && tIdx < 0) break;
    if (aIdx < 0) start = tIdx;
    else if (tIdx < 0) start = aIdx;
    else start = aIdx < tIdx ? aIdx : tIdx;

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
    while (path.length > 0) {
      const last = path.charCodeAt(path.length - 1);
      if (last === 58 || last === 46) path = path.substring(0, path.length - 1);
      else break;
    }
    if (path.charCodeAt(0) === 126) path = HOME + path.substring(1);
    const abs = resolvePath(path, cwd);
    pos = end > pos ? end : pos + 1;

    const info = isSourceCodePath(abs);
    if (info.exempt) continue;
    if (!info.code) continue;
    if (firstPathStart < 0) firstPathStart = start;
  }

  if (firstPathStart < 0) {
    const cdMatch = cmd.match(/\bcd\s+(~\/src\/[^\s;&|]+|\/?Users\/[^\s;&|]*\/src\/[^\s;&|]+)/);
    if (cdMatch) {
      let cdDir = cdMatch[1];
      if (cdDir.charCodeAt(0) === 126) cdDir = HOME + cdDir.substring(1);
      const cdAbs = resolvePath(cdDir, cwd);
      if (cdAbs.startsWith(SRC_PFX)) {
        const afterCd = cmd.substring(cmd.indexOf(cdMatch[0]) + cdMatch[0].length);
        const tokens = afterCd.replace(/^[\s;&|]+/, "").split(/\s+/);
        for (const tok of tokens) {
          if (tok.startsWith("-")) continue;
          const te = extOf(tok);
          if (te && SOURCE_EXTS.has(te) && !ALLOWED_EXTS.has(te)) {
            firstPathStart = cmd.indexOf(cdMatch[0]);
            break;
          }
        }
      }
    }
  }

  if (firstPathStart < 0) return "";

  const prefix = cmd.substring(0, firstPathStart);
  if (prefix.indexOf(">") >= 0) return "edit";
  if (/\btee\b/.test(prefix)) return "edit";
  const segs = prefix.split(/&&|\|\||;|\|/);
  const lastSeg = segs[segs.length - 1];
  const parts = lastSeg.trim().split(/\s+/);
  let idx = 0;
  while (idx < parts.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(parts[idx])) idx++;
  const word = parts[idx] ? baseOf(parts[idx]) : "";
  if (BASH_EDIT_WORDS.has(word)) return "edit";
  return "read";
}

// ---------------------------------------------------------------------------
// Decision API
// ---------------------------------------------------------------------------

export type ToolCall = { tool: string; args: Record<string, unknown> };
export type Decision = { allow: boolean; reason: string };

function pickFilePath(call: ToolCall): string {
  const a = call.args;
  if (call.tool === "Grep" || call.tool === "Glob" || call.tool === "Search") {
    return String(a.path ?? "");
  }
  return String(a.file_path ?? "");
}

function decideNativeFile(tool: string, filePath: string, args: Record<string, unknown>, cwd: string): Decision {
  if (!filePath) return { allow: true, reason: "no path" };
  const abs = resolvePath(filePath, cwd);

  const info = isSourceCodePath(abs);
  if (info.exempt) return { allow: true, reason: "exempt path" };

  if (info.code) {
    if (tool === "Edit" || tool === "Write") return { allow: false, reason: HINT_SERENA_EDIT };
    return { allow: false, reason: HINT_CBM_SEARCH };
  }

  const ext = extOf(abs);
  if (!ext && abs.startsWith(SRC_PFX) && (tool === "Grep" || tool === "Glob" || tool === "Search")) {
    const grepType = String(args.type ?? "");
    const grepGlob = String(args.glob ?? "");
    if (!grepType && !grepGlob) {
      return { allow: false, reason: HINT_CBM_SEARCH };
    }
  }

  if (tool === "Grep" || tool === "Search") {
    const grepType = String(args.type ?? "");
    if (grepType && SOURCE_GREP_TYPES.has(grepType)) return { allow: false, reason: HINT_CBM_SEARCH };
    const grepGlob = String(args.glob ?? "");
    if (grepGlob) {
      const gExt = extOf(grepGlob);
      if (gExt && SOURCE_EXTS.has(gExt)) return { allow: false, reason: HINT_CBM_SEARCH };
    }
  }

  if (tool === "Glob") {
    const pattern = String(args.pattern ?? "");
    if (pattern) {
      const braceMatch = pattern.match(/\.\{([^}]+)\}/);
      if (braceMatch) {
        for (const e of braceMatch[1].split(",")) {
          if (SOURCE_EXTS.has(e.trim())) return { allow: false, reason: HINT_CBM_SEARCH };
        }
      }
      const cleaned = pattern.replace(/[{}*?,]/g, "");
      const pExt = extOf(cleaned);
      if (pExt && SOURCE_EXTS.has(pExt)) return { allow: false, reason: HINT_CBM_SEARCH };
    }
  }

  return { allow: true, reason: "non-code" };
}

export function decide(call: ToolCall, cwd: string = process.cwd()): Decision {
  const { tool, args } = call;

  if (tool === "Read") return decideNativeFile("Read", pickFilePath(call), args, cwd);
  if (tool === "Edit" || tool === "Write") return decideNativeFile(tool, pickFilePath(call), args, cwd);
  if (tool === "Grep" || tool === "Glob" || tool === "Search") {
    const path = pickFilePath(call) || cwd;
    return decideNativeFile(tool, path, args, cwd);
  }

  if (tool === "Bash") {
    const cmd = String(args.command ?? "");
    if (!cmd) return { allow: true, reason: "empty" };
    const hit = bashSourceHit(cmd, cwd);
    if (hit === "read") return { allow: false, reason: HINT_CBM_SEARCH };
    if (hit === "edit") return { allow: false, reason: HINT_SERENA_EDIT };
    return { allow: true, reason: "bash passthrough" };
  }

  return { allow: true, reason: "no rule" };
}

// Back-compat: legacy tests imported a flat `decide` — kept identical signature.
// Back-compat constants for pre-existing imports.
export const CODE_EXTENSIONS = new Set(Array.from(SOURCE_EXTS).map((e) => "." + e));
