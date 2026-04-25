import { describe, it, expect } from "bun:test";
import { existsSync, readFileSync } from "fs";
import { join } from "path";

const ROOT = join(import.meta.dir, "..");

describe("plugin structure", () => {
  it("has dist binary", () => {
    expect(existsSync(join(ROOT, "dist", "orca-env-plugin"))).toBe(true);
  });

  it("has valid hooks.json", () => {
    const raw = readFileSync(join(ROOT, "hooks", "hooks.json"), "utf-8");
    const config = JSON.parse(raw);
    expect(config.hooks).toBeDefined();
    expect(config.hooks.SessionStart).toBeDefined();
    expect(config.hooks.Stop).toBeDefined();
    // No PreToolUse or PostToolUse
    expect(config.hooks.PreToolUse).toBeUndefined();
    expect(config.hooks.PostToolUse).toBeUndefined();
  });

  it("has valid plugin.json", () => {
    const raw = readFileSync(join(ROOT, ".claude-plugin", "plugin.json"), "utf-8");
    const meta = JSON.parse(raw);
    expect(meta.name).toBe("orca-env-plugin");
    expect(meta.version).toBe("5.0.0");
  });

  it("has CLAUDE.md with tool_routing fence", () => {
    const md = readFileSync(join(ROOT, "CLAUDE.md"), "utf-8");
    expect(md).toContain("<tool_routing>");
    expect(md).toContain("</tool_routing>");
  });

  it("has orca-dev skill", () => {
    expect(existsSync(join(ROOT, "skills", "orca-dev", "SKILL.md"))).toBe(true);
  });

  it("has orca-dev agent", () => {
    expect(existsSync(join(ROOT, "agents", "orca-dev.md"))).toBe(true);
  });

  it("does not have plugin-creator skill", () => {
    expect(existsSync(join(ROOT, "skills", "plugin-creator"))).toBe(false);
  });
});
