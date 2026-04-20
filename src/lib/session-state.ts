import { mkdirSync, readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

export const DEFAULT_ROOT = join(homedir(), ".cache", "orca-env-plugin", "sessions");

function pathFor(sessionId: string, root: string): string {
  mkdirSync(root, { recursive: true });
  return join(root, `${sessionId}.json`);
}

export function getTurn(sessionId: string, root: string = DEFAULT_ROOT): number {
  const p = pathFor(sessionId, root);
  if (!existsSync(p)) return 0;
  try {
    const data = JSON.parse(readFileSync(p, "utf8")) as { turn: number };
    return data.turn ?? 0;
  } catch {
    return 0;
  }
}

export function incrementTurn(sessionId: string, root: string = DEFAULT_ROOT): number {
  const current = getTurn(sessionId, root);
  const next = current + 1;
  writeFileSync(pathFor(sessionId, root), JSON.stringify({ turn: next }));
  return next;
}

export function resetSession(sessionId: string, root: string = DEFAULT_ROOT): void {
  const p = pathFor(sessionId, root);
  if (existsSync(p)) unlinkSync(p);
}
