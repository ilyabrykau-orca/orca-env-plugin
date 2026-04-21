import { describe, test, expect } from "bun:test";
import { decide, resolvePath, extOf, baseOf, type Decision } from "../src/lib/routing";

const HOME = process.env.HOME!;
const SRC = `${HOME}/src`;

function d(tool: string, args: Record<string, unknown>, cwd?: string): Decision {
  return decide({ tool, args }, cwd ?? SRC);
}

describe("routing edge cases — exempt paths", () => {
  test(".ts in node_modules → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/node_modules/@types/node/index.ts` });
    expect(r.allow).toBe(true);
  });
  test(".py in vendor/ → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/vendor/github.com/some/lib.py` });
    expect(r.allow).toBe(true);
  });
  test(".go in testdata/ → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca-runtime-sensor/testdata/sample.go` });
    expect(r.allow).toBe(true);
  });
  test(".ts in .github/workflows → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/.github/workflows/ci.ts` });
    expect(r.allow).toBe(true);
  });
  test(".py in scripts/ → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/scripts/deploy.py` });
    expect(r.allow).toBe(true);
  });
  test(".go in fixtures/ → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/fixtures/test.go` });
    expect(r.allow).toBe(true);
  });
});

describe("routing edge cases — relative paths", () => {
  test("relative ./foo.py from cwd=~/src/orca → denied", () => {
    const r = d("Read", { file_path: "./foo.py" }, `${SRC}/orca`);
    expect(r.allow).toBe(false);
  });
  test("relative ../orca-sensor/cmd/main.go from cwd=~/src/orca → denied", () => {
    const r = d("Read", { file_path: "../orca-sensor/cmd/main.go" }, `${SRC}/orca`);
    expect(r.allow).toBe(false);
  });
  test("relative ./README.md from cwd=~/src/orca → allowed", () => {
    const r = d("Read", { file_path: "./README.md" }, `${SRC}/orca`);
    expect(r.allow).toBe(true);
  });
});

describe("routing edge cases — double-dot traversal", () => {
  test("docs/../core.py resolves to core.py → denied", () => {
    const r = d("Read", { file_path: `${SRC}/orca/docs/../core.py` });
    expect(r.allow).toBe(false);
  });
  test("vendor/../secret.py resolves outside vendor → denied", () => {
    const r = d("Read", { file_path: `${SRC}/orca/vendor/../secret.py` });
    expect(r.allow).toBe(false);
  });
  test("docs/../docs/api.md stays in docs → allowed", () => {
    const r = d("Read", { file_path: `${SRC}/orca/docs/../docs/api.md` });
    expect(r.allow).toBe(true);
  });
});

describe("routing edge cases — Grep/Glob source type guards", () => {
  test("Grep type=python (alias) → denied", () => {
    const r = d("Grep", { path: SRC, type: "python", pattern: "import" });
    expect(r.allow).toBe(false);
  });
  test("Grep type=ruby → denied", () => {
    const r = d("Grep", { path: SRC, type: "ruby", pattern: "def" });
    expect(r.allow).toBe(false);
  });
  test("Grep glob=*.rs under ~/src → denied", () => {
    const r = d("Grep", { path: SRC, glob: "*.rs", pattern: "fn" });
    expect(r.allow).toBe(false);
  });
  test("Grep type=md → allowed", () => {
    const r = d("Grep", { path: SRC, type: "md", pattern: "# " });
    expect(r.allow).toBe(true);
  });
  test("Glob *.{ts,md} → denied (contains ts)", () => {
    const r = d("Glob", { path: SRC, pattern: "*.{ts,md}" });
    expect(r.allow).toBe(false);
  });
  test("Glob *.{json,yaml} → allowed", () => {
    const r = d("Glob", { path: SRC, pattern: "*.{json,yaml}" });
    expect(r.allow).toBe(true);
  });
});

describe("routing edge cases — Bash", () => {
  test("cat extensionless file under ~/src → allowed (not source code)", () => {
    const r = d("Bash", { command: `cat ${SRC}/orca/somebinary` });
    expect(r.allow).toBe(true);
  });
  test("cat on Makefile → allowed (allowed name)", () => {
    const r = d("Bash", { command: `cat ${SRC}/orca/Makefile` });
    expect(r.allow).toBe(true);
  });
  test("unknown tool always allowed", () => {
    const r = d("SomeFutureTool", { whatever: true });
    expect(r.allow).toBe(true);
    expect(r.reason).toBe("no rule");
  });
  test("empty Bash command → allowed", () => {
    const r = d("Bash", { command: "" });
    expect(r.allow).toBe(true);
    expect(r.reason).toBe("empty");
  });
});

describe("resolvePath edge cases", () => {
  test("tilde expansion", () => expect(resolvePath("~/src/orca")).toBe(`${HOME}/src/orca`));
  test("absolute unchanged", () => expect(resolvePath("/tmp/foo")).toBe("/tmp/foo"));
  test("relative with cwd", () => expect(resolvePath("bar.py", "/foo")).toBe("/foo/bar.py"));
  test("multiple ..", () => expect(resolvePath("/a/b/c/../../d")).toBe("/a/d"));
  test(".. at root", () => expect(resolvePath("/../../foo")).toBe("/foo"));
  test("empty returns empty", () => expect(resolvePath("")).toBe(""));
  test("single dot removed", () => expect(resolvePath("/a/./b")).toBe("/a/b"));
});

describe("extOf / baseOf edge cases", () => {
  test("no extension", () => expect(extOf("Makefile")).toBe(""));
  test("dotfile", () => expect(extOf(".gitignore")).toBe("gitignore"));
  test("double extension", () => expect(extOf("foo.test.ts")).toBe("ts"));
  test("trailing dot", () => expect(extOf("foo.")).toBe(""));
  test("baseOf root", () => expect(baseOf("/")).toBe(""));
  test("baseOf simple", () => expect(baseOf("foo.py")).toBe("foo.py"));
});
