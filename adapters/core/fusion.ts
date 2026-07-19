/**
 * Reciprocal Rank Fusion (DESIGN §2.6; Cormack, Clarke & Büttcher, SIGIR 2009).
 *
 * RRFscore(d) = Σ_{r ∈ rankers} 1/(k + rank_r(d)), ranks 1-based, documents
 * absent from a ranker's list contribute 0. k = 60 is the canonical constant.
 * Only the top-FUSE_DEPTH entries of each list participate. RRF is rank-only,
 * which is exactly why it fuses BM25 (unbounded scores) with cosine ([-1,1])
 * without normalization gymnastics.
 */

export const RRF_K = 60;
export const FUSE_DEPTH = 50;

export interface RankedItem {
  id: string;
  score: number;
}

export function rrfFuse(lists: RankedItem[][], fuseDepth: number = FUSE_DEPTH): RankedItem[] {
  const fused = new Map<string, number>();
  for (const list of lists) {
    const top = list.slice(0, fuseDepth);
    top.forEach((item, i) => {
      const rank = i + 1; // 1-based
      fused.set(item.id, (fused.get(item.id) ?? 0) + 1 / (RRF_K + rank));
    });
  }
  return [...fused.entries()]
    .map(([id, score]) => ({ id, score }))
    .sort((a, b) => b.score - a.score || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}
