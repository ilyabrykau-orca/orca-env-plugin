import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import { runBinary, isDenied, denyReason } from "./helpers";

const CORPUS_PATH = join(import.meta.dir, "fixtures", "bash-violation-corpus.txt");

// Source-ext path under ~/src/ (any user)
const SRC_EXT_RE =
  /\/Users\/[^\s"'`)\\]+\/src\/[^\s"'`)\\]*\.(go|ts|tsx|js|jsx|rs|py|c|cc|cpp|h|hpp|rb|java|kt|php|scala|swift)(?![A-Za-z0-9_])/;

const ALLOWED_PATH_SEGS = [
  "/docs/", "/doc/", "/documentation/", "/generated/", "/gen/",
  "/vendor/", "/node_modules/", "/testdata/", "/test_data/", "/fixtures/",
  "/.github/", "/.vscode/", "/.idea/", "/scripts/", "/hack/",
  "/deploy/", "/chart/", "/charts/", "/templates/",
];

function loadViolations(): string[] {
  const raw = readFileSync(CORPUS_PATH, "utf8");
  const lines = raw.split("\n");
  const out: string[] = [];
  for (const line of lines) {
    if (line.startsWith("#")) continue;
    if (line.trim() === "") continue;
    if (!SRC_EXT_RE.test(line)) continue;
    const m = line.match(SRC_EXT_RE);
    if (m) {
      let allowed = false;
      for (const seg of ALLOWED_PATH_SEGS) {
        if (m[0].includes(seg)) { allowed = true; break; }
      }
      if (allowed) continue;
    }
    if (/\|\s*bash\b/.test(line)) continue;
    out.push(line);
  }
  return out;
}

describe("bash allowlist fuzz corpus", () => {
  const violations = loadViolations();

  test("corpus has enough violations", () => {
    expect(violations.length).toBeGreaterThan(250);
  });

  test.each(violations)("DENIED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: cmd },
    });
    if (!isDenied(r)) {
      throw new Error(
        `Expected DENY, got allow/passthrough. cmd=${cmd.substring(0, 120)} reason=${denyReason(r)}`,
      );
    }
    expect(isDenied(r)).toBe(true);
  });
});

describe("bash allowlist — false-positive checks", () => {
  const ALLOWED = [
    "git status",
    "git log --oneline -5",
    "git diff HEAD",
    "ls /tmp",
    "make build",
    "bun test",
    "bun run build",
    "npm install",
    "cat /tmp/foo.py",
    "cat /etc/hosts",
    "echo hello",
    "cat ~/src/orca/README.md",
    "cat ~/src/orca/go.mod",
    "cat ~/src/orca/package.json",
    "head ~/src/orca/config.yaml",
    "ls ~/src/orca",
    "cd ~/src/orca",
  ];

  test.each(ALLOWED)("ALLOWED: %s", async (cmd) => {
    const r = await runBinary("pre-tool-use", {
      tool_name: "Bash",
      tool_input: { command: cmd },
    });
    expect(isDenied(r)).toBe(false);
  });
});
