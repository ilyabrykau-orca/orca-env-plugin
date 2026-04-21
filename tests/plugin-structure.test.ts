import { describe, test, expect } from "bun:test";
import { existsSync, readFileSync, readdirSync } from "fs";
import { BINARY, PLUGIN_ROOT } from "./helpers";
import { join } from "path";

describe("plugin structure", () => {
  test("binary exists and is executable", () => {
    expect(existsSync(BINARY)).toBe(true);
  });

  test("hooks.json routes all events to binary", () => {
    const hooks = JSON.parse(readFileSync(join(PLUGIN_ROOT, "hooks", "hooks.json"), "utf-8"));
    const events = ["PreToolUse", "SessionStart", "UserPromptSubmit", "PostToolUse", "Stop", "SubagentStop"];
    for (const event of events) {
      expect(hooks.hooks[event]).toBeDefined();
      const cmd = hooks.hooks[event][0].hooks[0].command;
      expect(cmd).toContain("orca-env-plugin");
    }
  });

  test("no codanna references in skills", () => {
    const skills = ["orca-setup", "codebase-explorer", "docs", "serena-workflow"];
    for (const skill of skills) {
      const path = join(PLUGIN_ROOT, "skills", skill, "SKILL.md");
      if (existsSync(path)) {
        const content = readFileSync(path, "utf-8");
        expect(content.toLowerCase()).not.toContain("codanna");
      }
    }
  });

  test("skill-rules has no caveman-compress", () => {
    const rules = JSON.parse(readFileSync(join(PLUGIN_ROOT, "skills", "skill-rules.json"), "utf-8"));
    expect(rules.skills["caveman-compress"]).toBeUndefined();
  });

  test("agents have no native file tools", () => {
    const agentDir = join(PLUGIN_ROOT, "agents");
    const agents = readdirSync(agentDir).filter(f => f.endsWith(".md"));
    expect(agents.length).toBeGreaterThan(0);
    const forbidden = ["Bash", "Read", "Grep", "Glob", "Search", "Edit", "Write"];
    for (const agent of agents) {
      const content = readFileSync(join(agentDir, agent), "utf-8");
      for (const tool of forbidden) {
        const lines = content.split("\n").filter(l => l.trim().startsWith("- "));
        for (const line of lines) {
          expect(line.trim()).not.toBe(`- ${tool}`);
        }
      }
    }
  });
});
