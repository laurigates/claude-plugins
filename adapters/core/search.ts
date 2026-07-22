/**
 * SkillIndex — wires rankers + fusion + filters (DESIGN §2.1, §2.6).
 *
 * search() is async even though BM25 is sync: the query embedding is a
 * network call in hybrid mode; one signature for both modes keeps the
 * bindings mode-agnostic. Search never hard-fails on the embedding side —
 * per-query embedding failures degrade that query to BM25-only (ADR risk
 * mitigation).
 */

import { Bm25Index } from "./bm25.ts";
import { cacheFilePath, entryKey, loadCache, saveCache } from "./cache.ts";
import {
  BATCH_TIMEOUT_MS,
  DEFAULT_DIMENSIONS,
  DEFAULT_ENDPOINT,
  DEFAULT_MODEL,
  dotRow,
  type EmbedOptions,
  embedDocuments,
  embedQuery,
  normalizeVector,
  PREFIX_SCHEME,
  probeEndpoint,
  toNormalizedMatrix,
} from "./embeddings.ts";
import { FUSE_DEPTH, type RankedItem, rrfFuse } from "./fusion.ts";
import { documentText, scanSkills } from "./indexer.ts";
import {
  DEFAULT_K,
  type IndexOptions,
  type Ranker,
  type SearchFilters,
  type SearchResult,
  type SkillEntry,
} from "./types.ts";

export class SkillIndex {
  readonly entries: SkillEntry[];
  readonly mode: "hybrid" | "bm25-only";
  readonly warnings: string[];

  /**
   * Count of queries that fell back to BM25 because their embedding failed.
   *
   * The shipping path deliberately swallows per-query embedding failures, so
   * `mode` alone is NOT a sufficient signal that a run was actually hybrid:
   * an index can report `mode === "hybrid"` while every individual query
   * degraded. The eval raises a gate issue on any non-zero count, so a
   * threshold can never be frozen from a partly-BM25 run.
   */
  degradedQueries = 0;
  /** Message of the most recent per-query embedding failure (diagnosis aid). */
  lastDegradeReason: string | null = null;

  private readonly bm25: Bm25Index;
  private readonly idToIdx: Map<string, number>;
  private readonly embedOpts: EmbedOptions | null;
  /** Row-per-skill, L2-normalized at index time; null in bm25-only mode. */
  private readonly matrix: Float32Array | null;
  private readonly dims: number;

  constructor(
    entries: SkillEntry[],
    warnings: string[],
    mode: "hybrid" | "bm25-only",
    embedOpts: EmbedOptions | null,
    matrix: Float32Array | null,
    dims: number,
  ) {
    this.entries = entries;
    this.warnings = warnings;
    this.mode = mode;
    this.embedOpts = embedOpts;
    this.matrix = matrix;
    this.dims = dims;
    this.bm25 = new Bm25Index(entries.map((e) => documentText(e)));
    this.idToIdx = new Map(entries.map((e, i) => [e.id, i]));
  }

  /** Ranker seam — BM25 over the whole index (eval ablation entry point). */
  bm25Ranker(): Ranker {
    return async (query, k) =>
      this.bm25
        .score(query)
        .slice(0, k)
        .map(({ docIdx, score }) => ({ id: (this.entries[docIdx] as SkillEntry).id, score }));
  }

  /** Ranker seam — cosine over the whole index; null in bm25-only mode. */
  embeddingRanker(): Ranker | null {
    const { matrix, embedOpts } = this;
    if (matrix === null || embedOpts === null) return null;
    return async (query, k) => {
      const queryVec = normalizeVector(await embedQuery(query, embedOpts, BATCH_TIMEOUT_MS));
      if (queryVec.length !== this.dims) {
        throw new Error(`query embedding width ${queryVec.length} != index dims ${this.dims}`);
      }
      return this.cosineRank(queryVec)
        .slice(0, k)
        .map(({ docIdx, score }) => ({ id: (this.entries[docIdx] as SkillEntry).id, score }));
    };
  }

  private cosineRank(queryVec: Float32Array): Array<{ docIdx: number; score: number }> {
    const matrix = this.matrix;
    if (matrix === null) return [];
    const scored: Array<{ docIdx: number; score: number }> = [];
    for (let i = 0; i < this.entries.length; i++) {
      scored.push({ docIdx: i, score: dotRow(matrix, this.dims, i, queryVec) });
    }
    return scored.sort((a, b) => b.score - a.score || a.docIdx - b.docIdx);
  }

  private candidateIds(filters?: SearchFilters): Set<string> | null {
    if (!filters) return null;
    const excluded = new Set(filters.excludeIds ?? []);
    const plugins = filters.plugins ? new Set(filters.plugins) : null;
    const ids = new Set<string>();
    for (const entry of this.entries) {
      if (excluded.has(entry.id)) continue;
      if (plugins && !plugins.has(entry.plugin)) continue;
      if (filters.category && entry.category !== filters.category) continue;
      ids.add(entry.id);
    }
    return ids;
  }

  /**
   * Ranked search. In hybrid mode the score is the RRF fusion score
   * (rank-derived); in bm25-only mode it is the raw BM25 score.
   */
  async search(
    query: string,
    k: number = DEFAULT_K,
    filters?: SearchFilters,
  ): Promise<SearchResult[]> {
    const candidates = this.candidateIds(filters);
    const inCandidates = (id: string) => candidates === null || candidates.has(id);

    const bm25List: RankedItem[] = this.bm25
      .score(query)
      .map(({ docIdx, score }) => ({ id: (this.entries[docIdx] as SkillEntry).id, score }))
      .filter((item) => inCandidates(item.id));

    let fused: RankedItem[];
    if (this.mode === "hybrid" && this.matrix !== null && this.embedOpts !== null) {
      let embedList: RankedItem[] | null = null;
      try {
        const queryVec = normalizeVector(await embedQuery(query, this.embedOpts, BATCH_TIMEOUT_MS));
        if (queryVec.length !== this.dims) {
          throw new Error(`query embedding width ${queryVec.length} != index dims ${this.dims}`);
        }
        embedList = this.cosineRank(queryVec)
          .map(({ docIdx, score }) => ({ id: (this.entries[docIdx] as SkillEntry).id, score }))
          .filter((item) => inCandidates(item.id));
      } catch (error) {
        // Per-query embedding failure degrades this query to BM25-only.
        // Swallowed for the shipping path (search never hard-fails on the
        // embedding side) but counted so the eval can see it.
        this.degradedQueries++;
        this.lastDegradeReason = error instanceof Error ? error.message : String(error);
        embedList = null;
      }
      fused =
        embedList === null
          ? bm25List
          : rrfFuse([bm25List.slice(0, FUSE_DEPTH), embedList.slice(0, FUSE_DEPTH)]);
    } else {
      fused = bm25List;
    }

    return fused.slice(0, k).map((item) => {
      const entry = this.entries[this.idToIdx.get(item.id) as number] as SkillEntry;
      return {
        id: entry.id,
        name: entry.name,
        description: entry.description,
        path: entry.path,
        score: item.score,
      };
    });
  }
}

/**
 * Build the index: scan the marketplace, then (unless disabled) probe the
 * embedding endpoint and assemble the L2-normalized vector matrix through
 * the XDG content-hash cache. Any embedding failure yields mode "bm25-only".
 */
export async function buildIndex(opts: IndexOptions): Promise<SkillIndex> {
  const target = opts.target ?? "foreign";
  const { entries, warnings } = scanSkills(opts.repoRoot, target);

  const embedOpts: EmbedOptions = {
    endpoint: opts.embed?.endpoint ?? DEFAULT_ENDPOINT,
    model: opts.embed?.model ?? DEFAULT_MODEL,
    ...(opts.embed?.dimensions !== undefined ? { dimensions: opts.embed.dimensions } : {}),
  };
  const dims = opts.embed?.dimensions ?? DEFAULT_DIMENSIONS;

  if (opts.embed?.disabled) {
    return new SkillIndex(entries, warnings, "bm25-only", null, null, dims);
  }

  if (!(await probeEndpoint(embedOpts))) {
    return new SkillIndex(entries, warnings, "bm25-only", null, null, dims);
  }

  try {
    const filePath = cacheFilePath(opts.repoRoot, opts.cacheDir);
    const cached = loadCache(filePath);
    const cacheValid = cached !== null && cached.model === embedOpts.model && cached.dims === dims;
    const keys = entries.map((entry) =>
      entryKey({
        model: embedOpts.model,
        dims,
        prefixScheme: PREFIX_SCHEME,
        skillName: entry.name,
        description: entry.description,
      }),
    );

    const rows: Array<number[] | null> = keys.map((key) =>
      cacheValid ? ((cached as NonNullable<typeof cached>).entries[key] ?? null) : null,
    );
    const missIdx: number[] = [];
    rows.forEach((row, i) => {
      if (row === null) missIdx.push(i);
    });
    if (missIdx.length > 0) {
      const embedded = await embedDocuments(
        missIdx.map((i) => documentText(entries[i] as SkillEntry)),
        embedOpts,
      );
      missIdx.forEach((entryIdx, j) => {
        rows[entryIdx] = embedded[j] ?? null;
      });
    }
    if (rows.some((row) => row === null || row.length !== dims)) {
      // Includes the width guard: a cache entry or fresh row whose length
      // differs from the expected dims must not reach the truncating matrix
      // build — degrade to BM25-only instead.
      return new SkillIndex(entries, warnings, "bm25-only", null, null, dims);
    }

    // Rewrite with only-current entries (self-pruning).
    const nextEntries: Record<string, number[]> = {};
    keys.forEach((key, i) => {
      nextEntries[key] = rows[i] as number[];
    });
    saveCache(filePath, { version: 1, model: embedOpts.model, dims, entries: nextEntries });

    const matrix = toNormalizedMatrix(rows as number[][], dims);
    return new SkillIndex(entries, warnings, "hybrid", embedOpts, matrix, dims);
  } catch {
    // Batch-embed or cache failure after a successful probe: degrade.
    return new SkillIndex(entries, warnings, "bm25-only", null, null, dims);
  }
}
