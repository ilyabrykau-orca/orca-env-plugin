export const CODE_EXTENSIONS = new Set([
  ".py", ".go", ".ts", ".tsx", ".js", ".jsx", ".rs",
  ".cpp", ".c", ".h", ".hpp", ".rb", ".java", ".kt",
  ".php", ".scala", ".swift", ".sh", ".bash",
]);

export type ToolCall = { tool: string; args: Record<string, unknown> };
export type Decision = { allow: boolean; reason: string };

const extOf = (p: string): string => {
  const i = p.lastIndexOf(".");
  return i < 0 ? "" : p.slice(i).toLowerCase();
};

const isCodePath = (p: string): boolean => CODE_EXTENSIONS.has(extOf(p));

const HINT_CBM_SEARCH = "Use codebase-memory-mcp: search_code, search_graph, get_code_snippet, trace_path.";
const HINT_SERENA_EDIT = "Use serena: replace_symbol_body, replace_content, insert_after_symbol.";
const HINT_CBM_READ = "Use mcp__serena__find_symbol or mcp__codebase-memory-mcp__get_code_snippet.";

export function decide(call: ToolCall): Decision {
  const { tool, args } = call;

  if (tool === "Read") {
    const p = String(args.file_path ?? "");
    if (isCodePath(p)) return { allow: false, reason: HINT_CBM_READ };
    return { allow: true, reason: "non-code file" };
  }

  if (tool === "Edit" || tool === "Write") {
    const p = String(args.file_path ?? "");
    if (isCodePath(p)) return { allow: false, reason: HINT_SERENA_EDIT };
    return { allow: true, reason: "non-code file" };
  }

  if (tool === "Grep" || tool === "Glob") {
    return { allow: false, reason: HINT_CBM_SEARCH };
  }

  if (tool === "Bash") {
    const cmd = String(args.command ?? "");
    const hit = [...CODE_EXTENSIONS].some((ext) => new RegExp(`\\S+${ext.replace(".", "\\.")}(\\s|$)`).test(cmd));
    if (hit && /^(cat|head|tail|less|more|sed|awk|grep|rg)\b/.test(cmd.trim())) {
      return { allow: false, reason: HINT_CBM_SEARCH };
    }
    return { allow: true, reason: "bash passthrough" };
  }

  return { allow: true, reason: "no rule matched" };
}
