/**
 * Ranker seam (DESIGN §5.4) — one seam serving meta-tests, ablation, and
 * diagnosis: hybrid | bm25Only | embeddingOnly | random(seed) | oracle |
 * nameSubstring | descriptionSubstring.
 *
 * `descriptionSubstring` is the two-sided complement to `nameSubstring`: a
 * degenerate ranker that must lose to `bm25Only`, proving prompts don't echo
 * description text any more than they echo names.
 */

import { tokenize } from "../core/bm25.ts";
import type { SkillIndex } from "../core/search.ts";
import type { Ranker, SkillEntry } from "../core/types.ts";

export interface EvalTask {
  id: string;
  prompt: string;
  expected_skills: string[];
  acceptable_skills: string[];
  negative: boolean;
  tags: string[];
  provenance: string;
}

export interface TaskSet {
  version: number;
  k: number;
  gate: {
    cutover_thresholds: Record<string, unknown> & { status?: string };
  };
  tasks: EvalTask[];
}

/** The hybrid (shipping) configuration: whatever mode the index resolved. */
export function hybridRanker(index: SkillIndex): Ranker {
  return async (query, k) => (await index.search(query, k)).map(({ id, score }) => ({ id, score }));
}

export function bm25OnlyRanker(index: SkillIndex): Ranker {
  return index.bm25Ranker();
}

/** Throws when the index is in bm25-only mode (no embedding side to ablate). */
export function embeddingOnlyRanker(index: SkillIndex): Ranker {
  const ranker = index.embeddingRanker();
  if (ranker === null) {
    throw new Error("embeddingOnly ranker requires a hybrid-mode index (run --with-embeddings)");
  }
  return ranker;
}

/** mulberry32 — small deterministic PRNG for the random ranker. */
function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashString(text: string): number {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * Deterministic per (seed, query): different tasks get independent
 * permutations, and the same seed reproduces the same run exactly.
 */
export function randomRanker(index: SkillIndex, seed: number): Ranker {
  return async (query, k) => {
    const rng = mulberry32((seed ^ hashString(query)) >>> 0);
    const ids = index.entries.map((e) => e.id);
    for (let i = ids.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      const a = ids[i] as string;
      ids[i] = ids[j] as string;
      ids[j] = a;
    }
    return ids.slice(0, k).map((id, i) => ({ id, score: 1 / (i + 1) }));
  };
}

/**
 * Perfect ranker: expected skills first, then acceptable, then arbitrary
 * fill. Proves the eval gate is achievable, not aspirational.
 */
export function oracleRanker(index: SkillIndex, tasks: EvalTask[]): Ranker {
  const byPrompt = new Map<string, EvalTask>(tasks.map((t) => [t.prompt, t]));
  return async (query, k) => {
    const task = byPrompt.get(query);
    const targets = task ? [...task.expected_skills, ...task.acceptable_skills] : [];
    const seen = new Set<string>();
    const ranked: Array<{ id: string; score: number }> = [];
    for (const id of targets) {
      if (seen.has(id) || ranked.length >= k) continue;
      seen.add(id);
      ranked.push({ id, score: 1 - ranked.length / (k + 1) });
    }
    for (const entry of index.entries) {
      if (ranked.length >= k) break;
      if (seen.has(entry.id)) continue;
      seen.add(entry.id);
      ranked.push({ id: entry.id, score: 1 - ranked.length / (k + 1) });
    }
    return ranked;
  };
}

function tokenOverlapRanker(index: SkillIndex, field: (e: SkillEntry) => string): Ranker {
  const docTokens = index.entries.map((e) => new Set(tokenize(field(e))));
  return async (query, k) => {
    const queryTokens = new Set(tokenize(query));
    const scored: Array<{ id: string; score: number }> = [];
    index.entries.forEach((entry, i) => {
      let overlap = 0;
      for (const token of docTokens[i] as Set<string>) {
        if (queryTokens.has(token)) overlap++;
      }
      if (overlap > 0) scored.push({ id: entry.id, score: overlap });
    });
    return scored.sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : 1)).slice(0, k);
  };
}

/** Degenerate: matches only skill-name tokens against the query text. */
export function nameSubstringRanker(index: SkillIndex): Ranker {
  return tokenOverlapRanker(index, (e) => e.name);
}

/** Degenerate: matches only description tokens against the query text. */
export function descriptionSubstringRanker(index: SkillIndex): Ranker {
  return tokenOverlapRanker(index, (e) => e.description);
}
