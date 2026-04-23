import { REMINDER } from "../hot/user-prompt-submit";

import { PROJECT_MAP, SRC_PREFIX } from "../lib/constants";
import { sessionContext } from "../lib/protocol";

export type SessionStartPayload = {
  session_id: string;
  source: "startup" | "resume" | "clear" | "compact";
  cwd: string;
};

export type SessionStartOpts = Record<string, never>;
export type SessionStartResult = { appendContext: string; exitCode?: number; stdout?: string };

function detectProject(cwd: string): string {
  if (!cwd) return "";
  for (const [dir, project] of Object.entries(PROJECT_MAP)) {
    if (cwd.includes(`/${dir}`)) return project;
  }
  if (cwd.includes("/src/orca")) return "orca";
  if (cwd === SRC_PREFIX.slice(0, -1) || cwd + "/" === SRC_PREFIX) return "orca-unified";
  return "";
}


const CONTEXT_WINDOW_PROTECTION = `<context_window_protection>
  <priority_instructions>
    Raw tool output floods your context window. You MUST use context-mode MCP tools to keep raw data in the sandbox.
  </priority_instructions>

  <tool_selection_hierarchy>
    1. SOURCE READ: search_code, search_graph, get_code_snippet, trace_path (codebase-memory-mcp)
       - Mandatory for all source code reads/searches (.go, .ts, .py, .c, .h).
    2. SOURCE EDIT: replace_symbol_body, replace_content, insert_after_symbol (Serena)
       - Mandatory for source code edits. MUST run find_referencing_symbols before any edit.
    3. GATHER: mcp__plugin_context-mode_context-mode__ctx_batch_execute(commands, queries)
       - Primary tool for non-source research. Runs all commands, auto-indexes, and searches.
       - ONE call replaces many individual steps.
       - Each command: {label: "descriptive section header", command: "shell command"}
       - label becomes the FTS5 chunk title — use descriptive labels for better search.
    4. FOLLOW-UP: mcp__plugin_context-mode_context-mode__ctx_search(queries: ["q1", "q2", ...])
       - Use for all follow-up questions. ONE call, many queries.
    5. PROCESSING: mcp__plugin_context-mode_context-mode__ctx_execute(language, code) | mcp__plugin_context-mode_context-mode__ctx_execute_file(path, language, code)
       - Use for API calls, log analysis, and data processing.
  </tool_selection_hierarchy>

  <forbidden_actions>
    - DO NOT use native Read/Edit/Grep/Glob, mcp__plugin_context-mode_context-mode__ctx_batch_execute, or mcp__plugin_context-mode_context-mode__ctx_execute_file on source code (.go, .ts, .py, .c, .h). Use codebase-memory-mcp and Serena exclusively.
    - DO NOT use Bash for commands producing >20 lines of output.
    - DO NOT use Read for non-source analysis (use execute_file). Read IS correct for non-source files you intend to Edit.
    - DO NOT use WebFetch (use mcp__plugin_context-mode_context-mode__ctx_fetch_and_index instead).
    - Bash is ONLY for git/mkdir/rm/mv/navigation.
    - DO NOT use mcp__plugin_context-mode_context-mode__ctx_execute or mcp__plugin_context-mode_context-mode__ctx_execute_file to create, modify, or overwrite files.
      ctx_execute is for data analysis, log processing, and computation only.
  </forbidden_actions>

  <file_writing_policy>
    ALWAYS use the native Write tool to create non-source files and Edit tool to modify non-source files.
    For source code (.go, .ts, .py, .c, .h), ALWAYS use Serena tools.
    NEVER use mcp__plugin_context-mode_context-mode__ctx_execute, mcp__plugin_context-mode_context-mode__ctx_execute_file, or Bash to write file content.
    This applies to configs, plans, specs, YAML, JSON, markdown.
  </file_writing_policy>

  <output_constraints>
    <word_limit>Keep your final response under 500 words.</word_limit>
    <artifact_policy>
      Write artifacts (configs, PRDs) to FILES using the native Write tool. NEVER return them as inline text.
      Use Edit tool (or Serena for source code) for modifications to existing files.
      Return only: file path + 1-line description.
    </artifact_policy>
    <response_format>
      Your response must be a concise summary:
      - Actions taken (2-3 bullets)
      - File paths created/modified
      - Knowledge base source labels (so parent can search)
      - Key findings
    </response_format>
  </output_constraints>
</context_window_protection>`;

export async function handleSessionStart(
  p: SessionStartPayload,
  opts: SessionStartOpts = {},
): Promise<SessionStartResult> {
  const project = detectProject(p.cwd);
  const parts: string[] = [];

  if (project) {
    parts.push(
      `SERENA WORKSPACE DETECTED: project='${project}' at ${p.cwd}\n` +
      `IMMEDIATELY call: mcp__serena__activate_project(project=${project})`,
    );
  }

  parts.push(
    `TOOL ROUTING (hooks enforce — violations are hard-blocked):\n` +
    `• Source-code exploration/read/search → codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path\n` +
    `• Source-code edits → Serena: replace_symbol_body, replace_content, insert_after_symbol\n` +
    `• Docs/config/logs/diffs → native Read/Edit/Write\n` +
    `• External docs/web → mcp__docs__search_docs, mcp__exa__web_search_exa`,
  );

  parts.push(CONTEXT_WINDOW_PROTECTION);

  if (p.source === "resume" || p.source === "compact") {
    parts.push(REMINDER);
  }

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
