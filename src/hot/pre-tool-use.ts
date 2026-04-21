import { readFileSync, writeSync, appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { decide } from "../lib/routing";
import { recordDecision } from "../lib/audit";

const HOME = homedir();
const LOG_DIR = `${HOME}/.claude/logs`;
const LOG_FILE = `${LOG_DIR}/hooks.jsonl`;
const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT ?? "";
const STATE_FILE = `${PLUGIN_ROOT}/state/refs-traced.json`;

// ---------------------------------------------------------------------------
// Public programmatic API (tested)
// ---------------------------------------------------------------------------

export type HookPayload = {
  session_id: string;
  tool_name: string;
  tool_input: Record<string, unknown>;
};

export type HookResult = { decision: "approve" | "deny"; reason: string };

export function handlePreToolUse(p: HookPayload): HookResult {
  const d = decide({ tool: p.tool_name, args: p.tool_input });
  const target =
    String(p.tool_input.file_path ?? "") ||
    String(p.tool_input.path ?? "") ||
    String(p.tool_input.command ?? "");

  try {
    recordDecision({
      sessionId: p.session_id,
      tool: p.tool_name,
      target: target.substring(0, 400),
      allow: d.allow,
      reason: d.reason,
    });
  } catch {}

  return { decision: d.allow ? "approve" : "deny", reason: d.reason };
}

// ---------------------------------------------------------------------------
// Legacy raw-stdin CLI entry (keeps zero-alloc deny path + RTK rewrite + serena guard)
// ---------------------------------------------------------------------------

const DENY_EXPLORE = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use codebase-memory-mcp for source-code exploration: search_code, search_graph, get_code_snippet, trace_path."}}';
const DENY_EDIT = '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Use Serena for source-code edits: replace_symbol_body, replace_content, insert_after_symbol."}}';

function extractStr(raw: string, key: string): string {
  const needle = `"${key}":"`;
  const i = raw.indexOf(needle);
  if (i < 0) return "";
  const start = i + needle.length;
  let end = start;
  while (end < raw.length) {
    if (raw.charCodeAt(end) === 34 && raw.charCodeAt(end - 1) !== 92) break;
    end++;
  }
  return raw.substring(start, end);
}

let logDirReady = false;
function logSync(action: string, tool: string, path: string, reason: string): void {
  try {
    if (!logDirReady) { mkdirSync(LOG_DIR, { recursive: true }); logDirReady = true; }
    const ts = Date.now();
    appendFileSync(LOG_FILE, `{"ts":${ts},"h":"ct","a":"${action}","t":"${tool}","p":"${path.substring(0, 80).replace(/"/g, '')}","r":"${reason}"}\n`);
  } catch {}
}

const SERENA_EDIT_TOOLS = new Set([
  "mcp__serena__replace_symbol_body",
  "mcp__serena__replace_content",
  "mcp__serena__insert_after_symbol",
  "mcp__serena__insert_before_symbol",
  "mcp__serena__rename_symbol",
  "mcp__serena__safe_delete_symbol",
]);

function hasShellChars(cmd: string): boolean {
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd.charCodeAt(i);
    if (c === 124 || c === 38 || c === 59 || c === 62 || c === 60 ||
        c === 36 || c === 40 || c === 41 || c === 96) return true;
  }
  return cmd.indexOf("<<") >= 0;
}

export function runPreToolUseCli(raw: string): void {
  const toolName = extractStr(raw, "tool_name");
  if (!toolName) { process.exit(0); }

  // Route through routing.decide for all tools it handles.
  let toolInput: Record<string, unknown> = {};
  try {
    const parsed = JSON.parse(raw) as { tool_input?: Record<string, unknown>; session_id?: string };
    toolInput = parsed.tool_input ?? {};
  } catch {}

  const sessionId = extractStr(raw, "session_id");

  // Serena edit guard (not handled by routing)
  if (SERENA_EDIT_TOOLS.has(toolName)) {
    const relPath = extractStr(raw, "relative_path");
    if (!relPath) process.exit(0);
    try {
      const stateRaw = readFileSync(STATE_FILE, "utf-8");
      const sidNeedle = '"session_id":"';
      const sidStart = stateRaw.indexOf(sidNeedle);
      if (sidStart >= 0) {
        const sidValStart = sidStart + sidNeedle.length;
        const sidEnd = stateRaw.indexOf('"', sidValStart);
        const stateSid = stateRaw.substring(sidValStart, sidEnd);
        if (stateSid === sessionId && stateRaw.indexOf(`"${relPath}"`) >= 0) {
          process.exit(0);
        }
      }
    } catch {}
    process.stderr.write(
      `[serena-edit-guard] Editing '${relPath}' without tracing references.\nCall mcp__serena__find_referencing_symbols first.\n`,
    );
    process.exit(1);
  }

  // Routing decision for Read/Edit/Write/Grep/Glob/Search/Bash
  const d = decide({ tool: toolName, args: toolInput });

  const targetPath =
    String(toolInput.file_path ?? "") ||
    String(toolInput.path ?? "") ||
    String(toolInput.command ?? "");

  try {
    recordDecision({
      sessionId,
      tool: toolName,
      target: targetPath.substring(0, 400),
      allow: d.allow,
      reason: d.reason,
    });
  } catch {}

  if (!d.allow) {
    logSync("deny", toolName, targetPath, d.reason.substring(0, 40));
    const payload = d.reason === "Use Serena for source-code edits: replace_symbol_body, replace_content, insert_after_symbol."
      ? DENY_EDIT
      : DENY_EXPLORE;
    writeSync(1, payload);
    process.exit(0);
  }

  // Bash-only post-allow: RTK rewrite for simple commands
  if (toolName === "Bash") {
    const cmd = String(toolInput.command ?? "");
    if (!cmd) process.exit(0);
    if (process.env.CLAUDE_RAW === "1") process.exit(0);
    if (hasShellChars(cmd)) process.exit(0);

    try {
      const result = Bun.spawnSync(["rtk", "rewrite", cmd], { stdout: "pipe", stderr: "pipe" });
      const rewritten = result.stdout.toString().trim();
      const ec = result.exitCode;

      if (ec === 0 && rewritten && rewritten !== cmd) {
        const updatedInput = { ...toolInput, command: rewritten };
        logSync("rewrite", "Bash", cmd.substring(0, 80), "rtk");
        writeSync(1, JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: "RTK auto-rewrite",
            updatedInput,
          },
        }));
      } else if (ec === 3 && rewritten) {
        const updatedInput = { ...toolInput, command: rewritten };
        writeSync(1, JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            updatedInput,
          },
        }));
      }
    } catch {}
  }

  process.exit(0);
}
