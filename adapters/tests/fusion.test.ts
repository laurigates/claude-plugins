/**
 * RRF tests (DESIGN §7.4): hand-computed 2-ranker fixture, 1-based ranks,
 * k = 60 asserted.
 */

import { describe, expect, test } from "bun:test";
import { FUSE_DEPTH, RRF_K, rrfFuse } from "../core/fusion.ts";

describe("rrfFuse", () => {
  test("k constant is the canonical 60", () => {
    expect(RRF_K).toBe(60);
    expect(FUSE_DEPTH).toBe(50);
  });

  test("hand-computed two-ranker fusion with a single-list doc", () => {
    // listA ranks: d1=1, d2=2, d3=3; listB ranks: d2=1, d4=2.
    // RRF (1-based, k=60):
    //   d2 = 1/62 + 1/61 = 0.032523...
    //   d1 = 1/61         = 0.016393...
    //   d4 = 1/62         = 0.016129...
    //   d3 = 1/63         = 0.015873...
    const fused = rrfFuse([
      [
        { id: "d1", score: 9.0 },
        { id: "d2", score: 5.0 },
        { id: "d3", score: 1.0 },
      ],
      [
        { id: "d2", score: 0.9 },
        { id: "d4", score: 0.2 },
      ],
    ]);
    expect(fused.map((f) => f.id)).toEqual(["d2", "d1", "d4", "d3"]);
    expect(fused[0]?.score).toBeCloseTo(1 / 62 + 1 / 61, 12);
    expect(fused[1]?.score).toBeCloseTo(1 / 61, 12);
    expect(fused[2]?.score).toBeCloseTo(1 / 62, 12);
    expect(fused[3]?.score).toBeCloseTo(1 / 63, 12);
  });

  test("absent-from-list contributes zero (no penalty term)", () => {
    const fused = rrfFuse([[{ id: "only", score: 1 }], []]);
    expect(fused).toEqual([{ id: "only", score: 1 / 61 }]);
  });

  test("only the top fuseDepth entries of each list participate", () => {
    const longList = Array.from({ length: 60 }, (_, i) => ({
      id: `d${i}`,
      score: 60 - i,
    }));
    const fused = rrfFuse([longList], 50);
    expect(fused).toHaveLength(50);
    expect(fused.find((f) => f.id === "d59")).toBeUndefined();
  });

  test("input scores do not influence fusion (rank-only)", () => {
    const a = rrfFuse([[{ id: "x", score: 1e9 }]]);
    const b = rrfFuse([[{ id: "x", score: 1e-9 }]]);
    expect(a[0]?.score).toBe(b[0]?.score);
  });
});
