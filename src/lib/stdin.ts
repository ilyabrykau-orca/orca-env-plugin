const chunks: Buffer[] = [];
for await (const chunk of Bun.stdin.stream()) {
  chunks.push(Buffer.from(chunk));
}
const raw = Buffer.concat(chunks).toString("utf-8");

export function readStdin(): unknown {
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function getRaw(): string {
  return raw;
}
