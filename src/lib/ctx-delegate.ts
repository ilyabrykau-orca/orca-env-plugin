import { readdirSync, writeSync } from "node:fs";
import { resolve } from "node:path";
import { homedir } from "node:os";

const CACHE = resolve(homedir(), ".claude", "plugins", "cache", "context-mode", "context-mode");

function findCtxRoot(): string {
  try {
    const versions = readdirSync(CACHE).filter(d => /^\d/.test(d)).sort();
    if (versions.length === 0) return "";
    return resolve(CACHE, versions[versions.length - 1]);
  } catch { return ""; }
}

/**
 * Delegate a hook event to context-mode's script.
 * Spawns node with the script, pipes raw stdin, forwards stdout.
 * Returns exit code (0 if context-mode not found).
 */
export function delegateContextMode(script: string, raw: string): number {
  const root = findCtxRoot();
  if (!root) return 0;

  const scriptPath = resolve(root, "hooks", script);
  try {
    const r = Bun.spawnSync(["node", scriptPath], {
      stdin: Buffer.from(raw),
      stdout: "pipe",
      stderr: "pipe",
      env: { ...process.env, CLAUDE_PLUGIN_ROOT: root },
    });
    if (r.stdout.length) writeSync(1, r.stdout);
    return r.exitCode;
  } catch { return 0; }
}
