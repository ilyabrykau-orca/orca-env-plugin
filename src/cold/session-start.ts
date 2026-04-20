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
  const project = detectProject(cwd);
  const parts: string[] = [];

  if (project) {
    parts.push(
      `SERENA WORKSPACE DETECTED: project='${project}' at ${cwd}\n` +
      `IMMEDIATELY call: mcp__serena__activate_project(project=${project})\n` +
      `Then: mcp__serena__list_memories() and read relevant memories.`,
    );
  }

  const caveman = detectCaveman();
  if (caveman) {
    parts.push(`CAVEMAN MODE DETECTED → invoke: /caveman ${caveman}`);
  }

  parts.push(
    `TOOL ROUTING (hooks enforce — violations are hard-blocked):\n` +
    `• Source-code exploration/read/search → codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path\n` +
    `• Source-code edits → Serena: replace_symbol_body, replace_content, insert_after_symbol\n` +
    `• Docs/config/logs/diffs → native Read/Edit/Write\n` +
    `• External docs/web → mcp__docs__search_docs, mcp__exa__web_search_exa`,
  );

  const ctx = parts.join("\n\n");
  return { stdout: sessionContext(ctx), exitCode: 0 };
}

function detectProject(cwd: string): string {
  for (const [dir, project] of Object.entries(PROJECT_MAP)) {
    if (cwd.includes(`/${dir}`)) return project;
  }

  if (cwd.includes("/src/orca")) return "orca";
  if (cwd === SRC_PREFIX.slice(0, -1) || cwd + "/" === SRC_PREFIX) {
    return "orca-unified";
  }

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
