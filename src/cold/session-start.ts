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
    Raw tool output floods your context window. Route all tool output to the sandbox using the aliases below.
  </priority_instructions>

  <tool_aliases>
    CBM  = codebase-memory-mcp  → mcp__codebase-memory-mcp__search_code, search_graph, get_code_snippet, trace_path
    Serena = serena             → mcp__serena__replace_symbol_body, replace_content, insert_after_symbol (find_referencing_symbols first)
    CTX  = context-mode         → mcp__plugin_context-mode_context-mode__ctx_batch_execute (primary), ctx_search, ctx_execute, ctx_execute_file, ctx_fetch_and_index, ctx_index
  </tool_aliases>

  <routing_rules>
    Source code (.go .ts .py .c .h):
      explore → CBM only          (never Read/Glob/Grep/Bash-cat on source)
      edit    → Serena only       (find_referencing_symbols first; never Edit/Write/sed)

    Non-source (configs, logs, docs, diffs):
      read to Edit  → native Read (Edit needs content in context)
      analyze only  → CTX ctx_execute_file or ctx_batch_execute

    Research / shell output:
      any command   → CTX ctx_batch_execute(commands, queries)  — ONE call, auto-indexes, then ctx_search
      follow-up     → CTX ctx_search(queries: [...])

    Data processing:
      compute/parse → CTX ctx_execute(language, code)

    Web / external docs:
      fetch         → CTX ctx_fetch_and_index(url, source) then ctx_search   (never WebFetch/curl/wget)

    Store for later:
      index         → CTX ctx_index(content, source)

    Write files:
      all types     → native Write (create) / Edit (modify)   (never ctx_execute or Bash)
  </routing_rules>

  <forbidden_actions>
    - Read/Glob/Grep/Edit on source files → use CBM or Serena
    - ctx_execute_file on source files    → use CBM get_code_snippet
    - WebFetch or curl/wget               → use CTX ctx_fetch_and_index
    - Bash producing >20 lines            → use CTX ctx_batch_execute
    - ctx_execute/ctx_execute_file to write files → use native Write/Edit
  </forbidden_actions>

  <output_constraints>
    <word_limit>Keep your final response under 500 words.</word_limit>
    <artifact_policy>Write artifacts to FILES (native Write). Return only: file path + 1-line description.</artifact_policy>
    <response_format>Actions taken (2-3 bullets) · Files modified · Key findings</response_format>
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
    `• Source code explore → CBM (search_code, search_graph, get_code_snippet, trace_path)\n` +
    `• Source code edit    → Serena (find_referencing_symbols → replace_symbol_body / replace_content)\n` +
    `• Non-source research → CTX ctx_batch_execute(commands, queries) primary; ctx_search for follow-up\n` +
    `• Docs/config/logs    → native Read/Edit/Write\n` +
    `• External docs/web   → mcp__docs__search_docs, mcp__exa__web_search_exa`,
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
