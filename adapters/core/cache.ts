/**
 * XDG content-hash embedding cache (DESIGN §2.7; retrieval-design-inputs §5).
 *
 * - Entry key: sha256(CACHE_SCHEMA_VERSION \0 modelId \0 dims \0 prefixScheme
 *   \0 skillName \0 description) — content-addressed; edits, renames, model
 *   swaps, dimension changes, and prefix-scheme changes all auto-invalidate
 *   with no mtime logic.
 * - File: ${XDG_CACHE_HOME:-~/.cache}/claude-plugins-adapters/embeddings/
 *   <sha256(absRepoRoot).slice(0,16)>.json — XDG, never in-repo (in-repo
 *   caches dirty `git clean -x`, multiply per-worktree, and trip
 *   coworker-detection). Per-repo-path filename isolates checkouts.
 * - Write: atomic (.tmp + rename); each build rewrites with only-current
 *   entries (self-pruning, no LRU bookkeeping).
 */

import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

export const CACHE_SCHEMA_VERSION = "1";

export interface CacheFile {
  version: number;
  model: string;
  dims: number;
  entries: Record<string, number[]>;
}

export interface CacheKeyInput {
  model: string;
  dims: number;
  prefixScheme: string;
  skillName: string;
  description: string;
}

export function entryKey(input: CacheKeyInput): string {
  const material = [
    CACHE_SCHEMA_VERSION,
    input.model,
    String(input.dims),
    input.prefixScheme,
    input.skillName,
    input.description,
  ].join("\0");
  return createHash("sha256").update(material, "utf8").digest("hex");
}

export function defaultCacheDir(): string {
  const xdg = process.env.XDG_CACHE_HOME;
  const base = xdg && xdg.length > 0 ? xdg : join(homedir(), ".cache");
  return join(base, "claude-plugins-adapters", "embeddings");
}

export function cacheFilePath(repoRoot: string, cacheDir?: string): string {
  const dir = cacheDir ?? defaultCacheDir();
  const repoHash = createHash("sha256")
    .update(resolve(repoRoot), "utf8")
    .digest("hex")
    .slice(0, 16);
  return join(dir, `${repoHash}.json`);
}

/** Corrupt or missing cache files are treated as empty (rebuild, no crash). */
export function loadCache(filePath: string): CacheFile | null {
  let raw: string;
  try {
    raw = readFileSync(filePath, "utf8");
  } catch {
    return null;
  }
  try {
    const parsed = JSON.parse(raw) as CacheFile;
    if (
      typeof parsed !== "object" ||
      parsed === null ||
      typeof parsed.entries !== "object" ||
      parsed.entries === null
    ) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

/** Atomic write: serialize to <file>.tmp, then rename over the target. */
export function saveCache(filePath: string, cache: CacheFile): void {
  mkdirSync(dirname(filePath), { recursive: true });
  const tmpPath = `${filePath}.tmp`;
  writeFileSync(tmpPath, JSON.stringify(cache), "utf8");
  renameSync(tmpPath, filePath);
}
