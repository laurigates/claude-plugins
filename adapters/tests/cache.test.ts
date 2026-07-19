/**
 * Embedding-cache tests (DESIGN §7.3): key invalidation on every keyed
 * dimension, atomic writes, self-pruning rewrite, corrupt-file recovery.
 */

import { describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cacheFilePath, entryKey, loadCache, saveCache } from "../core/cache.ts";

const BASE = {
  model: "nomic-embed-text",
  dims: 768,
  prefixScheme: "search_document:/search_query:",
  skillName: "git-commit",
  description: "Commit staged changes.",
};

describe("entryKey", () => {
  test("unchanged content hits the same key", () => {
    expect(entryKey({ ...BASE })).toBe(entryKey({ ...BASE }));
  });

  test.each([
    ["description", { description: "Commit staged changes!" }],
    ["model", { model: "nomic-embed-text:v2" }],
    ["dims", { dims: 256 }],
    ["prefixScheme", { prefixScheme: "document:/query:" }],
    ["skillName", { skillName: "git-commit-workflow" }],
  ] as const)("changing %s produces a different key", (_label, delta) => {
    expect(entryKey({ ...BASE, ...delta })).not.toBe(entryKey(BASE));
  });

  test("field-boundary collisions are impossible (NUL-joined material)", () => {
    // "ab" + "c" vs "a" + "bc" must not collide.
    const a = entryKey({ ...BASE, skillName: "ab", description: "c" });
    const b = entryKey({ ...BASE, skillName: "a", description: "bc" });
    expect(a).not.toBe(b);
  });
});

describe("cacheFilePath", () => {
  test("is keyed per repo path, under the given cache dir", () => {
    const a = cacheFilePath("/repo/one", "/cache");
    const b = cacheFilePath("/repo/two", "/cache");
    expect(a).not.toBe(b);
    expect(a.startsWith("/cache/")).toBe(true);
    expect(a.endsWith(".json")).toBe(true);
  });
});

describe("save/load", () => {
  test("round-trips and leaves no .tmp behind (atomic write)", () => {
    const dir = mkdtempSync(join(tmpdir(), "adapters-cache-"));
    const file = join(dir, "cache.json");
    const cache = { version: 1, model: "m", dims: 4, entries: { abc: [1, 2, 3, 4] } };
    saveCache(file, cache);
    expect(loadCache(file)).toEqual(cache);
    expect(existsSync(`${file}.tmp`)).toBe(false);
    expect(readdirSync(dir)).toEqual(["cache.json"]);
  });

  test("rewrite drops entries absent from the current corpus (self-prune)", () => {
    const dir = mkdtempSync(join(tmpdir(), "adapters-cache-"));
    const file = join(dir, "cache.json");
    saveCache(file, { version: 1, model: "m", dims: 2, entries: { old: [1, 2], keep: [3, 4] } });
    // A build rewrites with only-current entries:
    saveCache(file, { version: 1, model: "m", dims: 2, entries: { keep: [3, 4] } });
    expect(Object.keys(loadCache(file)?.entries ?? {})).toEqual(["keep"]);
  });

  test("a simulated partial write does not corrupt the committed file", () => {
    const dir = mkdtempSync(join(tmpdir(), "adapters-cache-"));
    const file = join(dir, "cache.json");
    saveCache(file, { version: 1, model: "m", dims: 2, entries: { a: [1, 2] } });
    // Simulate a crash mid-write: a truncated .tmp exists but was never renamed.
    writeFileSync(`${file}.tmp`, '{"version":1,"model":"m","dims":2,"entr');
    expect(loadCache(file)?.entries.a).toEqual([1, 2]);
  });

  test("corrupt cache file is treated as empty (rebuild, no crash)", () => {
    const dir = mkdtempSync(join(tmpdir(), "adapters-cache-"));
    const file = join(dir, "cache.json");
    writeFileSync(file, "not json at all {{{");
    expect(loadCache(file)).toBeNull();
    writeFileSync(file, '"a bare string"');
    expect(loadCache(file)).toBeNull();
  });

  test("missing cache file loads as empty", () => {
    expect(loadCache("/nonexistent/path/cache.json")).toBeNull();
  });
});
