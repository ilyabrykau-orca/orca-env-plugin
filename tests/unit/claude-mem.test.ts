import { expect, test, beforeAll, afterAll } from "bun:test";
import { isHealthy } from "../../src/lib/claude-mem";

let server: ReturnType<typeof Bun.serve>;
const port = 37779;

beforeAll(() => {
  server = Bun.serve({
    port,
    fetch(req) {
      const url = new URL(req.url);
      if (url.pathname === "/api/health") return new Response("ok");
      return new Response("not found", { status: 404 });
    },
  });
});

afterAll(() => { server.stop(); });

test("isHealthy returns true when worker up", async () => {
  expect(await isHealthy(`http://localhost:${port}`)).toBe(true);
});

test("isHealthy returns false when worker down", async () => {
  expect(await isHealthy(`http://localhost:1`)).toBe(false);
});
