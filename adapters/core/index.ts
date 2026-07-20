/**
 * Public surface of the skill-discovery core (DESIGN §2.1).
 */

export { BM25_B, BM25_K1, Bm25Index, tokenize } from "./bm25.ts";
export {
  CACHE_SCHEMA_VERSION,
  cacheFilePath,
  defaultCacheDir,
  entryKey,
  loadCache,
  saveCache,
} from "./cache.ts";
export {
  DEFAULT_DIMENSIONS,
  DEFAULT_ENDPOINT,
  DEFAULT_MODEL,
  DOCUMENT_PREFIX,
  EmbedUnavailableError,
  embedBatch,
  embedDocuments,
  embedQuery,
  PREFIX_SCHEME,
  probeEndpoint,
  QUERY_PREFIX,
} from "./embeddings.ts";
export { extractFrontmatterBlock, parseFrontmatter } from "./frontmatter.ts";
export { FUSE_DEPTH, RRF_K, rrfFuse } from "./fusion.ts";
export { documentText, scanSkills } from "./indexer.ts";
export {
  AVAILABLE_SKILLS_CLOSE,
  AVAILABLE_SKILLS_OPEN,
  estimateTokens,
  INJECTED_BLOCK_TRAILER,
  renderInjectedBlock,
  renderSkillEntry,
  renderToolResult,
  SEARCH_SKILLS_TOOL_DESCRIPTION,
  stripAvailableSkillsBlocks,
} from "./render.ts";
export { buildIndex, SkillIndex } from "./search.ts";
export type {
  IndexOptions,
  Ranker,
  SearchFilters,
  SearchResult,
  SkillEntry,
} from "./types.ts";
export { DEFAULT_K } from "./types.ts";
