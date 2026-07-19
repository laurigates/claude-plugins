/**
 * BM25 tests (DESIGN §7.1): hand-computed golden values, boundary cases, and
 * the committed rank_bm25 rank-order diff fixture.
 */

import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { BM25_B, BM25_K1, Bm25Index, tokenize } from "../core/bm25.ts";

describe("tokenize", () => {
  test("lowercases, splits on non-alphanumerics, drops empties", () => {
    expect(tokenize("Git-Commit: push_it 2x!")).toEqual(["git", "commit", "push", "it", "2x"]);
    expect(tokenize("")).toEqual([]);
    expect(tokenize("---")).toEqual([]);
  });
});

describe("hand-computed golden (3-doc toy corpus)", () => {
  // Corpus: d0 = "cat dog" (len 2), d1 = "cat cat" (len 2), d2 = "bird" (len 1).
  // N = 3, avgdl = 5/3, k1 = 1.2, b = 0.75.
  //
  // Lucene IDF: idf(t) = ln(1 + (N - df + 0.5)/(df + 0.5))
  //   idf(cat)  = ln(1 + 1.5/2.5) = ln(1.6)   = 0.47000362924573563
  //   idf(dog)  = ln(1 + 2.5/1.5) = ln(8/3)   = 0.9808292530117263
  //
  // Term score: idf · tf·(k1+1) / (tf + k1·(1 − b + b·|d|/avgdl))
  //   |d|=2: k1-norm = 1.2·(0.25 + 0.75·2/(5/3)) = 1.2·1.15 = 1.38
  //   q="cat", d0 (tf=1): 0.470004·(1·2.2)/(1+1.38)  = 0.4344571362775708
  //   q="cat", d1 (tf=2): 0.470004·(2·2.2)/(2+1.38)  = 0.6118390439885316
  //   q="dog", d0 (tf=1): 0.980829·2.2/2.38          = 0.9066488893385706
  //   q="bird", d2 (tf=1, |d|=1): norm=1.2·(0.25+0.45)=0.84; 0.980829·2.2/1.84
  //                                                  = 1.1727306286009773
  //   q="cat dog", d0: 0.4344571… + 0.9066488…       = 1.3411060256161413
  const index = new Bm25Index(["cat dog", "cat cat", "bird"]);

  test("constants are the Robertson & Zaragoza defaults", () => {
    expect(BM25_K1).toBe(1.2);
    expect(BM25_B).toBe(0.75);
  });

  test("q=cat scores both cat docs exactly", () => {
    const scored = index.score("cat");
    expect(scored).toHaveLength(2);
    expect(scored[0]?.docIdx).toBe(1);
    expect(scored[0]?.score).toBeCloseTo(0.6118390439885316, 9);
    expect(scored[1]?.docIdx).toBe(0);
    expect(scored[1]?.score).toBeCloseTo(0.4344571362775708, 9);
  });

  test("q=dog scores only d0", () => {
    const scored = index.score("dog");
    expect(scored).toHaveLength(1);
    expect(scored[0]?.docIdx).toBe(0);
    expect(scored[0]?.score).toBeCloseTo(0.9066488893385706, 9);
  });

  test("q=bird scores the short doc with its own length norm", () => {
    const scored = index.score("bird");
    expect(scored[0]?.docIdx).toBe(2);
    expect(scored[0]?.score).toBeCloseTo(1.1727306286009773, 9);
  });

  test("multi-term query accumulates per-term contributions", () => {
    const scored = index.score("cat dog");
    expect(scored[0]?.docIdx).toBe(0);
    expect(scored[0]?.score).toBeCloseTo(1.3411060256161413, 9);
  });
});

describe("boundary cases", () => {
  test("term in all docs keeps a non-negative score (Lucene IDF property)", () => {
    const index = new Bm25Index(["use git", "use jq", "use rg"]);
    for (const { score } of index.score("use")) {
      expect(score).toBeGreaterThanOrEqual(0);
    }
    expect(index.idf("use")).toBeGreaterThan(0);
  });

  test("empty query returns empty result", () => {
    const index = new Bm25Index(["cat dog"]);
    expect(index.score("")).toEqual([]);
    expect(index.score("!!!")).toEqual([]);
  });

  test("query term absent from corpus contributes nothing", () => {
    const index = new Bm25Index(["cat dog"]);
    expect(index.score("elephant")).toEqual([]);
  });

  test("single-doc corpus scores without dividing by zero", () => {
    const index = new Bm25Index(["lonely document"]);
    const scored = index.score("lonely");
    expect(scored).toHaveLength(1);
    expect(scored[0]?.score).toBeGreaterThan(0);
    expect(Number.isFinite(scored[0]?.score)).toBe(true);
  });
});

describe("rank_bm25 reference diff", () => {
  // The design called for rank-order equality between the SHIPPED (Lucene
  // IDF) scorer and rank_bm25 (epsilon-floored classic IDF). Empirically the
  // two IDF curves legitimately reorder close-scored multi-term documents
  // (4/10 realistic queries diverge in the tail), so exact cross-variant rank
  // equality is impossible by construction — recorded design deviation.
  //
  // The sound split, preserving the diff-test's verification intent:
  //  (1) scoring with rank_bm25's OWN IDF (the "classic-rank-bm25" test seam)
  //      must reproduce the reference ranking EXACTLY — this validates the
  //      whole shared machinery (tokenizer, postings, tf, length norm,
  //      accumulation, tie-breaking) against genuine rank_bm25 output;
  //  (2) the shipped Lucene-IDF path is pinned by the hand-computed goldens
  //      above, and must still agree with the reference on nonzero-membership
  //      and the top-1 result for every fixture query.
  interface Fixture {
    corpus: Array<{ id: string; text: string }>;
    cases: Array<{ query: string; expected_rank_order: number[] }>;
  }
  const fixture = JSON.parse(
    readFileSync(join(import.meta.dir, "fixtures", "bm25-reference.json"), "utf8"),
  ) as Fixture;
  const docs = fixture.corpus.map((d) => d.text);
  const classicIndex = new Bm25Index(docs, "classic-rank-bm25");
  const shippedIndex = new Bm25Index(docs);

  test.each(fixture.cases.map((c) => [c.query, c.expected_rank_order] as const))(
    "classic-IDF seam reproduces rank_bm25 exactly for %j",
    (query, expectedOrder) => {
      const ours = classicIndex.score(query).map((s) => s.docIdx);
      expect(ours).toEqual(expectedOrder);
    },
  );

  test.each(fixture.cases.map((c) => [c.query, c.expected_rank_order] as const))(
    "shipped Lucene-IDF ranking agrees on membership and top-1 for %j",
    (query, expectedOrder) => {
      const ours = shippedIndex.score(query).map((s) => s.docIdx);
      expect([...ours].sort((a, b) => a - b)).toEqual([...expectedOrder].sort((a, b) => a - b));
      expect(ours[0]).toBe(expectedOrder[0] as number);
    },
  );
});
