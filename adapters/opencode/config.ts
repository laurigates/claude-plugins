/**
 * OpenCode binding options — PluginOptions normalization + defaults
 * (DESIGN §4.1; schema = §3.4 fields minus `push`).
 *
 * Options arrive via the `[name, options]` tuple form in opencode.json's
 * `plugin` array. This module is pure (no @opencode-ai/plugin import) so
 * tests exercise it without the harness package in play.
 */

import { resolve } from "node:path";
import { DEFAULT_ENDPOINT, DEFAULT_K, DEFAULT_MODEL } from "../core/index.ts";

export interface OpencodeBindingConfig {
  /** Marketplace checkout root. Default: derived from import.meta (§4.1). */
  repoRoot: string;
  /** Push top-k (pins + ranked, deduped). Default DEFAULT_K. */
  k: number;
  /** Embedding endpoint. Default DEFAULT_ENDPOINT. */
  endpoint: string;
  /** Embedding model. Default DEFAULT_MODEL. */
  model: string;
  /** Skill ids ("plugin:skill") always injected first; unknown ids warn and skip. */
  pins: string[];
}

/**
 * The binding file lives inside the checkout it indexes
 * (adapters/opencode/config.ts → two dirs up), so the common case is
 * zero-config.
 */
export const DEFAULT_REPO_ROOT = resolve(import.meta.dir, "..", "..");

const KNOWN_KEYS = new Set(["repoRoot", "k", "endpoint", "model", "pins"]);

function stringOption(
  options: Record<string, unknown>,
  key: string,
  fallback: string,
  warnings: string[],
): string {
  const value = options[key];
  if (value === undefined) return fallback;
  if (typeof value === "string" && value.length > 0) return value;
  warnings.push(`option "${key}" must be a non-empty string; using default`);
  return fallback;
}

/**
 * Normalize the raw PluginOptions record into a full config. Invalid values
 * warn and fall back to the default — the binding never hard-fails on
 * config (pull-first, ADR risk mitigation).
 */
export function resolveOptions(options?: Record<string, unknown>): {
  config: OpencodeBindingConfig;
  warnings: string[];
} {
  const raw = options ?? {};
  const warnings: string[] = [];

  for (const key of Object.keys(raw)) {
    if (!KNOWN_KEYS.has(key)) warnings.push(`unknown option "${key}" ignored`);
  }

  let k = DEFAULT_K;
  if (raw.k !== undefined) {
    if (typeof raw.k === "number" && Number.isInteger(raw.k) && raw.k >= 1) {
      k = raw.k;
    } else {
      warnings.push(`option "k" must be an integer >= 1; using default ${DEFAULT_K}`);
    }
  }

  let pins: string[] = [];
  if (raw.pins !== undefined) {
    if (Array.isArray(raw.pins)) {
      for (const pin of raw.pins) {
        if (typeof pin === "string" && pin.length > 0) pins.push(pin);
        else warnings.push(`pin ${JSON.stringify(pin)} is not a skill id string; skipped`);
      }
    } else {
      warnings.push('option "pins" must be an array of skill ids; using none');
      pins = [];
    }
  }

  return {
    config: {
      repoRoot: stringOption(raw, "repoRoot", DEFAULT_REPO_ROOT, warnings),
      k,
      endpoint: stringOption(raw, "endpoint", DEFAULT_ENDPOINT, warnings),
      model: stringOption(raw, "model", DEFAULT_MODEL, warnings),
      pins,
    },
    warnings,
  };
}
