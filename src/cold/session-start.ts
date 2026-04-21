import { REMINDER } from "../hot/user-prompt-submit";
import { isHealthy, DEFAULT_BASE } from "../lib/claude-mem";
import { PROJECT_MAP, SRC_PREFIX } from "../lib/constants";
import { sessionContext } from "../lib/protocol";

export type SessionStartPayload = {
  session_id: string;
  source: "startup" | "resume" | "clear" | "compact";
  cwd: string;
};

export type SessionStartOpts = { memBase?: string };
export type SessionStartResult = { appendContext: string; exitCode?: number; stdout?: string };

function detectProject(cwd: string): string {
  for (const [dir, project] of Object.entries(PROJECT_MAP)) {
    if (cwd.includes(`/${dir}`)) return project;
  }
  if (cwd.includes("/src/orca")) return "orca";
  if (cwd === SRC_PREFIX.slice(0, -1) || cwd + "/" === SRC_PREFIX) return "orca-unified";
  return "";
}

function detectCaveman(): string {
  const val = (process.env.CAVEMAN_MODE ?? "").toLowerCase();
  switch (val) {
    case "ultra": return "ultra";
    case "full": case "1": case "true": case "active": return "full";
    case "lite": return "lite";
    default: return "";
  }
}

export async function handleSessionStart(
  p: SessionStartPayload,
  opts: SessionStartOpts = {},
): Promise<SessionStartResult> {
  const project = detectProject(p.cwd);
  const parts: string[] = [];

  if (project) {
    parts.push(
      `SERENA WORKSPACE DETECTED: project='${project}' at ${p.cwd}\n` +
      `IMMEDIATELY call: mcp__serena__activate_project(project=${project})\n` +
      `Then: mcp__serena__list_memories() and read relevant memories.`,
    );
  }

  const caveman = detectCaveman();
  if (caveman) parts.push(`CAVEMAN MODE DETECTED → invoke: /caveman ${caveman}`);

  parts.push(
    `TOOL ROUTING (hooks enforce — violations are hard-blocked):\n` +
    `• Source-code exploration/read/search → codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path\n` +
    `• Source-code edits → Serena: replace_symbol_body, replace_content, insert_after_symbol\n` +
    `• Docs/config/logs/diffs → native Read/Edit/Write\n` +
    `• External docs/web → mcp__docs__search_docs, mcp__exa__web_search_exa`,
  );

  if (p.source === "resume" || p.source === "compact") {
    parts.push(REMINDER);
  }

  // claude-mem health probe (non-blocking, informational)
  const memBase = opts.memBase ?? DEFAULT_BASE;
  try {
    const up = await isHealthy(memBase);
    if (!up) parts.push("NOTE: claude-mem worker not reachable at " + memBase + ". Memory search degraded.");
  } catch { /* ignore */ }

  const appendContext = parts.join("\n\n");
  return { appendContext, stdout: sessionContext(appendContext), exitCode: 0 };
}

export async function runSessionStartCli(): Promise<void> {
  const stdin = await Bun.stdin.text();
  let payload: SessionStartPayload = { session_id: "", source: "startup", cwd: process.cwd() };
  try {
    const parsed = JSON.parse(stdin) as Partial<SessionStartPayload>;
    payload = {
      session_id: parsed.session_id ?? "",
      source: (parsed.source as SessionStartPayload["source"]) ?? "startup",
      cwd: parsed.cwd ?? process.cwd(),
    };
  } catch {}
  const r = await handleSessionStart(payload);
  if (r.stdout) process.stdout.write(r.stdout);
  process.exit(r.exitCode ?? 0);
}
