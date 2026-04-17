import { describe, test, expect } from "bun:test";
import { runBinary, PLUGIN_ROOT } from "./helpers";
import { readFileSync, rmSync } from "fs";
import { join } from "path";

const STATE_DIR = join(PLUGIN_ROOT, "state");
const STATE_FILE = join(STATE_DIR, "refs-traced.json");

describe("post-tool-use", () => {
  test("creates state file for find_referencing_symbols", async () => {
    // Clean state
    rmSync(STATE_DIR, { recursive: true, force: true });

    const r = await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: { name_path: "TestClass", relative_path: "src/test.py" },
      session_id: "test-post-tool",
    });
    expect(r.exitCode).toBe(0);

    const state = JSON.parse(readFileSync(STATE_FILE, "utf-8"));
    expect(state.session_id).toBe("test-post-tool");
    expect(state.traced["src/test.py"]).toBeDefined();

    // Cleanup
    rmSync(STATE_DIR, { recursive: true, force: true });
  });

  test("ignores non-refs tools", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });

    const r = await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_symbol",
      tool_input: { name_path_pattern: "Foo" },
      session_id: "test-ignore",
    });
    expect(r.exitCode).toBe(0);
    // State file should NOT exist
    try {
      readFileSync(STATE_FILE);
      expect(true).toBe(false); // should not reach
    } catch {}
  });
});
