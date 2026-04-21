import { readFileSync, writeSync } from "fs";
import { runPreToolUseCli } from "./hot/pre-tool-use";
import { runUserPromptSubmitCli } from "./hot/user-prompt-submit";
import { handleSessionStart } from "./cold/session-start";
import { handlePostToolUse } from "./cold/post-tool-use";
import { handleStop } from "./cold/stop";
import { runGainCli } from "./cli/gain";

const event = process.argv[2];

// gain CLI: no stdin needed
if (event === "gain") {
  runGainCli();
  process.exit(0);
}

// Read ALL stdin synchronously via fd 0 -- no async overhead
const raw = readFileSync(0, "utf-8");

if (event === "pre-tool-use") {
  runPreToolUseCli(raw);
} else if (event === "user-prompt-submit") {
  runUserPromptSubmitCli(raw);
} else {
  (async () => {
    let input: any;
    try { input = JSON.parse(raw); } catch { process.exit(0); }

    switch (event) {
      case "session-start": {
        const r = await handleSessionStart(input);
        if (r.stdout) writeSync(1, r.stdout);
        process.exit(r.exitCode ?? 0);
        break;
      }
      case "post-tool-use": {
        const r = handlePostToolUse(input);
        process.exit(r.exitCode);
        break;
      }
      case "stop": {
        const r = await handleStop(input, false);
        process.exit(r.exitCode);
        break;
      }
      case "subagent-stop": {
        const r = await handleStop(input, true);
        process.exit(r.exitCode);
        break;
      }
      default:
        process.exit(0);
    }
  })();
}
