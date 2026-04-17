import { appendFileSync, mkdirSync } from "fs";
import { LOG_DIR, LOG_FILE } from "./constants";

let dirEnsured = false;

export function log(
  action: string,
  tool: string,
  path: string,
  reason: string,
): void {
  if (!dirEnsured) {
    try {
      mkdirSync(LOG_DIR, { recursive: true });
    } catch {}
    dirEnsured = true;
  }
  const entry = JSON.stringify({
    ts: new Date().toISOString(),
    hook: "claude-toolkit",
    action,
    tool,
    path,
    reason,
  });
  try {
    appendFileSync(LOG_FILE, entry + "\n");
  } catch {}
}
