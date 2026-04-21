import { expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import script from "./prompts/drift-script.json";

test.skipIf(!process.env.RUN_INTEGRATION)("caveman + routing hold for 60 turns", () => {
  writeFileSync(script.native_read_file, "package main\n");

  const banned = new RegExp(script.banned_filler.join("|"), "i");
  let fillerHits = 0;
  let blockMisses = 0;

  for (let i = 1; i <= script.turns; i++) {
    const wantNativeRead = script.native_read_at_turn.includes(i);
    const prompt = wantNativeRead
      ? `Read ${script.native_read_file} using the native Read tool and print first line.`
      : script.prompt_template;

    const r = spawnSync("claude", ["-p", prompt, "--output-format", "text"], { encoding: "utf8", timeout: 60_000 });
    const out = r.stdout ?? "";

    if (i % script.check_every === 0 && banned.test(out)) fillerHits++;
    if (wantNativeRead && !/codebase-memory|serena/i.test(out)) blockMisses++;
  }

  expect(fillerHits).toBe(0);
  expect(blockMisses).toBe(0);
}, 900_000);
