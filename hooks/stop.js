#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { parseTranscript } from './utils/transcript-parser.js';

/**
 * Stop hook - Session statistics analyzer
 *
 * Parses the session transcript to extract:
 * - Total token usage (input, output, cache hits)
 * - Tool usage distribution
 * - Session duration
 * - Cost estimation
 *
 * Outputs to logs/stats/sessions.jsonl
 */

async function main() {
  let input = '';

  // Read JSON from stdin
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  try {
    const data = JSON.parse(input);
    const transcriptPath = data.transcript_path;

    if (!transcriptPath || !fs.existsSync(transcriptPath)) {
      console.error(`[stop] Transcript not found: ${transcriptPath}`);
      process.exit(0);
    }

    // Parse transcript
    const stats = await parseTranscript(transcriptPath);

    // Add metadata
    stats.hook_event = 'Stop';
    stats.cwd = data.cwd;
    stats.git_branch = data.gitBranch;
    stats.analyzed_at = new Date().toISOString();

    // Ensure stats directory exists
    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const statsDir = path.join(projectDir, 'logs', 'stats');
    if (!fs.existsSync(statsDir)) {
      fs.mkdirSync(statsDir, { recursive: true });
    }

    // Append to sessions log (JSONL format)
    const logPath = path.join(statsDir, 'sessions.jsonl');
    const logEntry = JSON.stringify(stats) + '\n';
    fs.appendFileSync(logPath, logEntry, 'utf8');

    // Also write a "latest session" file for quick access
    const latestPath = path.join(statsDir, 'latest-session.json');
    fs.writeFileSync(latestPath, JSON.stringify(stats, null, 2), 'utf8');

    // Print summary to stderr (won't interfere with hook protocol)
    console.error('\n Session Statistics:');
    console.error(`   Tokens: ${stats.tokens.total.toLocaleString()} (${stats.tokens.input.toLocaleString()} in, ${stats.tokens.output.toLocaleString()} out)`);
    console.error(`   Cache: ${stats.tokens.cache_read.toLocaleString()} read, ${stats.tokens.cache_creation.toLocaleString()} created`);
    console.error(`   Tools: ${Object.keys(stats.tools).length} types, ${Object.values(stats.tools).reduce((a, b) => a + b, 0)} total uses`);
    console.error(`   Duration: ${stats.duration_seconds}s`);
    console.error(`   Saved to: ${logPath}\n`);

    process.exit(0);
  } catch (err) {
    console.error(`[stop] Error: ${err.message}`);
    process.exit(0);
  }
}

main();
