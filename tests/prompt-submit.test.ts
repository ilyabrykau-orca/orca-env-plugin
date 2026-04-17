import { describe, test, expect } from "bun:test";
import { runBinary } from "./helpers";

describe("prompt-submit", () => {
  test("matches exploration keywords", async () => {
    const r = await runBinary("prompt-submit", { prompt: "I want to explore the codebase" });
    expect(r.stdout).toContain("codebase-explorer");
  });

  test("matches edit keywords", async () => {
    const r = await runBinary("prompt-submit", { prompt: "edit the function to fix the bug" });
    expect(r.stdout).toContain("serena-editor");
  });

  test("matches web search keywords", async () => {
    const r = await runBinary("prompt-submit", { prompt: "search web for latest version of Go" });
    expect(r.stdout).toContain("web-search");
  });

  test("no match → empty output", async () => {
    const r = await runBinary("prompt-submit", { prompt: "hello world" });
    expect(r.stdout).toBe("");
  });

  test("multiple skills can match", async () => {
    const r = await runBinary("prompt-submit", { prompt: "explore code and check docs for fastapi" });
    expect(r.stdout).toContain("codebase-explorer");
    expect(r.stdout).toContain("docs-lookup");
  });
});
