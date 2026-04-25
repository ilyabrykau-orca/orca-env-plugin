import { existsSync, mkdirSync, appendFileSync, writeFileSync } from "fs";
import { createReadStream } from "fs";
import { createInterface } from "readline";
import { join } from "path";

interface Tokens {
  input: number;
  output: number;
  cache_read: number;
  cache_creation: number;
  total: number;
}

interface Stats {
  tokens: Tokens;
  tools: Record<string, number>;
  messages: { user: number; assistant: number };
  timestamps: { start: Date | null; end: Date | null };
  session_id: string | null;
  model: string | null;
  hook_event?: string;
  agent_id?: string;
  cwd?: string;
  git_branch?: string;
  analyzed_at?: string;
  duration_seconds?: number;
}

interface StopInput {
  cwd: string;
  gitBranch: string;
  transcript_path?: string;
  agent_transcript_path?: string;
  agent_id?: string;
}

export async function handleStop(
  input: StopInput,
  isSubagent: boolean,
): Promise<void> {
  const transcriptPath = isSubagent
    ? (input.agent_transcript_path ?? input.transcript_path)
    : input.transcript_path;

  if (!transcriptPath || !existsSync(transcriptPath)) return;

  const stats = await parseTranscript(transcriptPath);
  stats.hook_event = isSubagent ? "SubagentStop" : "Stop";
  if (isSubagent) stats.agent_id = input.agent_id;
  stats.cwd = input.cwd;
  stats.git_branch = input.gitBranch;
  stats.analyzed_at = new Date().toISOString();

  const projectDir = process.env.CLAUDE_PROJECT_DIR ?? process.cwd();
  const statsDir = join(projectDir, "logs", "stats");
  mkdirSync(statsDir, { recursive: true });

  const logName = isSubagent ? "subagent-sessions.jsonl" : "sessions.jsonl";
  const logPath = join(statsDir, logName);
  appendFileSync(logPath, JSON.stringify(stats) + "\n");

  const latestName = isSubagent ? "latest-subagent-session.json" : "latest-session.json";
  writeFileSync(join(statsDir, latestName), JSON.stringify(stats, null, 2));

  const t = stats.tokens;
  process.stderr.write(
    `\n ${isSubagent ? "Subagent " : ""}Session Statistics:\n` +
    `   Tokens: ${t.total.toLocaleString()} (${t.input.toLocaleString()} in, ${t.output.toLocaleString()} out)\n` +
    `   Cache: ${t.cache_read.toLocaleString()} read, ${t.cache_creation.toLocaleString()} created\n` +
    `   Tools: ${Object.keys(stats.tools).length} types, ${Object.values(stats.tools).reduce((a: number, b: number) => a + b, 0)} total uses\n` +
    `   Duration: ${stats.duration_seconds ?? 0}s\n` +
    `   Saved to: ${logPath}\n\n`,
  );
}

async function parseTranscript(path: string): Promise<Stats> {
  const stats: Stats = {
    tokens: { input: 0, output: 0, cache_read: 0, cache_creation: 0, total: 0 },
    tools: {},
    messages: { user: 0, assistant: 0 },
    timestamps: { start: null, end: null },
    session_id: null,
    model: null,
  };

  const rl = createInterface({
    input: createReadStream(path),
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    try {
      const entry = JSON.parse(line);

      if (!stats.session_id && entry.sessionId) {
        stats.session_id = entry.sessionId;
      }

      if (entry.timestamp) {
        const ts = new Date(entry.timestamp);
        if (!stats.timestamps.start || ts < stats.timestamps.start) stats.timestamps.start = ts;
        if (!stats.timestamps.end || ts > stats.timestamps.end) stats.timestamps.end = ts;
      }

      if (entry.type === "user") {
        stats.messages.user++;
      } else if (entry.type === "assistant") {
        stats.messages.assistant++;
        if (entry.message?.model) stats.model = entry.message.model;
        else if (entry.model) stats.model = entry.model;

        const usage = entry.message?.usage;
        if (usage) {
          stats.tokens.input += usage.input_tokens ?? 0;
          stats.tokens.output += usage.output_tokens ?? 0;
          stats.tokens.cache_read += usage.cache_read_input_tokens ?? 0;
          stats.tokens.cache_creation += usage.cache_creation_input_tokens ?? 0;
        }

        const content = entry.message?.content;
        if (Array.isArray(content)) {
          for (const item of content) {
            if (item.type === "tool_use") {
              stats.tools[item.name] = (stats.tools[item.name] ?? 0) + 1;
            }
          }
        }
      }
    } catch {}
  }

  stats.tokens.total =
    stats.tokens.input + stats.tokens.output +
    stats.tokens.cache_read + stats.tokens.cache_creation;

  if (stats.timestamps.start && stats.timestamps.end) {
    stats.duration_seconds = Math.floor(
      (stats.timestamps.end.getTime() - stats.timestamps.start.getTime()) / 1000,
    );
  }

  return stats;
}
