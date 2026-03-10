import fs from 'fs';
import readline from 'readline';

/**
 * Shared transcript parser for stop and subagent-stop hooks.
 *
 * Parses a session transcript JSONL file and extracts:
 * - Token accumulation (input, output, cache hits)
 * - Tool usage tracking
 * - Message counting (user/assistant)
 * - Timestamp tracking (start/end, duration)
 * - Model extraction (checks both entry.model and entry.message.model)
 * - Malformed line handling (skip with warning)
 *
 * @param {string} transcriptPath - Absolute path to a JSONL transcript file.
 * @returns {Promise<object>} Parsed session statistics.
 */
export async function parseTranscript(transcriptPath) {
  const stats = {
    tokens: {
      input: 0,
      output: 0,
      cache_read: 0,
      cache_creation: 0,
      total: 0,
    },
    tools: {},
    messages: {
      user: 0,
      assistant: 0,
    },
    timestamps: {
      start: null,
      end: null,
    },
    session_id: null,
    model: null,
  };

  // Create readline interface to stream large files
  const fileStream = fs.createReadStream(transcriptPath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity,
  });

  for await (const line of rl) {
    try {
      const entry = JSON.parse(line);

      // Capture session metadata
      if (!stats.session_id && entry.sessionId) {
        stats.session_id = entry.sessionId;
      }

      // Track timestamps
      if (entry.timestamp) {
        const timestamp = new Date(entry.timestamp);
        if (!stats.timestamps.start || timestamp < stats.timestamps.start) {
          stats.timestamps.start = timestamp;
        }
        if (!stats.timestamps.end || timestamp > stats.timestamps.end) {
          stats.timestamps.end = timestamp;
        }
      }

      // Track message types
      if (entry.type === 'user') {
        stats.messages.user++;
      } else if (entry.type === 'assistant') {
        stats.messages.assistant++;

        // Extract model - check both entry.model and entry.message.model
        // Use most recent (last) model seen; message.model takes precedence
        // when both are present on the same entry.
        if (entry.model) {
          stats.model = entry.model;
        }
        if (entry.message?.model) {
          stats.model = entry.message.model;
        }

        // Sum token usage
        const usage = entry.message?.usage;
        if (usage) {
          stats.tokens.input += usage.input_tokens || 0;
          stats.tokens.output += usage.output_tokens || 0;
          stats.tokens.cache_read += usage.cache_read_input_tokens || 0;
          stats.tokens.cache_creation += usage.cache_creation_input_tokens || 0;
        }

        // Track tool usage
        const content = entry.message?.content;
        if (Array.isArray(content)) {
          for (const item of content) {
            if (item.type === 'tool_use') {
              const toolName = item.name;
              stats.tools[toolName] = (stats.tools[toolName] || 0) + 1;
            }
          }
        }
      }
    } catch (err) {
      // Skip malformed lines
      console.error(`[transcript-parser] Warning: Skipped malformed line: ${err.message}`);
    }
  }

  // Calculate totals
  stats.tokens.total =
    stats.tokens.input +
    stats.tokens.output +
    stats.tokens.cache_read +
    stats.tokens.cache_creation;

  // Calculate duration
  if (stats.timestamps.start && stats.timestamps.end) {
    stats.duration_ms = stats.timestamps.end - stats.timestamps.start;
    stats.duration_seconds = Math.floor(stats.duration_ms / 1000);
  }

  return stats;
}
