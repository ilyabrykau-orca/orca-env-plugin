import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

export const DEFAULT_DB = join(homedir(), ".cache", "orca-env-plugin", "audit.sqlite");

let cachedDb: Database | null = null;
let cachedPath = "";

export function resetAuditCache(): void {
  try { cachedDb?.close(); } catch {}
  cachedDb = null;
  cachedPath = "";
}

function db(path: string): Database {
  if (cachedDb && cachedPath === path) return cachedDb;
  mkdirSync(dirname(path), { recursive: true });
  const d = new Database(path);
  d.exec(`
    CREATE TABLE IF NOT EXISTS decisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ts INTEGER NOT NULL,
      session_id TEXT NOT NULL,
      tool TEXT NOT NULL,
      target TEXT,
      allow INTEGER NOT NULL,
      reason TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_tool ON decisions(tool);
    CREATE INDEX IF NOT EXISTS idx_session ON decisions(session_id);
  `);
  cachedDb = d;
  cachedPath = path;
  return d;
}

export type DecisionRecord = {
  sessionId: string;
  tool: string;
  target: string;
  allow: boolean;
  reason: string;
};

export function recordDecision(r: DecisionRecord, path: string = DEFAULT_DB): void {
  db(path).prepare(
    "INSERT INTO decisions(ts, session_id, tool, target, allow, reason) VALUES (?, ?, ?, ?, ?, ?)"
  ).run(Date.now(), r.sessionId, r.tool, r.target, r.allow ? 1 : 0, r.reason);
}

export function blockRate(path: string = DEFAULT_DB): number {
  const row = db(path).prepare(
    "SELECT SUM(CASE WHEN allow=0 THEN 1 ELSE 0 END) AS denies, COUNT(*) AS total FROM decisions"
  ).get() as { denies: number | null; total: number };
  if (!row.total) return 0;
  return (row.denies ?? 0) / row.total;
}

export type DenyRow = { tool: string; target: string; count: number };
export function topDenies(limit: number, path: string = DEFAULT_DB): DenyRow[] {
  return db(path).prepare(
    "SELECT tool, target, COUNT(*) AS count FROM decisions WHERE allow=0 GROUP BY tool, target ORDER BY count DESC LIMIT ?"
  ).all(limit) as DenyRow[];
}
