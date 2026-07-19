/**
 * Shared types for the skill-discovery core (ADR-0022, DESIGN §2.1).
 * Plain TS — no harness imports, no external dependencies (enforced by a
 * static import check in tests/indexer.test.ts).
 */

export interface SkillEntry {
  /** "<plugin>:<skill-dir>" — matches the repo's invocation naming. */
  id: string;
  /** Frontmatter name; fallback: skill directory basename. */
  name: string;
  /** Marketplace plugin name. */
  plugin: string;
  /** Frontmatter description (required; entry dropped if absent). */
  description: string;
  /** Absolute path to SKILL.md — the delivery handle (the model reads it). */
  path: string;
  /** Raw frontmatter value when present. */
  compatibility?: string;
  /** From the marketplace.json plugin entry. */
  category: string;
  /** From the marketplace.json plugin entry. */
  keywords: string[];
}

export interface SearchResult {
  id: string;
  name: string;
  description: string;
  path: string;
  score: number;
}

export interface SearchFilters {
  /** Restrict to these plugin names. */
  plugins?: string[];
  /** Restrict to one marketplace category. */
  category?: string;
  /** Drop specific skill ids (e.g. already-pinned ones). */
  excludeIds?: string[];
}

export type Ranker = (query: string, k: number) => Promise<Array<{ id: string; score: number }>>;

export interface IndexOptions {
  /** Marketplace checkout root. */
  repoRoot: string;
  /** Default "foreign": skip `compatibility: claude-code` entries. */
  target?: "foreign" | "claude-code";
  embed?: {
    /** Default "http://localhost:11434". */
    endpoint?: string;
    /** Default "nomic-embed-text". */
    model?: string;
    /** Default 768; Matryoshka knob (512/256/128/64) — one line of config, else YAGNI. */
    dimensions?: number;
    /** Force BM25-only (eval smoke mode). */
    disabled?: boolean;
  };
  /** Default: XDG recipe (core/cache.ts). */
  cacheDir?: string;
}

/**
 * Single source for the push top-k AND the eval hit@k; eval/tasks.json also
 * carries k and the runner asserts tasks.k === DEFAULT_K (DESIGN §5.1).
 */
export const DEFAULT_K = 5;
