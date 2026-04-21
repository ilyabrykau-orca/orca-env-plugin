import { describe, test, expect } from "bun:test";
import { handlePreToolUse, type HookPayload } from "../src/hot/pre-tool-use";
import { runBinary, isDenied, isAllowed, denyReason, contextText, SRC, PLUGIN_ROOT } from "./helpers";

const HOME = process.env.HOME!;

describe("extractStr via CLI — edge cases in JSON parsing", () => {
  test("tool_name with escaped quotes", async () => {
    const raw = '{"tool_name":"Read","tool_input":{"file_path":"' + SRC + '/orca/views.py"}}';
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob([raw]),
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    const stdout = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(0);
    expect(stdout).toContain("deny");
  });

  test("nested JSON values do not confuse extractStr", async () => {
    const raw = JSON.stringify({
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/views.py`, nested: { tool_name: "fake" } },
    });
    const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
      stdin: new Blob([raw]),
      stdout: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
    });
    const stdout = await new Response(proc.stdout).text();
    expect(await proc.exited).toBe(0);
    expect(stdout).toContain("deny");
  });
});

describe("hasShellChars via Bash routing — shell char detection", () => {
  test("pipe char → RTK skipped (no rewrite)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "echo hello | wc -l" },
    });
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toBe("");
  });

  test("semicolon → RTK skipped", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "echo a; echo b" },
    });
    expect(r.stdout).toBe("");
  });

  test("heredoc << → RTK skipped", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "cat <<EOF\nhello\nEOF" },
    });
    expect(r.stdout).toBe("");
  });

  test("backtick → RTK skipped", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "echo `date`" },
    });
    expect(r.stdout).toBe("");
  });

  test("dollar sign → RTK skipped", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "echo $HOME" },
    });
    expect(r.stdout).toBe("");
  });
});

describe("session-start — caveman detection", () => {
  test("CAVEMAN_MODE=ultra → output contains ultra", async () => {
    const r = await runBinary("session-start", { cwd: SRC }, { CAVEMAN_MODE: "ultra" });
    expect(contextText(r)).toContain("ultra");
  });

  test("CAVEMAN_MODE=1 maps to full", async () => {
    const r = await runBinary("session-start", { cwd: SRC }, { CAVEMAN_MODE: "1" });
    expect(contextText(r)).toContain("full");
  });

  test("CAVEMAN_MODE=lite → lite", async () => {
    const r = await runBinary("session-start", { cwd: SRC }, { CAVEMAN_MODE: "lite" });
    expect(contextText(r)).toContain("lite");
  });

  test("no CAVEMAN_MODE → no caveman in output", async () => {
    const r = await runBinary("session-start", { cwd: SRC }, { CAVEMAN_MODE: "" });
    expect(contextText(r)).not.toContain("CAVEMAN MODE DETECTED");
  });

  test("CAVEMAN_MODE=random → no caveman", async () => {
    const r = await runBinary("session-start", { cwd: SRC }, { CAVEMAN_MODE: "random" });
    expect(contextText(r)).not.toContain("CAVEMAN MODE DETECTED");
  });
});

describe("session-start — project detection", () => {
  test("cwd=~/src/orca-sensor → detects project", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-sensor` });
    expect(contextText(r)).toContain("orca");
  });

  test("cwd=/tmp → no project, still has routing", async () => {
    const r = await runBinary("session-start", { cwd: "/tmp" });
    const ctx = contextText(r);
    expect(ctx).not.toContain("SERENA WORKSPACE DETECTED");
    expect(ctx).toContain("TOOL ROUTING");
  });

  test("cwd=~/src → orca-unified", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    expect(contextText(r)).toContain("orca-unified");
  });
});

describe("stop hook — edge cases", () => {
  test("nonexistent transcript → exit 0", async () => {
    const r = await runBinary("stop", { transcript_path: "/nonexistent/path.jsonl", cwd: SRC });
    expect(r.exitCode).toBe(0);
  });

  test("missing transcript_path → exit 0", async () => {
    const r = await runBinary("stop", { cwd: SRC });
    expect(r.exitCode).toBe(0);
  });

  test("subagent-stop with no agent_transcript_path → exit 0", async () => {
    const r = await runBinary("subagent-stop", { cwd: SRC });
    expect(r.exitCode).toBe(0);
  });
});

describe("handlePreToolUse — deny reason routing", () => {
  test("Read on .py → CBM hint", () => {
    const r = handlePreToolUse({
      session_id: "s1", tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/views.py` },
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("codebase-memory-mcp");
  });

  test("Edit on .ts → Serena hint", () => {
    const r = handlePreToolUse({
      session_id: "s1", tool_name: "Edit",
      tool_input: { file_path: `${SRC}/orca/index.ts` },
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("Serena");
  });

  test("Write on .go → Serena hint", () => {
    const r = handlePreToolUse({
      session_id: "s1", tool_name: "Write",
      tool_input: { file_path: `${SRC}/orca-sensor/main.go` },
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("Serena");
  });

  test("Grep on source type → CBM hint", () => {
    const r = handlePreToolUse({
      session_id: "s1", tool_name: "Grep",
      tool_input: { path: SRC, type: "go", pattern: "func" },
    });
    expect(r.decision).toBe("deny");
    expect(r.reason).toContain("codebase-memory-mcp");
  });
});
