import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { recordDecision, topDenies, blockRate, resetAuditCache } from "../../src/lib/audit";

const dbPath = join(tmpdir(), `audit-test-${Date.now()}.sqlite`);

beforeEach(() => {
  resetAuditCache();
  try { rmSync(dbPath, { force: true }); } catch {}
});

test("record + query block rate", () => {
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.md", allow: true, reason: "doc" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Grep", target: "/x", allow: false, reason: "cbm" }, dbPath);
  expect(blockRate(dbPath)).toBeCloseTo(2 / 3, 2);
});

test("topDenies ranks by count", () => {
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Grep", target: "/y", allow: false, reason: "cbm" }, dbPath);
  const top = topDenies(5, dbPath);
  expect(top[0].tool).toBe("Read");
  expect(top[0].count).toBe(2);
});
