import { describe, test, expect } from "bun:test";
import { mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { handlePostToolUse } from "../src/cold/post-tool-use";
import { recordDecision, blockRate, resetAuditCache } from "../src/lib/audit";
import { incrementTurn, getTurn } from "../src/lib/session-state";
import { decide } from "../src/lib/routing";
import { SRC } from "./helpers";

describe("post-tool-use edge cases", () => {
  test("wrong tool_name -> exitCode 0", () => {
    const r = handlePostToolUse({ tool_name: "mcp__serena__replace_symbol_body", tool_input: { relative_path: "foo.py" }, session_id: "s1" });
    expect(r.exitCode).toBe(0);
  });
  test("error response -> exitCode 0", () => {
    const r = handlePostToolUse({ tool_name: "mcp__serena__find_referencing_symbols", tool_input: { relative_path: "foo.py", name_path: "Foo" }, session_id: "s1", tool_response: { is_error: true } });
    expect(r.exitCode).toBe(0);
  });
  test("empty relative_path -> exitCode 0", () => {
    const r = handlePostToolUse({ tool_name: "mcp__serena__find_referencing_symbols", tool_input: { name_path: "Foo" }, session_id: "s1" });
    expect(r.exitCode).toBe(0);
  });
});

describe("Bash cd+source detection", () => {
  test("cd to src subdir && cat .py -> denied", () => {
    const r = decide({ tool: "Bash", args: { command: "cd " + SRC + "/orca && cat views.py" } }, "/tmp");
    expect(r.allow).toBe(false);
  });
  test("cd to src subdir && ls -> allowed", () => {
    const r = decide({ tool: "Bash", args: { command: "cd " + SRC + "/orca && ls" } }, "/tmp");
    expect(r.allow).toBe(true);
  });
  test("cd to src subdir && cat README.md -> allowed", () => {
    const r = decide({ tool: "Bash", args: { command: "cd " + SRC + "/orca && cat README.md" } }, "/tmp");
    expect(r.allow).toBe(true);
  });
  test("cd to src subdir && sed source.go -> denied", () => {
    const r = decide({ tool: "Bash", args: { command: "cd " + SRC + "/orca && sed source.go" } }, "/tmp");
    expect(r.allow).toBe(false);
  });
});

describe("Grep/Glob on src subdirs", () => {
  test("Grep on src/orca with no type/glob -> denied", () => {
    const r = decide({ tool: "Grep", args: { path: SRC + "/orca", pattern: "func" } }, SRC);
    expect(r.allow).toBe(false);
  });
  test("Grep on src with glob=*.md -> allowed", () => {
    const r = decide({ tool: "Grep", args: { path: SRC, glob: "*.md", pattern: "x" } }, SRC);
    expect(r.allow).toBe(true);
  });
  test("Glob on src/orca with *.go -> denied", () => {
    const r = decide({ tool: "Glob", args: { path: SRC + "/orca", pattern: "*.go" } }, SRC);
    expect(r.allow).toBe(false);
  });
  test("Glob on src with *.json -> allowed", () => {
    const r = decide({ tool: "Glob", args: { path: SRC, pattern: "*.json" } }, SRC);
    expect(r.allow).toBe(true);
  });
  test("Search on src/orca with type=py -> denied", () => {
    const r = decide({ tool: "Search", args: { path: SRC + "/orca", type: "py", pattern: "import" } }, SRC);
    expect(r.allow).toBe(false);
  });
  test("bare ~/src itself -> allowed (parent dir, not code)", () => {
    const r = decide({ tool: "Grep", args: { path: SRC, pattern: "func" } }, SRC);
    expect(r.allow).toBe(true);
  });
});

describe("concurrent session-state", () => {
  test("rapid incrementTurn preserves count", () => {
    const root = mkdtempSync(join(tmpdir(), "concurrent-"));
    for (let i = 0; i < 20; i++) incrementTurn("rapid", root);
    expect(getTurn("rapid", root)).toBe(20);
  });
});

describe("audit blockRate edge cases", () => {
  function tempDb() { return join(mkdtempSync(join(tmpdir(), "br-")), "a.sqlite"); }
  test("all denies -> 1.0", () => {
    const p = tempDb();
    for (let i = 0; i < 5; i++) recordDecision({ sessionId: "s", tool: "Read", target: "/x", allow: false, reason: "d" }, p);
    expect(blockRate(p)).toBe(1);
    resetAuditCache();
  });
  test("all allows -> 0", () => {
    const p = tempDb();
    for (let i = 0; i < 5; i++) recordDecision({ sessionId: "s", tool: "Bash", target: "ls", allow: true, reason: "ok" }, p);
    expect(blockRate(p)).toBe(0);
    resetAuditCache();
  });
  test("single deny -> 1.0", () => {
    const p = tempDb();
    recordDecision({ sessionId: "s", tool: "Read", target: "/a", allow: false, reason: "x" }, p);
    expect(blockRate(p)).toBe(1);
    resetAuditCache();
  });
});
