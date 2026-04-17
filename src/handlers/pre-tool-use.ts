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
