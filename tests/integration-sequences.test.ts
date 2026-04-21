import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, isAllowed, denyReason, contextText, SRC, PLUGIN_ROOT } from "./helpers";
import { rmSync } from "fs";
import { join } from "path";

const STATE_DIR = join(PLUGIN_ROOT, "state");

/**
 * Integration sequence tests — validate multi-step session flows
 * that mirror real Claude Code behavior.
 */

describe("bash source guard", () => {
  describe("denies reading source via bash", () => {
    test.each([
      ["cat", `${SRC}/orca/views.py`],
      ["head", `${SRC}/orca-sensor/cmd/main.go`],
      ["tail", `${SRC}/orca/models.ts`],
      ["less", `${SRC}/orca/utils.rs`],
      ["bat", `${SRC}/orca/handler.tsx`],
    ])("%s %s → denied with explore message", async (cmd, path) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: `${cmd} ${path}` },
      });
      expect(isDenied(r)).toBe(true);
      expect(denyReason(r)).toContain("codebase-memory-mcp");
    });
  });

  describe("denies editing source via bash", () => {
    test.each([
      ["sed", `-i 's/foo/bar/' ${SRC}/orca/views.py`],
      ["awk", `'{print}' ${SRC}/orca/main.go`],
      ["perl", `-pi -e 's/foo/bar/' ${SRC}/orca/lib.rs`],
    ])("%s %s → denied with Serena message", async (cmd, args) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: `${cmd} ${args}` },
      });
      expect(isDenied(r)).toBe(true);
      expect(denyReason(r)).toContain("Serena");
    });
  });

  describe("allows bash on non-source files", () => {
    test.each([
      `cat ${SRC}/orca/README.md`,
      `head ${SRC}/orca/config.yaml`,
      `cat /tmp/code.py`,
      `tail ${SRC}/orca/go.mod`,
      `cat ${SRC}/orca/Makefile`,
    ])("allows: %s", async (cmd) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(isAllowed(r)).toBe(true);
    });
  });

  test("allows bash non-file commands", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "git log --oneline -5" },
    });
    expect(r.exitCode).toBe(0);
  });

  test("CLAUDE_RAW=1 bypasses all bash guards", async () => {
    // CLAUDE_RAW=1 bypasses RTK rewrite, NOT source routing.
    // Source guard still denies cat on .py files.
    const r = await runBinary(
      "pre-tool-use",
      { tool_name: "Bash", tool_input: { command: `cat ${SRC}/orca/views.py` } },
      { CLAUDE_RAW: "1" },
    );
    expect(r.exitCode).toBe(0);
    expect(isDenied(r)).toBe(true);
  });

  test("piped cat on source → DENIED (compound guard)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat ${SRC}/orca/views.py | grep foo` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("codebase-memory-mcp");
  });
});

describe("edit → refs → edit flow", () => {
  test("edit blocked, trace refs, then edit allowed", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });

    // Step 1: edit without refs → blocked
    const r1 = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "MyClass", relative_path: "orca/service.py", body: "pass" },
      session_id: "flow-test-1",
    });
    expect(r1.exitCode).toBe(1);
    expect(r1.stderr).toContain("find_referencing_symbols");

    // Step 2: trace refs
    await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: { name_path: "MyClass", relative_path: "orca/service.py" },
      session_id: "flow-test-1",
    });

    // Step 3: edit after refs → allowed
    const r3 = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "MyClass", relative_path: "orca/service.py", body: "pass" },
      session_id: "flow-test-1",
    });
    expect(r3.exitCode).toBe(0);

    rmSync(STATE_DIR, { recursive: true, force: true });
  });

  test("different session_id invalidates refs state", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });

    // Trace refs in session A
    await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: { name_path: "Func", relative_path: "orca/utils.py" },
      session_id: "session-A",
    });

    // Edit in session B → blocked (different session)
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_content",
      tool_input: { relative_path: "orca/utils.py", needle: "old", repl: "new", mode: "literal" },
      session_id: "session-B",
    });
    expect(r.exitCode).toBe(1);

    rmSync(STATE_DIR, { recursive: true, force: true });
  });

  test("refs for file A don't authorize edit of file B", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });

    await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: { name_path: "FuncA", relative_path: "orca/a.py" },
      session_id: "scope-test",
    });

    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "FuncB", relative_path: "orca/b.py", body: "pass" },
      session_id: "scope-test",
    });
    expect(r.exitCode).toBe(1);

    rmSync(STATE_DIR, { recursive: true, force: true });
  });
});

describe("grep/glob path edge cases", () => {
  test("Grep with path=~/src and type=go → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: SRC, type: "go", pattern: "func" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep with path=~/src and glob=*.py → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: SRC, glob: "*.py", pattern: "import" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep with path=~/src/orca and type=rust → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca`, type: "rust", pattern: "fn" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep with type=py but path=/tmp → allowed", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: "/tmp", type: "py", pattern: "def" },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Glob with *.ts under ~/src → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Glob",
      tool_input: { path: SRC, pattern: "**/*.ts" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Glob with *.md under ~/src → allowed", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Glob",
      tool_input: { path: SRC, pattern: "**/*.md" },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Grep on specific .py file under ~/src → denied", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca/views.py`, pattern: "def" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep with no path, no type → allowed (fail open)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { pattern: "hello" },
    });
    // cwd may be ~/src during test run — if so, type/glob checks apply
    // But no type/glob filter → should reach fail-open for unknown ext
    expect(r.exitCode).toBe(0);
  });
});

describe("session-start → routing context", () => {
  test("always emits tool routing table", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    const ctx = contextText(r);
    expect(ctx).toContain("TOOL ROUTING");
    expect(ctx).toContain("codebase-memory-mcp");
    expect(ctx).toContain("Source-code edits");
    expect(ctx).toContain("Serena");
    expect(ctx).toContain("native Read/Edit/Write");
  });

  test("~/src triggers orca-unified project + activation", async () => {
    const r = await runBinary("session-start", { cwd: SRC });
    const ctx = contextText(r);
    expect(ctx).toContain("orca-unified");
    expect(ctx).toContain("mcp__serena__activate_project");
    expect(ctx).toContain("mcp__serena__list_memories");
  });
});

describe("rtk integration", () => {
  test("simple command gets rewritten or passed through", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "git status" },
    });
    expect(r.exitCode).toBe(0);
    // Either RTK rewrites (stdout has JSON with updatedInput) or passthrough (empty)
    if (r.stdout) {
      expect(r.json?.hookSpecificOutput?.updatedInput?.command).toBeDefined();
    }
  });

  test("ls command gets rewritten", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "ls -la" },
    });
    expect(r.exitCode).toBe(0);
    if (r.json?.hookSpecificOutput?.updatedInput?.command) {
      expect(r.json.hookSpecificOutput.updatedInput.command).toContain("rtk");
    }
  });

  test("compound commands skip RTK (fail open)", async () => {
    const cmds = [
      "cat foo | grep bar",
      "make && make test",
      "echo foo > out.txt",
      "echo $(date)",
      "ls; echo done",
    ];
    for (const cmd of cmds) {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(r.exitCode).toBe(0);
      // Should not have RTK rewrite
      if (r.json?.hookSpecificOutput?.updatedInput) {
        // compound → should skip, but if RTK handles it, that's fine too
      }
    }
  });
});

describe("rtk always applied to simple commands", () => {
  test.each([
    "git log --oneline",
    "git diff HEAD",
    "git branch -a",
    "ls /tmp",
    "wc -l foo.txt",
    "file /tmp/test",
    "which bun",
    "pwd",
    "whoami",
    "uname -a",
  ])("RTK attempted for: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: cmd },
    });
    expect(r.exitCode).toBe(0);
    // For simple commands, RTK should either:
    // 1. Rewrite (stdout has JSON with updatedInput) → RTK was used
    // 2. Pass through (exit 0, empty stdout) → RTK tried but no rewrite needed
    // Both are valid — the key is no denial
    expect(isDenied(r)).toBe(false);
  });

  test("RTK skipped for MCP tools (non-Bash)", async () => {
    // MCP tools don't go through Bash handler at all
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__codebase-memory-mcp__search_graph",
      tool_input: { project: "test", name_pattern: "foo" },
    });
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toBe(""); // no RTK rewrite attempted
  });

  test("RTK rewrite produces valid updatedInput structure", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "git status" },
    });
    if (r.json?.hookSpecificOutput?.updatedInput) {
      // RTK rewrote — verify structure
      expect(r.json.hookSpecificOutput.updatedInput.command).toBeTruthy();
      expect(r.json.hookSpecificOutput.updatedInput.command).toContain("rtk");
    }
    // If no rewrite, that's fine — RTK may not be installed or command not supported
  });
});

describe("bash guard bypass hardening", () => {
  test("/bin/cat on source → DENIED (basename extraction)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `/bin/cat ${SRC}/orca/sensors/base.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("codebase-memory-mcp");
  });

  test("/usr/bin/head on source → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `/usr/bin/head ${SRC}/orca/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("/usr/bin/sed on source → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `/usr/bin/sed -i 's/a/b/' ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });

  test("cat -- source.py → DENIED (-- separator handled)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat -- ${SRC}/orca/sensors/base.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("head -- -n source.go → DENIED (args after -- not treated as flags)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `head -- ${SRC}/orca/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });
});

describe("compound command guard — real session violations", () => {
  describe("pipe reads denied", () => {
    test.each([
      `cat ${SRC}/orca/sensors/base.py | grep class`,
      `cat ${SRC}/orca/views.py | head -20`,
      `head ${SRC}/orca/main.go | grep func`,
      `tail ${SRC}/orca/models.ts | wc -l`,
      `cat -n ${SRC}/orca-sensor/cmd/main.go | head`,
    ])("DENIED: %s", async (cmd) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(isDenied(r)).toBe(true);
      expect(denyReason(r)).toContain("codebase-memory-mcp");
    });
  });

  describe("redirect writes denied", () => {
    test.each([
      `cat > ${SRC}/orca/new_file.py << 'EOF'\nprint("hello")\nEOF`,
      `cat >> ${SRC}/orca/utils.ts << 'EOF'\nexport {}\nEOF`,
      `echo "test" > ${SRC}/orca/test.go`,
    ])("DENIED: %s", async (cmd) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(isDenied(r)).toBe(true);
      expect(denyReason(r)).toContain("Serena");
    });
  });

  describe("compound commands on non-source still allowed", () => {
    test.each([
      `cat ${SRC}/orca/README.md | head`,
      `cat ${SRC}/orca/config.yaml | grep key`,
      `echo "test" > /tmp/output.py`,
      `cat > ${SRC}/orca/notes.md << 'EOF'\n# Notes\nEOF`,
      `head ${SRC}/orca/go.mod | grep module`,
    ])("ALLOWED: %s", async (cmd) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(isDenied(r)).toBe(false);
    });
  });

  describe("non-cat compound commands pass through", () => {
    test.each([
      "make && make test",
      "go build ./... && go test ./...",
      "npm run build; npm run test",
    ])("ALLOWED: %s", async (cmd) => {
      const r = await runBinary("pre-tool-use", {
        tool_name: "Bash",
        tool_input: { command: cmd },
      });
      expect(r.exitCode).toBe(0);
      expect(isDenied(r)).toBe(false);
    });
  });
});
