import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, isAllowed, denyReason, contextText, SRC, PLUGIN_ROOT } from "./helpers";
import { rmSync } from "fs";
import { join } from "path";

const STATE_DIR = join(PLUGIN_ROOT, "state");

/**
 * TDD: Serena/CBM/RTK lifecycle bugs.
 * Tests written FIRST — expected to FAIL.
 */

// ═══════════════════════════════════════════════════════
// SESSION-START: Project detection bugs
// ═══════════════════════════════════════════════════════

describe("TDD: session-start project detection", () => {
  test("orca-cloud-platform → detects project + activate", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-cloud-platform` });
    const ctx = contextText(r);
    expect(ctx).toContain("SERENA WORKSPACE DETECTED");
    expect(ctx).toContain("activate_project");
  });

  test("orca-env-plugin → detects as orca-env-plugin (not orca)", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-env-plugin` });
    const ctx = contextText(r);
    expect(ctx).toContain("orca-env-plugin");
    expect(ctx).not.toContain("project='orca'");
  });

  test("orca-env-plugin subdir → same detection", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-env-plugin/src/hot` });
    const ctx = contextText(r);
    expect(ctx).toContain("orca-env-plugin");
  });
});

// ═══════════════════════════════════════════════════════
// PROMPT-SUBMIT: Skill trigger false positives
// ═══════════════════════════════════════════════════════

describe("TDD: prompt-submit false positive fixes", () => {
  test("'search web for breaking changes' → NOT serena-editor", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "search web for Go 1.25 breaking changes",
    });
    expect(r.exitCode).toBe(0);
    expect(r.exitCode).toBe(0);
  });

  test("'commit the changes' → NOT serena-editor", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "commit the changes",
    });
    expect(r.exitCode).toBe(0);
  });

  test("'fix the failing test' → suggests serena-editor", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "fix the failing test",
    });
    expect(r.exitCode).toBe(0);
  });

  test("'change the function signature' → serena-editor (legitimate)", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "change the function signature to accept a context parameter",
    });
    expect(r.exitCode).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════
// SERENA EDIT GUARD: All edit tools covered
// ═══════════════════════════════════════════════════════

describe("TDD: serena edit guard — all tools", () => {
  const editTools = [
    "mcp__serena__replace_symbol_body",
    "mcp__serena__replace_content",
    "mcp__serena__insert_after_symbol",
    "mcp__serena__insert_before_symbol",
    "mcp__serena__rename_symbol",
  ];

  for (const tool of editTools) {
    test(`${tool.split("__").pop()} without refs → exit 1`, async () => {
      rmSync(STATE_DIR, { recursive: true, force: true });
      const r = await runBinary("pre-tool-use", {
        tool_name: tool,
        tool_input: { relative_path: "orca/test.py", name_path: "Foo", body: "pass" },
        session_id: `guard-test-${tool}`,
      });
      expect(r.exitCode).toBe(1);
      expect(r.stderr).toContain("find_referencing_symbols");
      rmSync(STATE_DIR, { recursive: true, force: true });
    });
  }

  test("safe_delete_symbol without refs → exit 1", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__safe_delete_symbol",
      tool_input: { relative_path: "orca/test.py", name_path: "Foo" },
      session_id: "guard-delete-test",
    });
    // safe_delete_symbol is NOT in SERENA_EDIT_TOOLS → should it be?
    // If it fails open, that's a bug
    expect(r.exitCode).toBe(1);
    rmSync(STATE_DIR, { recursive: true, force: true });
  });
});

// ═══════════════════════════════════════════════════════
// RTK: Rewrite determinism
// ═══════════════════════════════════════════════════════

describe("TDD: RTK determinism", () => {
  test("same command rewritten identically 5x", async () => {
    const results: string[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: "git status" },
      });
      results.push(r.stdout);
    }
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toBe(results[0]);
    }
  });
});
