/**
 * Per-query embedding degradation is observable (CUTOVER.md "Guards").
 *
 * The shipping path deliberately swallows per-query embedding failures so
 * search never hard-fails on the soft dependency. That makes `index.mode`
 * an INSUFFICIENT signal that a run was actually hybrid: the build-time
 * probe and the corpus batch can both succeed (→ mode "hybrid") while every
 * subsequent query fails and silently falls back to BM25. A cutover
 * threshold derived from such a run would be fiction.
 *
 * The stub below is the only deterministic way to reach that state: it
 * serves valid vectors for `search_document:` inputs (so probe + corpus
 * embedding succeed) and 500s for `search_query:` inputs (so every query
 * degrades). Asserting `mode === "hybrid"` AND `degradedQueries > 0` in the
 * same run is the proof that the counter carries information `mode` does not.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdtempSync, readdirSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DEFAULT_DIMENSIONS, DOCUMENT_PREFIX, QUERY_PREFIX } from "../core/embeddings.ts";
import { buildIndex } from "../core/search.ts";

const FIXTURE_SRC = join(import.meta.dir, "fixtures", "mini-marketplace-src");

/** Deterministic unit-ish vector; content-dependent so rows are not identical. */
function fakeVector(seed: number): number[] {
  return Array.from({ length: DEFAULT_DIMENSIONS }, (_, i) => Math.sin((i + 1) * (seed + 1)));
}

let fixtureRoot = "";
let cacheDir = "";
let server: ReturnType<typeof Bun.serve>;
let endpoint = "";
/** Flipped per test to choose whether query embedding succeeds. */
let failQueries = true;

beforeAll(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "degrade-marketplace-"));
  cpSync(FIXTURE_SRC, fixtureRoot, { recursive: true });
  for (const entry of readdirSync(fixtureRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const src = join(fixtureRoot, entry.name, "skilldirs");
    if (existsSync(src)) renameSync(src, join(fixtureRoot, entry.name, "skills"));
  }
  // Never touch the real XDG cache — a cached corpus would skip the batch.
  cacheDir = mkdtempSync(join(tmpdir(), "degrade-cache-"));

  server = Bun.serve({
    port: 0,
    async fetch(request) {
      const body = (await request.json()) as { input: string[] };
      const inputs = body.input;
      const isQuery = inputs.some((text) => text.startsWith(QUERY_PREFIX));
      if (isQuery && failQueries) {
        return new Response("upstream exploded", { status: 500 });
      }
      if (!inputs.every((t) => t.startsWith(DOCUMENT_PREFIX) || t.startsWith(QUERY_PREFIX))) {
        return new Response(JSON.stringify({ error: "missing task prefix" }), { status: 200 });
      }
      return Response.json({ embeddings: inputs.map((_, i) => fakeVector(i)) });
    },
  });
  endpoint = `http://localhost:${server.port}`;
});

afterAll(() => {
  server.stop(true);
});

describe("per-query embedding degradation", () => {
  test("mode stays 'hybrid' while every query degrades — mode alone is not a sufficient signal", async () => {
    failQueries = true;
    const index = await buildIndex({
      repoRoot: fixtureRoot,
      embed: { endpoint, dimensions: DEFAULT_DIMENSIONS },
      cacheDir,
    });

    // Document-side succeeded, so the index believes it is hybrid...
    expect(index.mode).toBe("hybrid");
    expect(index.degradedQueries).toBe(0);

    const results = await index.search("commit some work", 5);

    // ...but the query degraded, and search still returned BM25 results.
    expect(index.mode).toBe("hybrid");
    expect(index.degradedQueries).toBe(1);
    expect(index.lastDegradeReason).toContain("500");
    expect(results.length).toBeGreaterThan(0);

    await index.search("another query", 5);
    expect(index.degradedQueries).toBe(2);
  });

  test("a genuinely healthy endpoint leaves the counter at zero", async () => {
    failQueries = false;
    const index = await buildIndex({
      repoRoot: fixtureRoot,
      embed: { endpoint, dimensions: DEFAULT_DIMENSIONS },
      cacheDir,
    });

    expect(index.mode).toBe("hybrid");
    await index.search("commit some work", 5);
    await index.search("another query", 5);

    expect(index.degradedQueries).toBe(0);
    expect(index.lastDegradeReason).toBeNull();
  });
});
