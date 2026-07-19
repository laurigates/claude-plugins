/**
 * Embeddings client + fallback tests (DESIGN §7.4): the full fallback matrix
 * (ECONNREFUSED, non-2xx, JSON error body, timeout) each degrading to
 * bm25-only with a functioning search(); prefix correctness asserted by a
 * mock /api/embed server; the hybrid happy path through the cache.
 */

import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdtempSync, readdirSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  EmbedUnavailableError,
  embedBatch,
  embedDocuments,
  embedQuery,
  probeEndpoint,
} from "../core/embeddings.ts";
import { buildIndex } from "../core/search.ts";

const FIXTURE_SRC = join(import.meta.dir, "fixtures", "mini-marketplace-src");
const DIMS = 8;

let fixtureRoot = "";
let cacheDir = "";

/** Deterministic per-input mock embedding: seeded by input length + char sum. */
function mockVector(input: string): number[] {
  let seed = input.length;
  for (let i = 0; i < input.length; i++) seed = (seed * 31 + input.charCodeAt(i)) >>> 0;
  return Array.from({ length: DIMS }, (_, j) => ((seed >> j) % 17) + 1);
}

interface MockState {
  receivedInputs: string[][];
  mode: "ok" | "http500" | "errorBody" | "stall";
}

const state: MockState = { receivedInputs: [], mode: "ok" };
let server: ReturnType<typeof Bun.serve>;
let endpoint = "";

beforeAll(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "mini-marketplace-embed-"));
  cpSync(FIXTURE_SRC, fixtureRoot, { recursive: true });
  for (const entry of readdirSync(fixtureRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const src = join(fixtureRoot, entry.name, "skilldirs");
    if (existsSync(src)) renameSync(src, join(fixtureRoot, entry.name, "skills"));
  }
  cacheDir = mkdtempSync(join(tmpdir(), "adapters-embed-cache-"));

  server = Bun.serve({
    port: 0,
    async fetch(req) {
      const url = new URL(req.url);
      if (url.pathname !== "/api/embed") return new Response("not found", { status: 404 });
      if (state.mode === "http500") return new Response("boom", { status: 500 });
      if (state.mode === "errorBody") {
        return Response.json({ error: "model not pulled" });
      }
      if (state.mode === "stall") {
        await new Promise((resolveSleep) => setTimeout(resolveSleep, 5_000));
      }
      const body = (await req.json()) as { model: string; input: string[] };
      state.receivedInputs.push(body.input);
      return Response.json({ model: body.model, embeddings: body.input.map(mockVector) });
    },
  });
  endpoint = `http://localhost:${server.port}`;
});

afterAll(() => {
  server?.stop(true);
});

const opts = () => ({ endpoint, model: "mock-embed", dimensions: DIMS });

describe("prefix correctness", () => {
  test("documents are sent with search_document: and queries with search_query:", async () => {
    state.mode = "ok";
    state.receivedInputs = [];
    await embedDocuments(["alpha skill", "beta skill"], opts());
    await embedQuery("do the thing", opts());
    expect(state.receivedInputs[0]).toEqual([
      "search_document: alpha skill",
      "search_document: beta skill",
    ]);
    expect(state.receivedInputs[1]).toEqual(["search_query: do the thing"]);
  });
});

describe("fallback matrix", () => {
  test("ECONNREFUSED (unbound port) throws EmbedUnavailableError", async () => {
    const dead = { endpoint: "http://127.0.0.1:9", model: "mock-embed" };
    expect(embedBatch(["x"], dead, 2_000)).rejects.toBeInstanceOf(EmbedUnavailableError);
    expect(await probeEndpoint(dead)).toBe(false);
  });

  test("non-2xx status throws EmbedUnavailableError", async () => {
    state.mode = "http500";
    expect(embedBatch(["x"], opts())).rejects.toBeInstanceOf(EmbedUnavailableError);
    expect(await probeEndpoint(opts())).toBe(false);
  });

  test("JSON error body (model not pulled) throws EmbedUnavailableError", async () => {
    state.mode = "errorBody";
    expect(embedBatch(["x"], opts())).rejects.toBeInstanceOf(EmbedUnavailableError);
    expect(await probeEndpoint(opts())).toBe(false);
  });

  test("timeout (stalled server) throws EmbedUnavailableError", async () => {
    state.mode = "stall";
    expect(embedBatch(["x"], opts(), 300)).rejects.toBeInstanceOf(EmbedUnavailableError);
    state.mode = "ok";
  });

  test("each failure mode yields mode bm25-only with a functioning search()", async () => {
    for (const brokenEndpoint of ["http://127.0.0.1:9"]) {
      const index = await buildIndex({
        repoRoot: fixtureRoot,
        embed: { endpoint: brokenEndpoint, model: "mock-embed", dimensions: DIMS },
        cacheDir,
      });
      expect(index.mode).toBe("bm25-only");
      expect(index.embeddingRanker()).toBeNull();
      const results = await index.search("commit staged changes", 3);
      expect(results.length).toBeGreaterThan(0);
      expect(results[0]?.id).toBe("alpha-plugin:normal-skill");
    }
    for (const mode of ["http500", "errorBody"] as const) {
      state.mode = mode;
      const index = await buildIndex({
        repoRoot: fixtureRoot,
        embed: { endpoint, model: "mock-embed", dimensions: DIMS },
        cacheDir,
      });
      expect(index.mode).toBe("bm25-only");
      const results = await index.search("commit staged changes", 3);
      expect(results.length).toBeGreaterThan(0);
    }
    state.mode = "ok";
  });

  test("embed.disabled forces bm25-only with zero network", async () => {
    state.receivedInputs = [];
    const index = await buildIndex({
      repoRoot: fixtureRoot,
      embed: { disabled: true },
      cacheDir,
    });
    expect(index.mode).toBe("bm25-only");
    expect(state.receivedInputs).toEqual([]);
  });
});

describe("hybrid happy path", () => {
  test("buildIndex probes, batch-embeds misses once, writes the cache, and fuses", async () => {
    state.mode = "ok";
    state.receivedInputs = [];
    const freshCache = mkdtempSync(join(tmpdir(), "adapters-embed-cache2-"));
    const index = await buildIndex({
      repoRoot: fixtureRoot,
      embed: { endpoint, model: "mock-embed", dimensions: DIMS },
      cacheDir: freshCache,
    });
    expect(index.mode).toBe("hybrid");
    expect(index.embeddingRanker()).not.toBeNull();
    // probe (1 input) + one batched corpus call (4 foreign entries)
    const batchCalls = state.receivedInputs.filter((batch) => batch.length > 1);
    expect(batchCalls).toHaveLength(1);
    expect(batchCalls[0]).toHaveLength(4);

    const results = await index.search("commit staged changes", 3);
    expect(results.length).toBeGreaterThan(0);
    // Hybrid mode returns RRF scores (rank-derived, bounded by lists/(k+1)).
    expect(results[0]?.score).toBeLessThan(1);

    // Second build: cache hit — no new multi-input batch call.
    const callsBefore = state.receivedInputs.length;
    const index2 = await buildIndex({
      repoRoot: fixtureRoot,
      embed: { endpoint, model: "mock-embed", dimensions: DIMS },
      cacheDir: freshCache,
    });
    expect(index2.mode).toBe("hybrid");
    const newBatches = state.receivedInputs.slice(callsBefore).filter((b) => b.length > 1);
    expect(newBatches).toEqual([]);
  });
});
