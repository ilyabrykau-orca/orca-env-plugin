import { describe, test, expect, afterEach } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { recordDecision, blockRate, topDenies, resetAuditCache } from "../src/lib/audit";

function tempDb(): string {
  const dir = mkdtempSync(join(tmpdir(), "audit-test-"));
  return join(dir, "test.sqlite");
}

afterEach(() => resetAuditCache());

describe("audit edge cases", () => {
  test("blockRate on empty DB → 0", () => {
    expect(blockRate(tempDb())).toBe(0);
  });

  test("recordDecision + blockRate round-trip", () => {
    const p = tempDb();
    recordDecision({ sessionId: "s1", tool: "Read", target: "/foo.py", allow: false, reason: "deny" }, p);
    recordDecision({ sessionId: "s1", tool: "Bash", target: "ls", allow: true, reason: "ok" }, p);
    expect(blockRate(p)).toBe(0.5);
  });

  test("topDenies returns correct grouping", () => {
    const p = tempDb();
    recordDecision({ sessionId: "s1", tool: "Read", target: "/a.py", allow: false, reason: "x" }, p);
    recordDecision({ sessionId: "s1", tool: "Read", target: "/a.py", allow: false, reason: "x" }, p);
    recordDecision({ sessionId: "s1", tool: "Edit", target: "/b.ts", allow: false, reason: "y" }, p);
    const top = topDenies(10, p);
    expect(top[0].tool).toBe("Read");
    expect(top[0].target).toBe("/a.py");
    expect(top[0].count).toBe(2);
    expect(top[1].count).toBe(1);
  });

  test("recordDecision with empty target", () => {
    const p = tempDb();
    recordDecision({ sessionId: "s1", tool: "Bash", target: "", allow: true, reason: "empty" }, p);
    expect(blockRate(p)).toBe(0);
  });

  test("recordDecision with very long target", () => {
    const p = tempDb();
    const longTarget = "x".repeat(10000);
    recordDecision({ sessionId: "s1", tool: "Read", target: longTarget, allow: false, reason: "deny" }, p);
    const top = topDenies(1, p);
    expect(top[0].target.length).toBe(10000);
  });

  test("multiple sessions tracked independently", () => {
    const p = tempDb();
    recordDecision({ sessionId: "s1", tool: "Read", target: "/a", allow: false, reason: "x" }, p);
    recordDecision({ sessionId: "s2", tool: "Read", target: "/a", allow: true, reason: "y" }, p);
    expect(blockRate(p)).toBe(0.5);
  });
});
