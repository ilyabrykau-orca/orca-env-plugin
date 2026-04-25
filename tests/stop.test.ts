import { describe, it, expect, beforeEach, afterEach } from "bun:test";
import { handleStop } from "../src/stop.ts";
import { writeFileSync, mkdirSync, rmSync, existsSync, readFileSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

describe("handleStop", () => {
  let tmpDir: string;
  let transcriptPath: string;

  beforeEach(() => {
    tmpDir = join(tmpdir(), `orca-stop-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });
    transcriptPath = join(tmpDir, "transcript.jsonl");
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it("exits cleanly when no transcript path", async () => {
    await handleStop({ cwd: tmpDir, gitBranch: "main" }, false);
    // Should not throw
  });

  it("exits cleanly when transcript does not exist", async () => {
    await handleStop(
      { cwd: tmpDir, gitBranch: "main", transcript_path: "/nonexistent" },
      false,
    );
  });

  it("parses transcript and writes stats", async () => {
    const entries = [
      JSON.stringify({
        type: "user",
        timestamp: "2026-04-24T10:00:00Z",
        sessionId: "test-123",
      }),
      JSON.stringify({
        type: "assistant",
        timestamp: "2026-04-24T10:01:00Z",
        message: {
          model: "claude-opus-4-6-20260424",
          usage: {
            input_tokens: 1000,
            output_tokens: 500,
            cache_read_input_tokens: 200,
            cache_creation_input_tokens: 100,
          },
          content: [
            { type: "tool_use", name: "Read" },
            { type: "tool_use", name: "Bash" },
            { type: "tool_use", name: "Read" },
          ],
        },
      }),
    ];
    writeFileSync(transcriptPath, entries.join("\n") + "\n");

    const oldProjectDir = process.env.CLAUDE_PROJECT_DIR;
    process.env.CLAUDE_PROJECT_DIR = tmpDir;

    try {
      await handleStop(
        { cwd: tmpDir, gitBranch: "main", transcript_path: transcriptPath },
        false,
      );
    } finally {
      if (oldProjectDir) process.env.CLAUDE_PROJECT_DIR = oldProjectDir;
      else delete process.env.CLAUDE_PROJECT_DIR;
    }

    const statsDir = join(tmpDir, "logs", "stats");
    expect(existsSync(join(statsDir, "sessions.jsonl"))).toBe(true);
    expect(existsSync(join(statsDir, "latest-session.json"))).toBe(true);

    const latest = JSON.parse(readFileSync(join(statsDir, "latest-session.json"), "utf-8"));
    expect(latest.tokens.input).toBe(1000);
    expect(latest.tokens.output).toBe(500);
    expect(latest.tokens.cache_read).toBe(200);
    expect(latest.tokens.total).toBe(1800);
    expect(latest.tools.Read).toBe(2);
    expect(latest.tools.Bash).toBe(1);
    expect(latest.messages.user).toBe(1);
    expect(latest.messages.assistant).toBe(1);
    expect(latest.session_id).toBe("test-123");
    expect(latest.hook_event).toBe("Stop");
    expect(latest.duration_seconds).toBe(60);
  });

  it("writes subagent stats with SubagentStop event", async () => {
    const entries = [
      JSON.stringify({
        type: "user",
        timestamp: "2026-04-24T10:00:00Z",
      }),
    ];
    writeFileSync(transcriptPath, entries.join("\n") + "\n");

    const oldProjectDir = process.env.CLAUDE_PROJECT_DIR;
    process.env.CLAUDE_PROJECT_DIR = tmpDir;

    try {
      await handleStop(
        {
          cwd: tmpDir,
          gitBranch: "feat/test",
          agent_transcript_path: transcriptPath,
          agent_id: "agent-42",
        },
        true,
      );
    } finally {
      if (oldProjectDir) process.env.CLAUDE_PROJECT_DIR = oldProjectDir;
      else delete process.env.CLAUDE_PROJECT_DIR;
    }

    const statsDir = join(tmpDir, "logs", "stats");
    expect(existsSync(join(statsDir, "subagent-sessions.jsonl"))).toBe(true);

    const latest = JSON.parse(
      readFileSync(join(statsDir, "latest-subagent-session.json"), "utf-8"),
    );
    expect(latest.hook_event).toBe("SubagentStop");
    expect(latest.agent_id).toBe("agent-42");
  });
});
