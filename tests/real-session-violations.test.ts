import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, isAllowed, denyReason, SRC, PLUGIN_ROOT } from "./helpers";
import { rmSync } from "fs";
import { join } from "path";

const STATE_DIR = join(PLUGIN_ROOT, "state");

/**
 * Real session violations — every test case extracted from actual Claude Code
 * session transcripts. These are ACTUAL commands that bypassed enforcement.
 * Each must be deterministically DENIED.
 */

describe("real: native Read on source (.ts/.py/.go/.rs/.c)", () => {
  test.each([
    `${SRC}/orca-env-plugin/src/hot/pre-tool-use.ts`,
    `${SRC}/orca-env-plugin/src/index.ts`,
    `${SRC}/orca-env-plugin/src/lib/constants.ts`,
    `${SRC}/orca-env-plugin/src/cold/session-start.ts`,
    `${SRC}/orca-env-plugin/tests/pre-tool-use.test.ts`,
    `${SRC}/orca-env-plugin/tests/helpers.ts`,
    `${SRC}/orca-runtime-sensor/pkg/http/classification_test.go`,
    `${SRC}/orca-runtime-sensor/eventsource/bpfprobes/ssl_probe.c`,
    `${SRC}/orca-runtime-sensor/eventsource/bpfprobes/ssl_conn_info.h`,
    `${SRC}/rtk/src/discover/mod.rs`,
    `${SRC}/orca/base_api/views.py`,
  ])("Read %s → DENIED", async (path) => {
    const r = await runBinary("pre-tool-use", { tool_name: "Read", tool_input: { file_path: path } });
    expect(isDenied(r)).toBe(true);
  });
});

describe("real: native Edit/Write on source", () => {
  test.each([
    ["Edit", `${SRC}/orca-env-plugin/src/lib/constants.ts`],
    ["Edit", `${SRC}/orca-runtime-sensor/pkg/http/classification_test.go`],
    ["Write", `${SRC}/orca-env-plugin/src/lib/headroom.ts`],
    ["Write", `${SRC}/orca-env-plugin/tests/headroom.test.ts`],
  ])("%s %s → DENIED (use Serena)", async (tool, path) => {
    const r = await runBinary("pre-tool-use", { tool_name: tool, tool_input: { file_path: path } });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });
});

describe("real: Bash cat/head/tail/sed on source", () => {
  test.each([
    `cat ${SRC}/orca-env-plugin/src/hot/pre-tool-use.ts`,
    `cat ${SRC}/orca-env-plugin/src/index.ts`,
    `cat ${SRC}/orca-env-plugin/src/cold/session-start.ts`,
    `cat ${SRC}/orca-env-plugin/tests/pre-tool-use.test.ts`,
    `cat ${SRC}/orca-runtime-sensor/pkg/events/ssl_event.go`,
    `head -15 ${SRC}/orca-sensor/services/sensor-management/server/server.go`,
    `tail -80 ${SRC}/orca-runtime-sensor/eventsource/bpfstream/ssl_test.go`,
    `sed -n '1,15p' ${SRC}/orca-runtime-sensor/eventsource/bpfstream/ssl_test.go`,
    `sed -n '25,40p' ${SRC}/orca-runtime-sensor/eventsource/bpfstream/ssl_test.go`,
    `/bin/cat ${SRC}/orca/views.py`,
  ])("DENIED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: cmd } });
    expect(isDenied(r)).toBe(true);
  });
});

describe("real: Bash compound (pipe/heredoc/chain)", () => {
  test.each([
    `cat ${SRC}/orca-env-plugin/src/hot/pre-tool-use.ts | head -5`,
    `cat ${SRC}/orca-env-plugin/src/hot/pre-tool-use.ts | grep -n function`,
    `cat ${SRC}/orca-env-plugin/src/hot/pre-tool-use.ts | sed -n '1,10p'`,
    `grep -n "^func " ${SRC}/orca-sensor/cmd/main.go`,
    `grep -nE "^static int" ${SRC}/orca-runtime-sensor/eventsource/bpfprobes/ssl_probe.c`,
    `wc -l ${SRC}/rtk/src/discover/mod.rs`,
    `cat -n ${SRC}/orca-env-plugin/src/cold/session-start.ts | head`,
  ])("DENIED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: cmd } });
    expect(isDenied(r)).toBe(true);
  });
});

describe("real: Bash redirect writes to source", () => {
  test.each([
    `cat > ${SRC}/orca-env-plugin/tests/session-start.test.ts << 'EOF'\nimport { test } from "bun:test";\nEOF`,
    `cat > ${SRC}/orca-env-plugin/src/cold/session-start.ts << 'TYPESCRIPT'\nexport function handleSessionStart() {}\nTYPESCRIPT`,
    `cat >> ${SRC}/orca-env-plugin/tests/prompt-submit.test.ts << 'EOF'\ntest("extra", () => {});\nEOF`,
    `echo "test" > ${SRC}/orca/new_module.py`,
  ])("DENIED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: cmd } });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });
});

describe("real: Bash chain commands (&&)", () => {
  test.each([
    `cd ${SRC}/orca && cat views.py`,
    `cd ${SRC}/orca-sensor && grep -n "func main" cmd/main.go`,
  ])("DENIED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", { tool_name: "Bash", tool_input: { command: cmd } });
    expect(isDenied(r)).toBe(true);
  });
});

describe("real: Glob/Grep on source patterns", () => {
  test.each([
    { tool: "Glob", input: { path: SRC, pattern: "**/*.ts" } },
    { tool: "Glob", input: { path: `${SRC}/orca-env-plugin`, pattern: "**/*.ts" } },
    { tool: "Grep", input: { path: SRC, type: "go", pattern: "func" } },
    { tool: "Grep", input: { path: SRC, type: "py", pattern: "class" } },
    { tool: "Grep", input: { path: `${SRC}/orca-sensor`, glob: "*.go", pattern: "func main" } },
  ])("DENIED: $tool $input", async ({ tool, input }) => {
    const r = await runBinary("pre-tool-use", { tool_name: tool, tool_input: input });
    expect(isDenied(r)).toBe(true);
  });
});

describe("real: Serena edit guard", () => {
  test("replace_symbol_body without refs → exit 1", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_symbol_body",
      tool_input: { name_path: "handleSessionStart", relative_path: "orca/sensors/base.py", body: "pass" },
      session_id: "real-session-test",
    });
    expect(r.exitCode).toBe(1);
    expect(r.stderr).toContain("find_referencing_symbols");
    rmSync(STATE_DIR, { recursive: true, force: true });
  });

  test("replace_content without refs → exit 1", async () => {
    rmSync(STATE_DIR, { recursive: true, force: true });
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__serena__replace_content",
      tool_input: { relative_path: "orca/utils.py", needle: "old", repl: "new", mode: "literal" },
      session_id: "real-session-test2",
    });
    expect(r.exitCode).toBe(1);
    rmSync(STATE_DIR, { recursive: true, force: true });
  });
});

describe("real: must-allow (non-source / non-src)", () => {
  test.each([
    { tool: "Read", input: { file_path: `${SRC}/orca/README.md` } },
    { tool: "Read", input: { file_path: `${SRC}/orca-env-plugin/package.json` } },
    { tool: "Read", input: { file_path: `${SRC}/orca-env-plugin/hooks/hooks.json` } },
    { tool: "Read", input: { file_path: `${SRC}/orca/config.yaml` } },
    { tool: "Read", input: { file_path: `${SRC}/orca-env-plugin/skills/orca-setup/SKILL.md` } },
    { tool: "Read", input: { file_path: `${process.env.HOME}/.claude/settings.json` } },
    { tool: "Read", input: { file_path: "/tmp/test.py" } },
    { tool: "Bash", input: { command: "git log --oneline -5" } },
    { tool: "Bash", input: { command: "bun test" } },
    { tool: "Bash", input: { command: `ls ${SRC}/orca-env-plugin/` } },
  ])("ALLOWED: $tool $input", async ({ tool, input }) => {
    const r = await runBinary("pre-tool-use", { tool_name: tool, tool_input: input });
    expect(isDenied(r)).toBe(false);
  });

  test("MCP tools always pass through", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "mcp__codebase-memory-mcp__search_graph",
      tool_input: { project: "orca", name_pattern: "SensorBase" },
    });
    expect(r.exitCode).toBe(0);
    expect(r.stdout).toBe("");
  });
});
