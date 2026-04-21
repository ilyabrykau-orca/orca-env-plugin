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

describe("constants sync — hot path vs lib/constants", () => {
  test("SOURCE_EXTS contains expected code extensions", () => {
    expect(SOURCE_EXTS.size).toBeGreaterThan(0);
    expect(SOURCE_EXTS.has("py")).toBe(true);
    expect(SOURCE_EXTS.has("go")).toBe(true);
    expect(SOURCE_EXTS.has("ts")).toBe(true);
  });

  test("ALLOWED_EXTS contains expected non-code extensions", () => {
    expect(ALLOWED_EXTS.size).toBeGreaterThan(0);
    expect(ALLOWED_EXTS.has("md")).toBe(true);
    expect(ALLOWED_EXTS.has("json")).toBe(true);
    expect(ALLOWED_EXTS.has("yaml")).toBe(true);
  });

  test("ALLOWED_FILENAME_PREFIXES contains standard filenames", () => {
    expect(ALLOWED_FILENAME_PREFIXES.length).toBeGreaterThan(0);
    expect(ALLOWED_FILENAME_PREFIXES).toContain("Makefile");
    expect(ALLOWED_FILENAME_PREFIXES).toContain("Dockerfile");
  });

  test("ALLOWED_PATH_COMPONENTS contains exempt directories", () => {
    expect(ALLOWED_PATH_COMPONENTS.length).toBeGreaterThan(0);
    expect(ALLOWED_PATH_COMPONENTS).toContain("/docs/");
    expect(ALLOWED_PATH_COMPONENTS).toContain("/vendor/");
  });

  test("SERENA_EDIT_TOOLS in hot path match lib constants", () => {
    const hotSerena = HOT_PATH.match(/SERENA_EDIT_TOOLS.*?new Set\(\[([\s\S]*?)\]\)/);
    expect(hotSerena).not.toBeNull();
    const hotTools = hotSerena![1].match(/"([^"]+)"/g)!.map(s => s.replace(/"/g, ""));
    expect(hotTools.sort()).toEqual([...SERENA_EDIT_TOOLS].sort());
  });

  test("NATIVE_FILE_TOOLS contains core native tools", () => {
    expect(NATIVE_FILE_TOOLS.size).toBeGreaterThan(0);
    expect(NATIVE_FILE_TOOLS.has("Read")).toBe(true);
    expect(NATIVE_FILE_TOOLS.has("Edit")).toBe(true);
    expect(NATIVE_FILE_TOOLS.has("Write")).toBe(true);
  });
});
