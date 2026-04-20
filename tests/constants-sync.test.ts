import { describe, test, expect } from "bun:test";
import { readFileSync } from "fs";
import { join } from "path";
import {
  SOURCE_EXTS,
  ALLOWED_EXTS,
  ALLOWED_FILENAME_PREFIXES,
  ALLOWED_PATH_COMPONENTS,
  SERENA_EDIT_TOOLS,
  NATIVE_FILE_TOOLS,
} from "../src/lib/constants";

const HOT_PATH = readFileSync(join(import.meta.dir, "..", "src", "hot", "pre-tool-use.ts"), "utf-8");

function extractSwitchCases(src: string, fnName: string): string[] {
  const fnMatch = src.match(new RegExp(`function ${fnName}\\([^)]*\\)[^{]*\\{[\\s\\S]*?^\\}`, "m"));
  if (!fnMatch) throw new Error(`Function ${fnName} not found`);
  const cases: string[] = [];
  const re = /case "([^"]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(fnMatch[0]))) cases.push(m[1]);
  return cases;
}

function extractArrayStrings(src: string, varName: string): string[] {
  const re = new RegExp(`const ${varName}\\s*=\\s*\\[([\\s\\S]*?)\\];`);
  const match = src.match(re);
  if (!match) throw new Error(`Array ${varName} not found`);
  const strs: string[] = [];
  const strRe = /"([^"]+)"/g;
  let m: RegExpExecArray | null;
  while ((m = strRe.exec(match[1]))) strs.push(m[1]);
  return strs;
}

describe("constants sync — hot path vs lib/constants", () => {
  test("SOURCE_EXTS match isSourceExt switch", () => {
    const hotExts = new Set(extractSwitchCases(HOT_PATH, "isSourceExt"));
    const libExts = SOURCE_EXTS;
    expect([...hotExts].sort()).toEqual([...libExts].sort());
  });

  test("ALLOWED_EXTS match isAllowedExt switch", () => {
    const hotExts = new Set(extractSwitchCases(HOT_PATH, "isAllowedExt"));
    const libExts = ALLOWED_EXTS;
    expect([...hotExts].sort()).toEqual([...libExts].sort());
  });

  test("ALLOWED_FILENAME_PREFIXES match ALLOWED_NAMES array", () => {
    const hotNames = extractArrayStrings(HOT_PATH, "ALLOWED_NAMES");
    expect(hotNames.sort()).toEqual([...ALLOWED_FILENAME_PREFIXES].sort());
  });

  test("ALLOWED_PATH_COMPONENTS match ALLOWED_PATHS array", () => {
    const hotPaths = extractArrayStrings(HOT_PATH, "ALLOWED_PATHS");
    expect(hotPaths.sort()).toEqual([...ALLOWED_PATH_COMPONENTS].sort());
  });

  test("SERENA_EDIT_TOOLS match SERENA_EDIT_PREFIXES array", () => {
    const hotPrefixes = extractArrayStrings(HOT_PATH, "SERENA_EDIT_PREFIXES");
    expect(hotPrefixes.sort()).toEqual([...SERENA_EDIT_TOOLS].sort());
  });

  test("NATIVE_FILE_TOOLS match isNativeFileTool switch", () => {
    const hotTools = new Set(extractSwitchCases(HOT_PATH, "isNativeFileTool"));
    const libTools = NATIVE_FILE_TOOLS;
    expect([...hotTools].sort()).toEqual([...libTools].sort());
  });
});
