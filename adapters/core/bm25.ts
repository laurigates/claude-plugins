/**
 * DIY BM25 (DESIGN §2.4; retrieval-design-inputs §2).
 *
 * - Tokenizer: lowercase, split /[^a-z0-9]+/, drop empties. Hyphenated and
 *   namespaced names decompose ("git-commit" → "git", "commit"). No stemming
 *   (corpus of ~400 short docs).
 * - Score: Σ_t idf(t) · (tf·(k1+1)) / (tf + k1·(1 − b + b·|d|/avgdl)) with
 *   k1 = 1.2, b = 0.75 (Robertson & Zaragoza 2009 defaults).
 * - IDF: Lucene-style ln(1 + (N − df + 0.5)/(df + 0.5)) — non-negative,
 *   avoiding the classic-Okapi pathology on terms in more than half the
 *   corpus ("use" appears in nearly every description).
 */

export const BM25_K1 = 1.2;
export const BM25_B = 0.75;

export function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 0);
}

export interface Bm25Scored {
  /** Index of the document in the corpus passed to the constructor. */
  docIdx: number;
  score: number;
}

/**
 * The shipped IDF is "lucene" (always). "classic-rank-bm25" replicates
 * rank_bm25.BM25Okapi's epsilon-floored classic IDF and exists solely as the
 * diff-test seam (tests/bm25.test.ts): scoring with the reference's own IDF
 * is the only way to assert exact rank equality against it, because the two
 * IDF curves legitimately reorder close-scored multi-term documents.
 */
export type IdfVariant = "lucene" | "classic-rank-bm25";

const RANK_BM25_EPSILON = 0.25;

export class Bm25Index {
  private readonly postings = new Map<string, Map<number, number>>();
  private readonly docLengths: number[] = [];
  private readonly avgdl: number;
  private readonly n: number;
  private readonly idfVariant: IdfVariant;
  /** classic-rank-bm25 only: eps floor = RANK_BM25_EPSILON × mean raw IDF. */
  private readonly classicEps: number;

  constructor(docs: string[], idfVariant: IdfVariant = "lucene") {
    this.idfVariant = idfVariant;
    this.n = docs.length;
    let totalLen = 0;
    docs.forEach((doc, docIdx) => {
      const tokens = tokenize(doc);
      this.docLengths.push(tokens.length);
      totalLen += tokens.length;
      for (const token of tokens) {
        let perDoc = this.postings.get(token);
        if (!perDoc) {
          perDoc = new Map<number, number>();
          this.postings.set(token, perDoc);
        }
        perDoc.set(docIdx, (perDoc.get(docIdx) ?? 0) + 1);
      }
    });
    this.avgdl = this.n > 0 ? totalLen / this.n : 0;

    let classicEps = 0;
    if (idfVariant === "classic-rank-bm25" && this.postings.size > 0) {
      let idfSum = 0;
      for (const perDoc of this.postings.values()) {
        const df = perDoc.size;
        idfSum += Math.log(this.n - df + 0.5) - Math.log(df + 0.5);
      }
      classicEps = RANK_BM25_EPSILON * (idfSum / this.postings.size);
    }
    this.classicEps = classicEps;
  }

  /** Lucene-style non-negative IDF (shipped), or the classic diff-test seam. */
  idf(term: string): number {
    const df = this.postings.get(term)?.size ?? 0;
    if (this.idfVariant === "classic-rank-bm25") {
      if (df === 0) return 0;
      const raw = Math.log(this.n - df + 0.5) - Math.log(df + 0.5);
      return raw < 0 ? this.classicEps : raw;
    }
    return Math.log(1 + (this.n - df + 0.5) / (df + 0.5));
  }

  /**
   * Score every document with a non-zero score against the query, sorted by
   * descending score (ties broken by ascending docIdx for determinism).
   * Query terms are accumulated as given — duplicates count twice, matching
   * the rank_bm25 reference the diff test compares against.
   */
  score(query: string): Bm25Scored[] {
    const queryTokens = tokenize(query);
    if (queryTokens.length === 0) return [];
    const acc = new Map<number, number>();
    for (const token of queryTokens) {
      const perDoc = this.postings.get(token);
      if (!perDoc) continue;
      const idf = this.idf(token);
      for (const [docIdx, tf] of perDoc) {
        const dl = this.docLengths[docIdx] ?? 0;
        const norm = tf + BM25_K1 * (1 - BM25_B + (BM25_B * dl) / this.avgdl);
        const contribution = (idf * (tf * (BM25_K1 + 1))) / norm;
        acc.set(docIdx, (acc.get(docIdx) ?? 0) + contribution);
      }
    }
    return [...acc.entries()]
      .map(([docIdx, score]) => ({ docIdx, score }))
      .sort((a, b) => b.score - a.score || a.docIdx - b.docIdx);
  }
}
