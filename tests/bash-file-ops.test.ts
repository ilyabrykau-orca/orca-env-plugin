import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, denyReason, SRC } from "./helpers";

/**
 * TDD: Tests written FIRST, expected to FAIL.
 * Each test represents a real bypass vector found by probing the binary.
 * After all fail, we fix the code until they pass.
 */

describe("TDD: bash indirect source access bypasses", () => {
  test("cp source to /tmp → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cp ${SRC}/orca/views.py /tmp/` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("mv source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `mv ${SRC}/orca/old.py ${SRC}/orca/new.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("tee to source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `echo test | tee ${SRC}/orca/new.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });

  test("python3 -c reading source → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `python3 -c "print(open('${SRC}/orca/views.py').read())"` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("bun -e writing source → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `bun -e "require('fs').writeFileSync('${SRC}/orca/test.py', 'pass')"` },
    });
    expect(isDenied(r)).toBe(true);
  });
});

describe("TDD: bash file operation commands", () => {
  test("rm source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `rm ${SRC}/orca/old_module.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("chmod source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `chmod +x ${SRC}/orca/script.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("cp non-source still allowed", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cp ${SRC}/orca/README.md /tmp/` },
    });
    expect(isDenied(r)).toBe(false);
  });

  test("tee to non-source still allowed", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `echo test | tee ${SRC}/orca/notes.md` },
    });
    expect(isDenied(r)).toBe(false);
  });

  test("mv non-source still allowed", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `mv ${SRC}/orca/old.md ${SRC}/orca/new.md` },
    });
    expect(isDenied(r)).toBe(false);
  });
});
import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, denyReason, SRC } from "./helpers";

/**
 * TDD Round 2: Tests from real session transcript analysis.
 * These represent actual bypasses that occurred in production sessions.
 */

describe("TDD round 2: real session bypasses", () => {
  test("wc -l on source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `wc -l ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("wc on multiple source files → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `wc -l ${SRC}/orca/views.py ${SRC}/orca/models.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("cd dir && cat source → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cd ${SRC}/orca && cat views.py` },
    });
    // This has && which is shell char. The cat targets a relative path
    // after cd to ~/src/orca. Hard to fully resolve, but the embedded
    // path scan should catch views.py if we resolve relative to cd target.
    // For now, test that compound check at least catches &&-chained commands
    // where the second segment targets source.
    expect(isDenied(r)).toBe(true);
  });

  test("grep -n on source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `grep -n "func main" ${SRC}/orca-sensor/cmd/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("grep -E on source file → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `grep -E "^func " ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("wc -l on .md → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `wc -l ${SRC}/orca/README.md` },
    });
    expect(isDenied(r)).toBe(false);
  });

  test("grep on .yaml → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `grep "key:" ${SRC}/orca/config.yaml` },
    });
    expect(isDenied(r)).toBe(false);
  });
});
import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, denyReason, isAllowed, SRC } from "./helpers";

/**
 * TDD Round 3: Bugs found by systematic probing.
 * Tests written FIRST — expected to FAIL.
 */

describe("TDD3: env prefix before file commands", () => {
  test("FOO=bar cat source.py → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `FOO=bar cat ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("LANG=C head source.go → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `LANG=C head ${SRC}/orca-sensor/cmd/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("ENV=1 sed source.py → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `ENV=1 sed -i 's/a/b/' ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });

  test("FOO=bar BAZ=1 cat source.py → DENIED (multiple env)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `FOO=bar BAZ=1 cat ${SRC}/orca/views.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("FOO=bar ls (non-file cmd) → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: "FOO=bar ls /tmp" },
    });
    expect(isDenied(r)).toBe(false);
  });
});

describe("TDD3: Grep on src directory without type filter", () => {
  test("Grep path=~/src/orca pattern=X (no type) → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca`, pattern: "import os" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep path=~/src/orca-sensor pattern=X (no type) → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca-sensor`, pattern: "func main" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Grep path=~/src/orca/docs pattern=X → ALLOWED (exempt path)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: `${SRC}/orca/docs`, pattern: "API" },
    });
    expect(isAllowed(r)).toBe(true);
  });

  test("Grep path=/tmp pattern=X → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Grep",
      tool_input: { path: "/tmp", pattern: "test" },
    });
    expect(isAllowed(r)).toBe(true);
  });
});

describe("TDD3: Glob multi-ext patterns", () => {
  test("Glob **/*.{go,py} under ~/src → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Glob",
      tool_input: { path: SRC, pattern: "**/*.{go,py}" },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Glob **/*.{md,json} under ~/src → ALLOWED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Glob",
      tool_input: { path: SRC, pattern: "**/*.{md,json}" },
    });
    expect(isAllowed(r)).toBe(true);
  });
});
import { describe, test, expect } from "bun:test";
import { runBinary, isDenied, denyReason, SRC } from "./helpers";

/**
 * TDD: Path traversal bypass via ../
 * CRITICAL: ~/src/docs/../views.py contains "/docs/" → passes ALLOWED_PATHS.
 * All these MUST be denied after fix.
 */

describe("TDD: path traversal bypass", () => {
  test("Read ~/src/orca/docs/../views.py → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/docs/../views.py` },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("codebase-memory-mcp");
  });

  test("Edit ~/src/orca/docs/../core.py → DENIED (Serena)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Edit",
      tool_input: { file_path: `${SRC}/orca/docs/../core.py`, old_string: "a", new_string: "b" },
    });
    expect(isDenied(r)).toBe(true);
    expect(denyReason(r)).toContain("Serena");
  });

  test("Read ~/src/orca/vendor/../secret.py → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/vendor/../secret.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Read ~/src/orca/testdata/../../sensor/main.go → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/testdata/../../orca-sensor/main.go` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Bash cat with ../ traversal → DENIED", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: `cat ${SRC}/orca/docs/../views.py` },
    });
    expect(isDenied(r)).toBe(true);
  });

  test("Read ~/src/orca/docs/real_doc.md with ../ → ALLOWED (still .md)", async () => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Read",
      tool_input: { file_path: `${SRC}/orca/foo/../docs/api.md` },
    });
    expect(isDenied(r)).toBe(false);
  });
});
