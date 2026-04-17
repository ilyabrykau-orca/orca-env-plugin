import { readFileSync, writeFileSync, mkdirSync, renameSync } from "fs";
import { dirname } from "path";

export interface RefsState {
  session_id: string | null;
  traced: Record<string, number>;
}

export function readState(path: string): RefsState {
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return { session_id: null, traced: {} };
  }
}

export function writeState(path: string, state: RefsState): void {
  const dir = dirname(path);
  try {
    mkdirSync(dir, { recursive: true });
  } catch {}
  const tmp = `${path}.tmp.${process.pid}`;
  writeFileSync(tmp, JSON.stringify(state) + "\n");
  renameSync(tmp, path);
}
