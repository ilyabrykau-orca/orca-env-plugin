import { readFileSync } from "fs";
import { PLUGIN_ROOT } from "../lib/constants";

interface PromptInput {
  prompt?: string;
  user_prompt?: string;
}

interface SkillRule {
  priority?: string;
  description?: string;
  promptTriggers?: {
    keywords?: string[];
    intentPatterns?: string[];
  };
}

interface SkillRules {
  skills: Record<string, SkillRule>;
}

export function handlePromptSubmit(input: PromptInput): {
  stdout?: string;
  exitCode: number;
} {
  const prompt = ((input.prompt ?? input.user_prompt) ?? "").toLowerCase();
  if (!prompt) return { exitCode: 0 };

  let rules: SkillRules;
  try {
    const rulesPath = `${PLUGIN_ROOT}/skills/skill-rules.json`;
    rules = JSON.parse(readFileSync(rulesPath, "utf-8"));
  } catch {
    return { exitCode: 0 };
  }

  const matches: { priority: string; name: string; action?: string }[] = [];

  for (const [name, rule] of Object.entries(rules.skills)) {
    const triggers = rule.promptTriggers;
    if (!triggers) continue;

    let matched = false;

    // Keyword match
    if (triggers.keywords) {
      for (const kw of triggers.keywords) {
        if (prompt.includes(kw.toLowerCase())) {
          matched = true;
          break;
        }
      }
    }

    // Intent pattern match
    if (!matched && triggers.intentPatterns) {
      for (const pattern of triggers.intentPatterns) {
        try {
          if (new RegExp(pattern, "i").test(prompt)) {
            matched = true;
            break;
          }
        } catch {}
      }
    }

    if (matched) {
      matches.push({
        priority: rule.priority ?? "medium",
        name,
        action: rule.description,
      });
    }
  }

  if (matches.length === 0) return { exitCode: 0 };

  // Build output grouped by priority
  const priorityOrder = ["critical", "high", "medium", "low"];
  const lines: string[] = ["SKILL ACTIVATION CHECK"];

  for (const level of priorityOrder) {
    const group = matches.filter((m) => m.priority === level);
    if (group.length === 0) continue;
    const label =
      level === "critical" ? "REQUIRED" :
      level === "high" ? "RECOMMENDED" :
      level === "medium" ? "SUGGESTED" : "OPTIONAL";
    const names = group.map((m) => m.name).join(", ");
    lines.push(`${label}: ${names}`);
  }

  lines.push("ACTION: Use Skill tool or appropriate MCP tools BEFORE responding");

  return { stdout: lines.join("\n"), exitCode: 0 };
}
