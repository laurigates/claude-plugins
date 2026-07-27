/**
 * skill-discovery.json load/merge for the pi binding (DESIGN §3.4).
 *
 * pi settings keys are a fixed set with no extension-config slot, so config
 * lives in a dedicated file: global `~/.pi/agent/skill-discovery.json`,
 * overridden key-by-key by project `.pi/skill-discovery.json` (same
 * precedence direction as pi's own settings). Missing file = all defaults —
 * the zero-config path works.
 *
 * Parsing is fail-safe per field (wrong-typed fields are ignored with a
 * warning; malformed JSON ignores the whole file with a warning) so a config
 * typo cannot take the session down — mirrors pi's own lenient resource
 * loading.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { DEFAULT_ENDPOINT, DEFAULT_K, DEFAULT_MODEL } from "../core/index.ts";

export const CONFIG_FILE_NAME = "skill-discovery.json";

/**
 * pi's config dir name, hardcoded deliberately: pi exports `CONFIG_DIR_NAME`
 * for this (pi-api.md §1), but it is a runtime *value* export and the DESIGN
 * §1.2 import-surface restriction (enforced by the static check in
 * tests/indexer.test.ts) allows only type-only imports from
 * `@earendil-works/pi-coding-agent`. If pi ever renames the dir, this one
 * constant is the only line to change.
 */
export const PI_CONFIG_DIR = ".pi";

export interface SkillDiscoveryConfig {
  /** Marketplace checkout root; default derived from the extension's own location. */
  repoRoot: string;
  /** Push top-k (also the search_skills default k). */
  k: number;
  /** Embedding endpoint. */
  endpoint: string;
  /** Embedding model. */
  model: string;
  /** Always-injected skill ids ("plugin:skill"); ranked results fill k after pins. */
  pins: string[];
  /** false = pull-only (debug/ablation). */
  push: boolean;
}

export function defaultConfig(defaultRepoRoot: string): SkillDiscoveryConfig {
  return {
    repoRoot: defaultRepoRoot,
    k: DEFAULT_K,
    endpoint: DEFAULT_ENDPOINT,
    model: DEFAULT_MODEL,
    pins: [],
    push: true,
  };
}

function isStringArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string");
}

/**
 * Parse one config file's JSON text into a partial config, fail-safe per
 * field. `source` labels warnings so a consumer can tell which file (global
 * vs project) carried the bad value.
 */
export function parseConfigText(
  text: string,
  source: string,
): { partial: Partial<SkillDiscoveryConfig>; warnings: string[] } {
  const warnings: string[] = [];
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { partial: {}, warnings: [`${source}: invalid JSON — file ignored (${message})`] };
  }
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    return { partial: {}, warnings: [`${source}: not a JSON object — file ignored`] };
  }

  const obj = raw as Record<string, unknown>;
  const partial: Partial<SkillDiscoveryConfig> = {};
  const ignore = (field: string, expected: string) => {
    warnings.push(`${source}: "${field}" is not ${expected} — field ignored`);
  };

  for (const [key, value] of Object.entries(obj)) {
    switch (key) {
      case "repoRoot":
      case "endpoint":
      case "model":
        if (typeof value === "string" && value.trim().length > 0) partial[key] = value;
        else ignore(key, "a non-empty string");
        break;
      case "k":
        if (typeof value === "number" && Number.isInteger(value) && value >= 1) partial.k = value;
        else ignore(key, "an integer >= 1");
        break;
      case "pins":
        if (isStringArray(value)) partial.pins = value;
        else ignore(key, "an array of strings");
        break;
      case "push":
        if (typeof value === "boolean") partial.push = value;
        else ignore(key, "a boolean");
        break;
      default:
        warnings.push(`${source}: unknown key "${key}" — ignored`);
    }
  }
  return { partial, warnings };
}

/** Key-by-key merge: later partials override earlier ones. */
export function mergeConfig(
  base: SkillDiscoveryConfig,
  ...overrides: Partial<SkillDiscoveryConfig>[]
): SkillDiscoveryConfig {
  const merged = { ...base };
  for (const override of overrides) {
    for (const [key, value] of Object.entries(override)) {
      if (value !== undefined) {
        (merged as Record<string, unknown>)[key] = value;
      }
    }
  }
  return merged;
}

export interface LoadedConfig {
  config: SkillDiscoveryConfig;
  warnings: string[];
}

/**
 * Load global ← project config. `globalPath`/`projectPath` are injectable so
 * tests never touch the real home directory; defaults follow pi's own
 * settings locations.
 */
export function loadConfig(opts: {
  defaultRepoRoot: string;
  globalPath?: string;
  projectPath?: string;
}): LoadedConfig {
  const globalPath = opts.globalPath ?? join(homedir(), PI_CONFIG_DIR, "agent", CONFIG_FILE_NAME);
  const projectPath = opts.projectPath ?? join(process.cwd(), PI_CONFIG_DIR, CONFIG_FILE_NAME);
  const warnings: string[] = [];

  const readPartial = (path: string): Partial<SkillDiscoveryConfig> => {
    if (!existsSync(path)) return {};
    let text: string;
    try {
      text = readFileSync(path, "utf8");
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      warnings.push(`${path}: unreadable — file ignored (${message})`);
      return {};
    }
    const { partial, warnings: fileWarnings } = parseConfigText(text, path);
    warnings.push(...fileWarnings);
    return partial;
  };

  const config = mergeConfig(
    defaultConfig(opts.defaultRepoRoot),
    readPartial(globalPath),
    readPartial(projectPath),
  );
  return { config, warnings };
}

/**
 * Resolve pin ids against the index entries, in pin order. Unknown pins warn
 * and are skipped; duplicates are deduped (DESIGN §3.4).
 */
export function resolvePins<T extends { id: string }>(
  pins: string[],
  entries: ReadonlyArray<T>,
): { resolved: T[]; warnings: string[] } {
  const byId = new Map(entries.map((entry) => [entry.id, entry]));
  const seen = new Set<string>();
  const resolved: T[] = [];
  const warnings: string[] = [];
  for (const pin of pins) {
    if (seen.has(pin)) continue;
    seen.add(pin);
    const entry = byId.get(pin);
    if (entry === undefined) {
      warnings.push(`pin "${pin}" not found in the skill index — skipped`);
      continue;
    }
    resolved.push(entry);
  }
  return { resolved, warnings };
}
