import { describe, test, expect } from "bun:test";
import { handlePreToolUse, type HookPayload } from "../src/hot/pre-tool-use";
import { runBinary, isDenied, isAllowed, PLUGIN_ROOT } from "./helpers";

describe("handlePreToolUse — malformed payloads", () => {
  test("empty tool_input → approve", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: {} });
    expect(r.decision).toBe("approve");
  });

  test("missing file_path in Read → approve (fail open)", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { other: "x" } });
    expect(r.decision).toBe("approve");
  });

  test("null file_path in Read → approve", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: null } as any });
    expect(r.decision).toBe("approve");
  });

  test("numeric file_path → approve (coerced to string, no ext)", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: 12345 } as any });
    expect(r.decision).toBe("approve");
  });

  test("unknown tool → approve", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "FutureTool", tool_input: { x: 1 } });
    expect(r.decision).toBe("approve");
  });

  test("Bash with no command → approve", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Bash", tool_input: {} });
    expect(r.decision).toBe("approve");
  });

  test("Bash with null command → approve", () => {
    const r = handlePreToolUse({ session_id: "s1", tool_name: "Bash", tool_input: { command: null } as any });
    expect(r.decision).toBe("approve");
  });
});

describe("CLI — malformed stdin payloads", () => {
  test("empty stdin → exit 0", async () => {
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob([""]),
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    expect(await proc.exited).toBe(0);
  });

  test("not JSON → exit 0", async () => {
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob(["this is not json at all"]),
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    expect(await proc.exited).toBe(0);
  });

  test("JSON without tool_name → exit 0", async () => {
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob([JSON.stringify({ tool_input: {} })]),
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    expect(await proc.exited).toBe(0);
  });

  test("JSON with empty tool_name → exit 0", async () => {
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob([JSON.stringify({ tool_name: "", tool_input: {} })]),
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    expect(await proc.exited).toBe(0);
  });

  test("unknown event arg → exit 0", async () => {
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "nonexistent-event"], {
      stdin: new Blob(["{}"])  ,
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    expect(await proc.exited).toBe(0);
  });

  test("session-start with empty JSON → exit 0", async () => {
    const r = await runBinary("session-start", {});
    expect(r.exitCode).toBe(0);
  });

  test("user-prompt-submit with empty JSON → exit 0", async () => {
    const r = await runBinary("user-prompt-submit", {});
    expect(r.exitCode).toBe(0);
  });

  test("stop with empty JSON → exit 0", async () => {
    const r = await runBinary("stop", {});
    expect(r.exitCode).toBe(0);
  });
});
