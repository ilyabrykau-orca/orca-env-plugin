import { describe, test, expect } from "bun:test";
import { runBinary, contextText, SRC } from "./helpers";

describe("session-start", () => {
  test("detects orca-unified from ~/src", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    const ctx = contextText(r);
    expect(ctx).toContain("orca-unified");
    expect(ctx).toContain("activate_project");
  });

  test("detects orca from ~/src/orca", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca` });
    expect(contextText(r)).toContain("project='orca'");
  });

  test("detects orca-sensor", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-sensor` });
    expect(contextText(r)).toContain("orca-sensor");
  });

  test("detects orca-runtime-sensor", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-runtime-sensor` });
    expect(contextText(r)).toContain("orca-runtime-sensor");
  });

  test("no project from /tmp", async () => {
    const r = await runBinary("session-start", { cwd: "/tmp" });
    const ctx = contextText(r);
    expect(ctx).not.toContain("SERENA WORKSPACE DETECTED");
    expect(ctx).toContain("TOOL ROUTING");
  });

  test("always includes routing table", async () => {
    const r = await runBinary("session-start", { cwd: "/tmp" });
    const ctx = contextText(r);
    expect(ctx).toContain("codebase-memory-mcp");
    expect(ctx).toContain("Serena");
  });

  test("output is valid JSON", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    expect(r.json).not.toBeNull();
    expect(r.json.hookSpecificOutput.hookEventName).toBe("SessionStart");
  });
});
