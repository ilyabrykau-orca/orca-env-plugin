import { readStdin } from "./lib/stdin";
import { handlePreToolUse } from "./handlers/pre-tool-use";
import { handleSessionStart } from "./handlers/session-start";
import { handlePromptSubmit } from "./handlers/prompt-submit";
import { handlePostToolUse } from "./handlers/post-tool-use";
import { handleStop } from "./handlers/stop";

(async () => {
  const event = process.argv[2];
  const input = (await readStdin()) as Record<string, unknown> | null;

  if (!input) {
    process.exit(0);
  }

  let result: { stdout?: string; exitCode: number };

  switch (event) {
    case "pre-tool-use":
      result = handlePreToolUse(input as any);
      break;
    case "session-start":
      result = handleSessionStart(input as any);
      break;
    case "prompt-submit":
      result = handlePromptSubmit(input as any);
      break;
    case "post-tool-use":
      result = handlePostToolUse(input as any);
      break;
    case "stop":
      result = await handleStop(input as any, false);
      break;
    case "subagent-stop":
      result = await handleStop(input as any, true);
      break;
    default:
      process.exit(0);
  }

  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  process.exit(result.exitCode);
})();
