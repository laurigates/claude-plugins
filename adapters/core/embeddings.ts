/**
 * Ollama /api/embed client (DESIGN §2.5; retrieval-design-inputs §1).
 *
 * - POST {endpoint}/api/embed with {"model", "input": string[]} — batch is
 *   native; response `embeddings: number[][]` in input order (always
 *   array-of-arrays). Never the legacy /api/embeddings (superseded).
 * - Task prefixes are mandatory for nomic-embed-text: corpus texts embed as
 *   `search_document: <text>`, queries as `search_query: <text>`. The prefix
 *   scheme string is part of the cache key so a prefix change invalidates.
 * - Fallback contract: fetch rejection (ECONNREFUSED etc.), non-2xx status,
 *   JSON `error` body (e.g. model not pulled), or AbortSignal.timeout expiry
 *   all signal "embeddings unavailable" — the index degrades to BM25-only.
 */

export const DEFAULT_ENDPOINT = "http://localhost:11434";
export const DEFAULT_MODEL = "nomic-embed-text";
export const DEFAULT_DIMENSIONS = 768;

/** Recorded in the cache key; changing prefixes invalidates cached vectors. */
export const PREFIX_SCHEME = "search_document:/search_query:";
export const DOCUMENT_PREFIX = "search_document: ";
export const QUERY_PREFIX = "search_query: ";

/** 3 s on the initial probe (embed one short string at build). */
export const PROBE_TIMEOUT_MS = 3_000;
/** 30 s on the batch call. */
export const BATCH_TIMEOUT_MS = 30_000;

export interface EmbedOptions {
  endpoint: string;
  model: string;
  dimensions?: number;
}

/** Thrown on any unavailability condition; callers degrade to BM25-only. */
export class EmbedUnavailableError extends Error {
  constructor(reason: string, cause?: unknown) {
    super(`embedding endpoint unavailable: ${reason}`);
    this.name = "EmbedUnavailableError";
    this.cause = cause;
  }
}

/**
 * Embed a batch of already-prefixed inputs. Throws EmbedUnavailableError on
 * every failure mode in the fallback contract; never returns partial output.
 */
export async function embedBatch(
  inputs: string[],
  opts: EmbedOptions,
  timeoutMs: number = BATCH_TIMEOUT_MS,
): Promise<number[][]> {
  if (inputs.length === 0) return [];
  const body: Record<string, unknown> = { model: opts.model, input: inputs };
  if (opts.dimensions !== undefined) body.dimensions = opts.dimensions;

  let response: Response;
  try {
    response = await fetch(new URL("/api/embed", opts.endpoint), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    throw new EmbedUnavailableError("fetch rejected (endpoint down or timeout)", err);
  }
  if (!response.ok) {
    throw new EmbedUnavailableError(`non-2xx status ${response.status}`);
  }
  let payload: unknown;
  try {
    payload = await response.json();
  } catch (err) {
    throw new EmbedUnavailableError("non-JSON response body", err);
  }
  if (typeof payload === "object" && payload !== null && "error" in payload) {
    throw new EmbedUnavailableError(`error body: ${String((payload as { error: unknown }).error)}`);
  }
  const embeddings = (payload as { embeddings?: unknown }).embeddings;
  if (
    !Array.isArray(embeddings) ||
    embeddings.length !== inputs.length ||
    !embeddings.every((row) => Array.isArray(row))
  ) {
    throw new EmbedUnavailableError("malformed embeddings payload");
  }
  return embeddings as number[][];
}

/** Embed corpus texts with the mandatory search_document prefix. */
export function embedDocuments(
  texts: string[],
  opts: EmbedOptions,
  timeoutMs: number = BATCH_TIMEOUT_MS,
): Promise<number[][]> {
  return embedBatch(
    texts.map((t) => `${DOCUMENT_PREFIX}${t}`),
    opts,
    timeoutMs,
  );
}

/** Embed a query with the mandatory search_query prefix. */
export async function embedQuery(
  query: string,
  opts: EmbedOptions,
  timeoutMs: number = BATCH_TIMEOUT_MS,
): Promise<number[]> {
  const rows = await embedBatch([`${QUERY_PREFIX}${query}`], opts, timeoutMs);
  const row = rows[0];
  if (!row) throw new EmbedUnavailableError("empty embeddings payload");
  return row;
}

/**
 * Build-time availability probe: embeds one short string with a short
 * timeout. Returns true when the endpoint answered correctly.
 */
export async function probeEndpoint(opts: EmbedOptions): Promise<boolean> {
  try {
    await embedBatch([`${DOCUMENT_PREFIX}probe`], opts, PROBE_TIMEOUT_MS);
    return true;
  } catch {
    return false;
  }
}

/** L2-normalize rows into one flat Float32Array (cosine = dot product). */
export function toNormalizedMatrix(rows: number[][], dims: number): Float32Array {
  const matrix = new Float32Array(rows.length * dims);
  rows.forEach((row, i) => {
    let normSq = 0;
    for (const v of row) normSq += v * v;
    const inv = normSq > 0 ? 1 / Math.sqrt(normSq) : 0;
    for (let j = 0; j < dims; j++) {
      matrix[i * dims + j] = (row[j] ?? 0) * inv;
    }
  });
  return matrix;
}

/** Dot product of a normalized query vector against row i of the matrix. */
export function dotRow(matrix: Float32Array, dims: number, i: number, query: Float32Array): number {
  let sum = 0;
  const base = i * dims;
  for (let j = 0; j < dims; j++) {
    sum += (matrix[base + j] ?? 0) * (query[j] ?? 0);
  }
  return sum;
}

/** L2-normalize a single vector into a Float32Array. */
export function normalizeVector(row: number[]): Float32Array {
  let normSq = 0;
  for (const v of row) normSq += v * v;
  const inv = normSq > 0 ? 1 / Math.sqrt(normSq) : 0;
  const out = new Float32Array(row.length);
  row.forEach((v, i) => {
    out[i] = v * inv;
  });
  return out;
}
