import { PLUGIN_ROOT } from "../lib/constants";
import { readState, writeState } from "../lib/state";

interface PostToolInput {
  tool_name: string;
  tool_input: Record<string, unknown>;
  tool_response?: { is_error?: boolean };
  session_id?: string;
}

export function handlePostToolUse(input: PostToolInput): {
  stdout?: string;
  exitCode: number;
} {
  if (input.tool_name !== "mcp__serena__find_referencing_symbols") {
    return { exitCode: 0 };
  }

  if (input.tool_response?.is_error) {
    return { exitCode: 0 };
  }

  const relativePath = (input.tool_input.relative_path as string) ?? "";
  if (!relativePath) return { exitCode: 0 };

  const sessionId = input.session_id ?? "unknown";
  const stateFile = `${PLUGIN_ROOT}/state/refs-traced.json`;
  const state = readState(stateFile);

  // Reset if session changed
  if (state.session_id !== sessionId) {
    state.session_id = sessionId;
    state.traced = {};
  }

  state.traced[relativePath] = Math.floor(Date.now() / 1000);
  writeState(stateFile, state);

  return { exitCode: 0 };
}
