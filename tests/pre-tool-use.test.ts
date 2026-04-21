import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, isAllowed, denyReason, SRC, PLUGIN_ROOT } from "./helpers";

describe("native-tool-guard", () => {
  describe("denies source code under ~/src", () => {
    test.each([
      ["Read", "file_path", `${SRC}/orca/base_api/views.py`],
      ["Read", "file_path", `${SRC}/orca-sensor/cmd/main.go`],
      ["Edit", "file_path", `${SRC}/orca/models.ts`],
      ["Write", "file_path", `${SRC}/orca/utils.rs`],
      ["Grep", "path", `${SRC}/orca/base_api/views.py`],
    ])("%s on %s=%s is denied", async (tool, param, path) => {
      const r = await runBinary("pre-tool-use", { tool_name: tool, tool_input: { [param]: path } });
      expect(isDenied(r)).toBe(true);
    });

    test("Read deny mentions codebase-memory-mcp", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: `${SRC}/orca/views.py` } });
      expect(denyReason(r)).toContain("codebase-memory-mcp");
    });

    test("Edit deny mentions Serena", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Edit", tool_input: { file_path: `${SRC}/orca/views.py` } });
      expect(denyReason(r)).toContain("Serena");
    });

    test("Grep with type=go under ~/src denied", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Grep", tool_input: { path: SRC, type: "go", pattern: "func" } });
      expect(isDenied(r)).toBe(true);
    });

    test("Glob with *.py pattern under ~/src denied", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Glob", tool_input: { path: SRC, pattern: "**/*.py" } });
      expect(isDenied(r)).toBe(true);
    });
  });

  describe("allows non-code files", () => {
    test.each([
      ["Read", { file_path: `${SRC}/orca/README.md` }],
      ["Read", { file_path: `${SRC}/orca/config.yaml` }],
      ["Edit", { file_path: `${SRC}/orca/settings.json` }],
      ["Read", { file_path: `${SRC}/orca/Makefile` }],
      ["Read", { file_path: `${SRC}/orca/Dockerfile` }],
      ["Read", { file_path: `${SRC}/orca/deploy.sh` }],
      ["Read", { file_path: `${SRC}/orca/go.mod` }],
    ])("%s on %j is allowed", async (tool, input) => {
      const r = await runBinary("pre-tool-use", { tool_name: tool, tool_input: input });
      expect(isAllowed(r)).toBe(true);
    });
  });

  describe("allows outside ~/src", () => {
    test("Read /tmp/foo.py allowed", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: "/tmp/foo.py" } });
      expect(isAllowed(r)).toBe(true);
    });
  });

  describe("allows ~/.claude/", () => {
    test("Read ~/.claude/settings.json allowed", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: `${process.env.HOME}/.claude/settings.json` } });
      expect(isAllowed(r)).toBe(true);
    });
  });

  describe("fails open", () => {
    test("no file_path → allowed", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: {} });
      expect(isAllowed(r)).toBe(true);
    });

    test("unknown extension → allowed", async () => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: `${SRC}/orca/data.xyz` } });
      expect(isAllowed(r)).toBe(true);
    });

    test("bad JSON input → exit 0", async () => {
      const proc = Bun.spawn([`${PLUGIN_ROOT}/dist/orca-env-plugin`, "pre-tool-use"], {
        stdin: new Blob(["not-json"]),
        stdout: "pipe",
        env: { ...process.env, CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT },
      });
      expect(await proc.exited).toBe(0);
    });
  });

  describe("allowed path components", () => {
    test.each([
      `${SRC}/orca/docs/api.py`,
      `${SRC}/orca/vendor/lib.go`,
      `${SRC}/orca/testdata/fixture.py`,
      `${SRC}/orca/.github/workflows/ci.py`,
      `${SRC}/orca/scripts/deploy.py`,
    ])("allows %s (path component exemption)", async (path) => {
      const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: path } });
      expect(isAllowed(r)).toBe(true);
    });
  });
});

describe("serena-edit-guard", () => {
  test("warns without refs traced", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "Foo", relative_path: "src/bar.py", body: "pass" },
      session_id: "test-no-refs",
    });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain("find_referencing_symbols");
  });

  test("allows after refs traced", async () => {
    // First trace refs
    await runBinary("post-tool-use", {
      tool_name: "mcp__serena__find_referencing_symbols",
      tool_input: { name_path: "Foo", relative_path: "src/bar.py" },
      session_id: "test-refs-ok",
    });
    // Then edit should be allowed
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "Foo", relative_path: "src/bar.py", body: "pass" },
      session_id: "test-refs-ok",
    });
    expect(r.exitCode).toBe(0);
  });
});

describe("rtk-rewrite", () => {
  test("simple command may be rewritten", async () => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: "git status" } });
    // Either rewritten (stdout has JSON) or passed through (empty stdout)
    expect(r.exitCode).toBe(0);
  });

  test("pipes skip RTK", async () => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: "cat foo | grep bar" } });
    expect(r.stdout).toBe("");
  });

  test("redirects skip RTK", async () => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: "echo foo > out.txt" } });
    expect(r.stdout).toBe("");
  });

  test("chained commands skip RTK", async () => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: "make && make test" } });
    expect(r.stdout).toBe("");
  });
});
