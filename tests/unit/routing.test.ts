import { expect, test, describe } from "bun:test";
import { decide } from "../../src/lib/routing";
import { homedir } from "node:os";

const SRC = `${homedir()}/src/orca/foo`;

describe("routing.decide", () => {
  test("Read on .go under ~/src → deny with CBM hint", () => {
    const d = decide({ tool: "Read", args: { file_path: `${SRC}.go` } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("codebase-memory-mcp");
  });

  test("Read on .go outside ~/src → allow", () => {
    const d = decide({ tool: "Read", args: { file_path: "/tmp/foo.go" } });
    expect(d.allow).toBe(true);
  });

  test("Read on .md → allow", () => {
    const d = decide({ tool: "Read", args: { file_path: `${SRC}/readme.md` } });
    expect(d.allow).toBe(true);
  });

  test("Grep on ~/src without type/glob → deny", () => {
    const d = decide({ tool: "Grep", args: { pattern: "foo", path: `${homedir()}/src/orca` } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("codebase-memory-mcp");
  });

  test("Grep on /tmp → allow (outside ~/src scope)", () => {
    const d = decide({ tool: "Grep", args: { pattern: "foo", path: "/tmp" } });
    expect(d.allow).toBe(true);
  });

  test("Edit on .ts under ~/src → deny with Serena hint", () => {
    const d = decide({ tool: "Edit", args: { file_path: `${SRC}.ts`, old_string: "a", new_string: "b" } });
    expect(d.allow).toBe(false);
    expect(d.reason.toLowerCase()).toContain("serena");
  });

  test("Bash cat on .py under ~/src → deny", () => {
    const d = decide({ tool: "Bash", args: { command: `cat ${SRC}.py` } });
    expect(d.allow).toBe(false);
  });

  test("Bash cat on .py under /tmp → allow (outside scope)", () => {
    const d = decide({ tool: "Bash", args: { command: "cat /tmp/x.py" } });
    expect(d.allow).toBe(true);
  });

  test("Bash git command → allow", () => {
    const d = decide({ tool: "Bash", args: { command: "git status" } });
    expect(d.allow).toBe(true);
  });

  test("Write on .json → allow", () => {
    const d = decide({ tool: "Write", args: { file_path: `${SRC}.json`, content: "{}" } });
    expect(d.allow).toBe(true);
  });

  test("Serena replace_symbol_body → allow (handled elsewhere)", () => {
    const d = decide({ tool: "mcp__serena__replace_symbol_body", args: {} });
    expect(d.allow).toBe(true);
  });

  test("Read on Makefile under ~/src → allow (allowed filename)", () => {
    const d = decide({ tool: "Read", args: { file_path: `${homedir()}/src/orca/Makefile` } });
    expect(d.allow).toBe(true);
  });

  test("Read on .go in /docs/ → allow (allowed path component)", () => {
    const d = decide({ tool: "Read", args: { file_path: `${homedir()}/src/orca/docs/example.go` } });
    expect(d.allow).toBe(true);
  });

  test("Edit on .go outside ~/src → allow", () => {
    const d = decide({ tool: "Edit", args: { file_path: "/tmp/foo.go", old_string: "a", new_string: "b" } });
    expect(d.allow).toBe(true);
  });

  test("Grep with glob=*.go → deny", () => {
    const d = decide({ tool: "Grep", args: { pattern: "x", path: `${homedir()}/src/orca`, glob: "*.go" } });
    expect(d.allow).toBe(false);
  });

  test("Grep with type=go → deny", () => {
    const d = decide({ tool: "Grep", args: { pattern: "x", path: `${homedir()}/src/orca`, type: "go" } });
    expect(d.allow).toBe(false);
  });

  test("Glob pattern *.go → deny", () => {
    const d = decide({ tool: "Glob", args: { pattern: "**/*.go", path: `${homedir()}/src/orca` } });
    expect(d.allow).toBe(false);
  });
});
