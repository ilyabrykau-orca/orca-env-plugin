import { readFileSync, writeSync } from "fs";
import { handlePreToolUse } from "./hot/pre-tool-use";
import { handleSessionStart } from "./cold/session-start";
import { handlePostToolUse } from "./cold/post-tool-use";
import { handleStop } from "./cold/stop";

// Read ALL stdin synchronously via fd 0 -- no async overhead
const raw = readFileSync(0, "utf-8");
const event = process.argv[2];

if (event === "pre-tool-use") {
  // HOT PATH -- everything sync, zero-alloc, no JSON.parse
  handlePreToolUse(raw);
  // handlePreToolUse calls process.exit() internally -- never reaches here
} else {
  // COLD PATHS -- async is fine
  (async () => {
    let input: any;
    try { input = JSON.parse(raw); } catch { process.exit(0); }

    switch (event) {
      case "session-start": {
        const r = handleSessionStart(input);
        if (r.stdout) writeSync(1, r.stdout);
        process.exit(r.exitCode);
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
