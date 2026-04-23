import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { runBinary, isDenied, isAllowed, denyReason, contextText, SRC, PLUGIN_ROOT } from "./helpers";
import { rmSync, existsSync, readFileSync } from "fs";
import { join } from "path";
import { homedir } from "os";

const STATE_DIR = join(PLUGIN_ROOT, "state");
const SESSION_CACHE_DIR = join(homedir(), ".cache", "orca-env-plugin", "sessions");
const SESSION_ID = "e2e-fix-bug-session";

/**
 * E2E Session Simulation: "Fix bug in orca/sensors/base.py"
 *
 * Simulates a complete developer session through the hook binary.
 * Every hook event type, every guard, every routing decision.
 * Steps run sequentially — each depends on prior state.
 */

function cleanAllState() {
  rmSync(STATE_DIR, { recursive: true, force: true });
  rmSync(SESSION_CACHE_DIR, { recursive: true, force: true });
}

beforeAll(cleanAllState);
afterAll(cleanAllState);

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 1: SESSION INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 1: session initialization", () => {
  test("step 1 — SessionStart from ~/src → orca-unified + routing table", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    const ctx = contextText(r);

    expect(r.exitCode).toBe(0);
    expect(r.json).not.toBeNull();
    expect(r.json.hookSpecificOutput.hookEventName).toBe("SessionStart");

    // Must detect orca-unified project
    expect(ctx).toContain("orca-unified");
    expect(ctx).toContain("mcp__serena__activate_project");

    // Must include full routing table
    expect(ctx).toContain("TOOL ROUTING");
    expect(ctx).toContain("codebase-memory-mcp");
    expect(ctx).toContain("Source code WRITE");
    expect(ctx).toContain("Serena");
    expect(ctx).toContain("Docs/config/logs");
    
  });

  test("step 2 — PromptSubmit 'explore the codebase' → suggests codebase-explorer", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "explore the codebase to find the bug in sensors",
    });
    expect(r.exitCode).toBe(0);
    expect(r.exitCode).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 2: EXPLORATION — ALL NATIVE TOOLS BLOCKED ON SOURCE
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 2: exploration — native tools blocked", () => {
  test("step 3 — Read ~/src/orca/sensors/base.py → DENIED (use CBM)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/sensors/base.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("CBM");
    expect(denyReason(r)).toContain("search_code");
    expect(denyReason(r)).toContain("search_graph");
  });

  test("step 4 — Glob **/*.py under ~/src → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Glob",
      tool_input: { path: SRC, pattern: "**/*.py" },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("search_code");
  });

  test("step 5 — Grep type=py under ~/src → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: SRC, type: "py", pattern: "class AbstractSensor" },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("search_code");
  });

  test("step 6 — Bash: cat source file → DENIED (use CBM)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat ${SRC}/orca/sensors/base.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("search_code");
  });

  test("step 7 — Bash: sed on source file → DENIED (use Serena)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `sed -i 's/old/new/' ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 3: CORRECT TOOL USAGE — MCP/ALLOWED TOOLS PASS
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 3: correct tools pass through", () => {
  test("step 8 — MCP search_graph → ALLOWED (not a native tool)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__codebase-memory-mcp__search_graph",
      tool_input: { project: "orca", name_pattern: "AbstractSensor" },
    });
    expect(r.exitCode).toBe(0);
    expect(isDenied(r)).toBe(false);
    expect(r.stdout).toBe("");
  });

  test("step 9 — Read README.md → ALLOWED (non-code file)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/README.md` },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("step 10 — Bash: git log → ALLOWED + RTK rewrite", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "git log --oneline -5" },
    });
    expect(r.exitCode).toBe(0);
    expect(isDenied(r)).toBe(false);
    if (r.json?.hookSpecificOutput?.updatedInput?.command) {
      expect(r.json.hookSpecificOutput.updatedInput.command).toContain("rtk");
    }
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 4: EDITING WORKFLOW — refs guard + serena flow
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 4: editing workflow", () => {
  test("step 11 — PromptSubmit 'edit the function' → suggests serena-editor", async () => {
    const r = await runBinary("user-prompt-submit", {
      prompt: "edit the function to fix the bug in sensors",
    });
    expect(r.exitCode).toBe(0);
    expect(r.exitCode).toBe(0);
  });

  test("step 12 — Serena edit WITHOUT refs → WARNED (exit 1)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: {
        name_path: "AbstractSensor/process",
        relative_path: "orca/sensors/base.py",
        body: "def process(self, event):\n    return self.handle(event)",
      },
      session_id: SESSION_ID,
    });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain("find_referencing_symbols");
    expect(r.stderr).toContain("orca/sensors/base.py");
  });

  test("step 13 — PostToolUse: find_referencing_symbols → records state", async () => {
    const r = await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: {
        name_path: "AbstractSensor/process",
        relative_path: "orca/sensors/base.py",
      },
      session_id: SESSION_ID,
    });
    expect(r.exitCode).toBe(0);

    const stateFile = join(STATE_DIR, "refs-traced.json");
    expect(existsSync(stateFile)).toBe(true);

    const state = JSON.parse(readFileSync(stateFile, "utf-8"));
    expect(state.session_id).toBe(SESSION_ID);
    expect(state.traced["orca/sensors/base.py"]).toBeDefined();
  });

  test("step 14 — Serena edit WITH refs traced → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: {
        name_path: "AbstractSensor/process",
        relative_path: "orca/sensors/base.py",
        body: "def process(self, event):\n    return self.handle(event)",
      },
      session_id: SESSION_ID,
    });
    expect(r.exitCode).toBe(0);
    expect(isDenied(r)).toBe(false);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 5: SESSION END
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 5: session end", () => {
  test("step 15 — Stop with no transcript → clean exit", async () => {
    const r = await runBinary("stop", {
      transcript_path: "/nonexistent/path/transcript.jsonl",
      cwd: SRC,
    });
    expect(r.exitCode).toBe(0);
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 6: EDGE CASES — boundary conditions across hook types
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 6: cross-hook edge cases", () => {
  test("native Edit on source → DENIED with Serena message (not CBM)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Edit",
      tool_input: { file_path: `${SRC}/orca/sensors/base.py`, old_string: "old", new_string: "new" },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
    expect(denyReason(r)).not.toContain("codebase-memory-mcp");
  });

  test("native Write on source → DENIED with Serena message", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Write",
      tool_input: { file_path: `${SRC}/orca/new_module.py`, content: "# new" },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });

  test("Grep with glob=*.go under ~/src → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca-sensor`, glob: "*.go", pattern: "func main" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Bash: head with flags → still denied on source", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `head -n 50 ${SRC}/orca/sensors/base.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Bash: tail -f on source → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `tail -f ${SRC}/orca/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Bash: cat .json under ~/src → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat ${SRC}/orca/package.json` },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Bash: cat .sh under ~/src → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat ${SRC}/orca/scripts/deploy.sh` },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Read .py in /docs/ path → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/docs/api.py` },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Read .go in /vendor/ → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/vendor/lib/parser.go` },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Serena replace_content without refs → WARNED", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_content",
      tool_input: { relative_path: "orca/new_file.py", needle: "x", repl: "y", mode: "literal" },
      session_id: "edge-case-session",
    });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain("find_referencing_symbols");
  });

  test("Serena insert_after_symbol without refs → WARNED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__insert_after_symbol",
      tool_input: { name_path: "Foo", relative_path: "orca/utils.py", body: "def bar(): pass" },
      session_id: "edge-case-session",
    });
    expect(r.exitCode).toBe(1);
  });

  test("unknown tool → fail open", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "SomeNewTool",
      tool_input: { file: `${SRC}/orca/code.py` },
    });
    expect(r.exitCode).toBe(0);
    expect(isDenied(r)).toBe(false);
  });

  test("PromptSubmit with no match → empty output", async () => {
    const r = await runBinary("user-prompt-submit", { session_id: "isolated-no-match", prompt: "what time is it" });
    expect(r.stdout).toBe("");
  });

  test("SessionStart from /tmp → no project, still has routing", async () => {
    const r = await runBinary("session-start", { cwd: "/tmp" });
    const ctx = contextText(r);
    expect(ctx).not.toContain("SERENA WORKSPACE DETECTED");
    expect(ctx).toContain("TOOL ROUTING");
  });

  test("SessionStart from orca-sensor subdir → detects orca-sensor", async () => {
    const r = await runBinary("session-start", { cwd: `${SRC}/orca-sensor/cmd` });
    const ctx = contextText(r);
    expect(ctx).toContain("orca-sensor");
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// PHASE 7: DETERMINISM — same input always produces same output
// ═══════════════════════════════════════════════════════════════════════════

describe("phase 7: determinism", () => {
  test("same deny input produces identical output across 5 runs", async () => {
    const results: string[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Read",
        tool_input: { file_path: `${SRC}/orca/sensors/base.py` },
      });
      results.push(r.stdout);
    }
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toBe(results[0]);
    }
  });

  test("same allow input produces identical output across 5 runs", async () => {
    const results: string[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Read",
        tool_input: { file_path: `${SRC}/orca/README.md` },
      });
      results.push(r.stdout);
    }
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toBe(results[0]);
    }
  });

  test("session-start output is deterministic", async () => {
    const results: string[] = [];
    for (let i = 0; i < 3; i++) {
      const r = await runBinary("session-start", { cwd: SRC });
      results.push(r.stdout);
    }
    for (let i = 1; i < results.length; i++) {
      expect(results[i]).toBe(results[0]);
    }
  });
});
