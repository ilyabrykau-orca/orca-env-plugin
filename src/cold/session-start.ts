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
    CBM          = mcp__codebase-memory-mcp__*
                   Pick the right tool for the task — do not default to one.
                   search_code (text/regex), search_graph (structural), get_code_snippet (read symbol/range),
                   trace_path (call chains), get_architecture (high-level map), query_graph (Cypher),
                   index_repository, detect_changes, get_graph_schema, manage_adr, ingest_traces.

    Serena READ  = mcp__serena__find_symbol, get_symbols_overview, read_file,
                   find_referencing_symbols, search_for_pattern, find_file, list_dir
                   (no guard — use freely for exploration and reading)

    Serena WRITE = mcp__serena__replace_symbol_body, replace_content, insert_after_symbol,
                   insert_before_symbol, rename_symbol, safe_delete_symbol
                   ⚠ MUST call find_referencing_symbols BEFORE any WRITE in the same turn.

    CTX          = mcp__plugin_context-mode_context-mode__*
                   Pick the right tool for the task.
                   ctx_batch_execute (primary — runs commands, auto-indexes, searches in one call),
                   ctx_search, ctx_execute, ctx_execute_file, ctx_fetch_and_index, ctx_index.
  </tool_aliases>

  <routing_rules>
    Source code (.go .ts .py .c .h):
      Explore/understand → CBM — pick right tool per task
      Read a symbol      → Serena READ (find_symbol, get_symbols_overview, read_file)
      WRITE              → Serena WRITE — call find_referencing_symbols FIRST, same turn
      NEVER              → native Read / Glob / Grep / Bash-cat / Edit / Write / sed

    Non-source (configs, logs, docs, diffs):
      read to Edit  → native Read then Edit
      analyze only  → CTX ctx_execute_file or ctx_batch_execute

    Research / shell commands:
      run commands  → CTX ctx_batch_execute(commands, queries) — ONE call, auto-indexes
      follow-up     → CTX ctx_search(queries: [...])

    Compute / parse / transform:
      scripts       → CTX ctx_execute(language, code)

    Web / external docs:
      fetch         → CTX ctx_fetch_and_index — never WebFetch / curl / wget

    Store for later:
      index         → CTX ctx_index(content, source)

    Write files:
      non-source    → native Write (create) / Edit (modify)
      source code   → Serena WRITE only
      never         → ctx_execute or Bash to write files
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
    `• Source code explore  → CBM (mcp__codebase-memory-mcp__*) — pick right tool per task\n` +
    `• Source code read sym → Serena READ (find_symbol, get_symbols_overview, read_file)\n` +
    `• Source code WRITE    → Serena WRITE — find_referencing_symbols FIRST, same turn\n` +
    `• Non-source / shell   → CTX ctx_batch_execute primary; ctx_search for follow-up\n` +
    `• Docs/config/logs     → native Read/Edit/Write\n` +
    `• External docs/web    → mcp__docs__search_docs, mcp__exa__web_search_exa`,
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
