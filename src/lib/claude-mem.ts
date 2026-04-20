export const DEFAULT_BASE = "http://localhost:37777";
const TIMEOUT_MS = 500;

export async function isHealthy(base: string = DEFAULT_BASE): Promise<boolean> {
  try {
    const res = await fetch(`${base}/api/health`, { signal: AbortSignal.timeout(TIMEOUT_MS) });
    return res.ok;
  } catch {
    return false;
  }
}
