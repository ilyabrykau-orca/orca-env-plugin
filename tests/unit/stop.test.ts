import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { recordDecision, resetAuditCache } from "../../src/lib/audit";
import { auditSummary } from "../../src/cold/stop";

const dbPath = join(tmpdir(), `stop-audit-${Date.now()}.sqlite`);

beforeEach(() => {
  resetAuditCache();
  try { rmSync(dbPath, { force: true }); } catch {}
});

test("auditSummary returns block rate + top denies", () => {
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.go", allow: false, reason: "code" }, dbPath);
  recordDecision({ sessionId: "s1", tool: "Read", target: "/x.md", allow: true, reason: "doc" }, dbPath);
  const s = auditSummary(dbPath);
  expect(s.blockRate).toBeCloseTo(2 / 3, 2);
  expect(s.topDenies.length).toBeGreaterThan(0);
  expect(s.topDenies[0].tool).toBe("Read");
});

test("auditSummary on empty db returns zero rate", () => {
  const s = auditSummary(dbPath);
  expect(s.blockRate).toBe(0);
  expect(s.topDenies.length).toBe(0);
});
