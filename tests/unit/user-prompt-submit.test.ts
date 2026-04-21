import { expect, test, beforeEach } from "bun:test";
import { rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { handleUserPromptSubmit } from "../../src/hot/user-prompt-submit";

const root = join(tmpdir(), "ups-test-" + Date.now());
beforeEach(() => { try { rmSync(root, { recursive: true, force: true }); } catch {} });

test("no re-injection on turn 1", () => {
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toBe("");
});

test("re-injects on turn 10", () => {
  for (let i = 1; i < 10; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toContain("CAVEMAN MODE");
  expect(out.appendContext).toContain("codebase-memory-mcp");
});

test("re-injects again on turn 20", () => {
  for (let i = 1; i < 20; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toContain("CAVEMAN MODE");
});

test("no re-injection on turn 11", () => {
  for (let i = 1; i < 11; i++) handleUserPromptSubmit({ session_id: "s1" }, root);
  const out = handleUserPromptSubmit({ session_id: "s1" }, root);
  expect(out.appendContext).toBe("");
});
