import { describe, test, expect, afterEach } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { getTurn, incrementTurn, resetSession } from "../src/lib/session-state";

function tempRoot(): string {
  return mkdtempSync(join(tmpdir(), "session-test-"));
}

describe("session-state edge cases", () => {
  test("getTurn nonexistent session → 0", () => {
    expect(getTurn("nonexistent", tempRoot())).toBe(0);
  });

  test("incrementTurn starts at 1", () => {
    const root = tempRoot();
    expect(incrementTurn("new-session", root)).toBe(1);
  });

  test("incrementTurn is sequential", () => {
    const root = tempRoot();
    expect(incrementTurn("seq", root)).toBe(1);
    expect(incrementTurn("seq", root)).toBe(2);
    expect(incrementTurn("seq", root)).toBe(3);
    expect(getTurn("seq", root)).toBe(3);
  });

  test("corrupt JSON → getTurn returns 0", () => {
    const root = tempRoot();
    writeFileSync(join(root, "corrupt.json"), "NOT_JSON{{{");
    expect(getTurn("corrupt", root)).toBe(0);
  });

  test("missing turn field → getTurn returns 0", () => {
    const root = tempRoot();
    writeFileSync(join(root, "noturn.json"), '{"other": 42}');
    expect(getTurn("noturn", root)).toBe(0);
  });

  test("resetSession nonexistent → no crash", () => {
    const root = tempRoot();
    expect(() => resetSession("nope", root)).not.toThrow();
  });

  test("resetSession clears turn", () => {
    const root = tempRoot();
    incrementTurn("reset-me", root);
    incrementTurn("reset-me", root);
    expect(getTurn("reset-me", root)).toBe(2);
    resetSession("reset-me", root);
    expect(getTurn("reset-me", root)).toBe(0);
  });

  test("different sessions isolated", () => {
    const root = tempRoot();
    incrementTurn("a", root);
    incrementTurn("a", root);
    incrementTurn("b", root);
    expect(getTurn("a", root)).toBe(2);
    expect(getTurn("b", root)).toBe(1);
  });
});
