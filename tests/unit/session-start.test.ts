import { expect, test } from "bun:test";
import { handleSessionStart } from "../../src/cold/session-start";
import { REMINDER } from "../../src/hot/user-prompt-submit";
import { homedir } from "node:os";

test("startup under ~/src returns workspace context, no reminder", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "startup", cwd: `${homedir()}/src` }, { memBase: "http://localhost:1" });
  expect(out.appendContext).toContain("orca-unified");
  expect(out.appendContext).not.toContain("CAVEMAN");
});

test("compact re-injects reminder + workspace", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "compact", cwd: `${homedir()}/src` }, { memBase: "http://localhost:1" });
  expect(out.appendContext).toContain(REMINDER);
  expect(out.appendContext).toContain("orca-unified");
});

test("resume re-injects reminder", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "resume", cwd: `${homedir()}/src/orca-env-plugin` }, { memBase: "http://localhost:1" });
  expect(out.appendContext).toContain(REMINDER);
  expect(out.appendContext).toContain("orca-env-plugin");
});

test("detects orca project by cwd prefix", async () => {
  const out = await handleSessionStart({ session_id: "s1", source: "startup", cwd: `${homedir()}/src/orca/services` }, { memBase: "http://localhost:1" });
  expect(out.appendContext).toContain("orca");
});
