const PROJECT_MAP: Record<string, string> = {
  "orca-env-plugin": "orca-env-plugin",
  "orca-cloud-platform": "orca-cloud-platform",
  "orca-runtime-sensor": "orca-runtime-sensor",
  "orca-sensor": "orca-sensor",
  "helm-charts": "helm-charts",
  "grafana-provisioning": "grafana-provisioning",
};

const ROUTING_HINT = `PREFERRED ROUTING (advisory, not enforced):
Source search → CBM (search_code, get_code_snippet, search_graph). Source edit → find_referencing_symbols first, then native Edit.
Non-source (.json, .yaml, .md) → native Read/Edit/Write. Shell → Bash.
Batch independent tool calls in one message. Use Agent for exploration (separate context, cheaper).`;

function detectProject(cwd: string): string {
  if (!cwd) return "";
  for (const [dir, project] of Object.entries(PROJECT_MAP)) {
    if (cwd.includes(`/${dir}`)) return project;
  }
  if (cwd.includes("/src/orca")) return "orca";
  const srcDir = `${process.env.HOME ?? ""}/src`;
  if (cwd === srcDir || cwd === srcDir + "/") return "orca-unified";
  return "";
}

interface SessionStartPayload {
  cwd: string;
}

export async function handleSessionStart(
  p: SessionStartPayload,
): Promise<{ appendContext: string }> {
  const project = detectProject(p.cwd);
  const parts: string[] = [];

  if (project) {
    parts.push(
      `SERENA WORKSPACE DETECTED: project='${project}' at ${p.cwd}\n` +
      `IMMEDIATELY call: mcp__serena__activate_project(project=${project})`,
    );
  }

  parts.push(ROUTING_HINT);

  return { appendContext: parts.join("\n\n") };
}
