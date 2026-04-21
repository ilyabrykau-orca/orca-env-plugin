import { expect, test } from "bun:test";
import { handlePreToolUse } from "../../src/hot/pre-tool-use";
import { homedir } from "node:os";

const SRC = `${homedir()}/src/orca/foo`;

test("allow non-code Read", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: `${SRC}.md` } });
  expect(out.decision).toBe("approve");
});

test("deny code Read under ~/src with reason", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: `${SRC}.go` } });
  expect(out.decision).toBe("deny");
  expect(out.reason).toContain("codebase-memory");
});

test("allow code Read outside ~/src", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Read", tool_input: { file_path: "/tmp/x.go" } });
  expect(out.decision).toBe("approve");
});

test("deny Grep on ~/src without type/glob", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Grep", tool_input: { pattern: "x", path: `${homedir()}/src/orca` } });
  expect(out.decision).toBe("deny");
});

test("deny Edit on .ts under ~/src", () => {
  const out = handlePreToolUse({ session_id: "s1", tool_name: "Edit", tool_input: { file_path: `${SRC}.ts`, old_string: "a", new_string: "b" } });
  expect(out.decision).toBe("deny");
  expect(out.reason.toLowerCase()).toContain("serena");
});
