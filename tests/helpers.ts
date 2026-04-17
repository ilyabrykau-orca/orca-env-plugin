import { join } from "path";

export const PLUGIN_ROOT = join(import.meta.dir, "..");
export const BINARY = join(PLUGIN_ROOT, "dist", "claude-toolkit");
export const HOME = process.env.HOME!;
export const SRC = `${HOME}/src`;

interface BinaryResult {
  stdout: string;
  stderr: string;
  exitCode: number;
  json: any;
}

export async function runBinary(event: string, input: unknown): Promise<BinaryResult> {
  const proc = Bun.spawn([BINARY, event], {
    stdin: new Blob([JSON.stringify(input)]),
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...process.env,
      CLAUDE_PLUGIN_ROOT: PLUGIN_ROOT,
    },
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  let json = null;
  try { json = JSON.parse(stdout); } catch {}
  return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode, json };
}

export function isDenied(result: BinaryResult): boolean {
  return result.json?.hookSpecificOutput?.permissionDecision === "deny";
}

export function isAllowed(result: BinaryResult): boolean {
  return !result.stdout || result.json?.hookSpecificOutput?.permissionDecision === "allow";
}

export function denyReason(result: BinaryResult): string {
  return result.json?.hookSpecificOutput?.permissionDecisionReason ?? "";
}

export function contextText(result: BinaryResult): string {
  return result.json?.hookSpecificOutput?.additionalContext ?? "";
}
