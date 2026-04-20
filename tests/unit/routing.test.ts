import { expect, test, describe } from "bun:test";
import { decide } from "../../src/lib/routing";

describe("routing.decide", () => {
  test("Read on .go file → deny with CBM hint", () => {
    const d = decide({ tool: "Read", args: { file_path: "/tmp/foo.go" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("codebase-memory-mcp");
  });

  test("Read on .md file → allow", () => {
    const d = decide({ tool: "Read", args: { file_path: "/tmp/readme.md" } });
    expect(d.allow).toBe(true);
  });

  test("Grep on any path → deny with CBM hint", () => {
    const d = decide({ tool: "Grep", args: { pattern: "foo", path: "/tmp" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("search_code");
  });

  test("Edit on .ts → deny with Serena hint", () => {
    const d = decide({ tool: "Edit", args: { file_path: "/tmp/x.ts", old_string: "a", new_string: "b" } });
    expect(d.allow).toBe(false);
    expect(d.reason).toContain("serena");
  });

  test("Bash with cat on .py path → deny", () => {
    const d = decide({ tool: "Bash", args: { command: "cat /tmp/x.py" } });
    expect(d.allow).toBe(false);
  });

  test("Bash on git command → allow", () => {
    const d = decide({ tool: "Bash", args: { command: "git status" } });
    expect(d.allow).toBe(true);
  });

  test("Write on .json → allow", () => {
    const d = decide({ tool: "Write", args: { file_path: "/tmp/x.json", content: "{}" } });
    expect(d.allow).toBe(true);
  });

  test("Serena replace_symbol_body → allow (no L2 block, warning only)", () => {
    const d = decide({ tool: "mcp__serena__replace_symbol_body", args: {} });
    expect(d.allow).toBe(true);
  });
});
