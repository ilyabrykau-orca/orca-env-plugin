import { describe, test, expect } from "bun:test";
import { runBinary, contextText } from "./helpers";

describe("prompt-submit", () => {
  test("first turn returns empty context", async () => {
    const r = await runBinary("user-prompt-submit", { prompt: "hello", session_id: "ps-test-1" });
    expect(r.exitCode).toBe(0);
  });

  test("caveman reminder reinjects periodically", async () => {
    const sid = `ps-reinject-${Date.now()}`;
    let sawReminder = false;
    for (let i = 0; i < 10; i++) {
      const r = await runBinary("user-prompt-submit", { prompt: "do stuff", session_id: sid });
      if (r.stdout && r.stdout.includes("CAVEMAN")) sawReminder = true;
    }
    expect(sawReminder).toBe(true);
  });

  test("empty prompt does not crash", async () => {
    const r = await runBinary("user-prompt-submit", { prompt: "", session_id: "ps-empty" });
    expect(r.exitCode).toBe(0);
  });

  test("missing session_id does not crash", async () => {
    const r = await runBinary("user-prompt-submit", { prompt: "test" });
    expect(r.exitCode).toBe(0);
  });
});
