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
