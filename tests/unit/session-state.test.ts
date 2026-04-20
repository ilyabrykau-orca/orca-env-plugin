import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { incrementTurn, getTurn, resetSession } from "../../src/lib/session-state";

const root = join(tmpdir(), "orca-env-plugin-test-" + Date.now());

beforeEach(() => {
  try { rmSync(root, { recursive: true, force: true }); } catch {}
});

test("new session starts at turn 1", () => {
  const n = incrementTurn("sess-A", root);
  expect(n).toBe(1);
});

test("increments persist across calls", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  const n = incrementTurn("sess-A", root);
  expect(n).toBe(3);
});

test("different sessions isolated", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  const b = incrementTurn("sess-B", root);
  expect(b).toBe(1);
});

test("getTurn returns current without incrementing", () => {
  incrementTurn("sess-A", root);
  incrementTurn("sess-A", root);
  expect(getTurn("sess-A", root)).toBe(2);
  expect(getTurn("sess-A", root)).toBe(2);
});

test("resetSession clears counter", () => {
  incrementTurn("sess-A", root);
  resetSession("sess-A", root);
  expect(getTurn("sess-A", root)).toBe(0);
});
