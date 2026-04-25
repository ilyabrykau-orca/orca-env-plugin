import { readFileSync } from "fs";
import { handleSessionStart } from "./session-start.ts";
import { handleStop } from "./stop.ts";

(async () => {
  const event = process.argv[2];
  const raw = readFileSync(0, "utf-8");

  switch (event) {
    case "session-start": {
      const result = await handleSessionStart(JSON.parse(raw));
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "SessionStart",
          additionalContext: result.appendContext,
        },
      }));
      process.exit(0);
      break;
    }
    case "stop": {
      await handleStop(JSON.parse(raw), false);
      process.exit(0);
      break;
    }
    case "subagent-stop": {
      await handleStop(JSON.parse(raw), true);
      process.exit(0);
      break;
    }
    default:
      process.stderr.write(`Unknown event: ${event}\n`);
      process.exit(1);
  }
})();