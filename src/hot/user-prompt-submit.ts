import { incrementTurn, DEFAULT_ROOT } from "../lib/session-state";

export const REINJECT_EVERY = 10;

export const REMINDER = [
  "CAVEMAN MODE ACTIVE (ultra). Drop articles/filler/pleasantries/hedging. Fragments OK.",
  "ROUTING: code search → codebase-memory-mcp (search_code, search_graph, get_code_snippet, trace_path).",
  "ROUTING: code edits → serena (find_referencing_symbols → replace_symbol_body/replace_content).",
  "ROUTING: docs → mcp__docs. Web → mcp__exa. Never native Read/Edit/Grep on code.",
].join(" ");

export type UpsPayload = { session_id: string };
export type UpsResult = { appendContext: string };

export function handleUserPromptSubmit(p: UpsPayload, root: string = DEFAULT_ROOT): UpsResult {
  const turn = incrementTurn(p.session_id, root);
  if (turn % REINJECT_EVERY === 0) return { appendContext: REMINDER };
  return { appendContext: "" };
}

export function runUserPromptSubmitCli(raw: string): void {
  let payload: UpsPayload = { session_id: "" };
  try { payload = JSON.parse(raw) as UpsPayload; } catch {}
  const r = handleUserPromptSubmit(payload);
  if (r.appendContext) process.stdout.write(r.appendContext);
  process.exit(0);
}
