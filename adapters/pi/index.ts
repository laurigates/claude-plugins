/**
 * pi extension binding (#2090, DESIGN §3) over the shared discovery core.
 *
 * Default-exports the pi extension factory. Registers the `search_skills`
 * pull tool and a `before_agent_start` push handler that replaces pi's
 * native uncapped `<available_skills>` listing with pins + ranked top-k,
 * rendered by the same core/render.ts template the eval token accounting
 * uses.
 *
 * Runtime import surface is deliberately restricted (DESIGN §1.2, enforced
 * by the static import check in tests/indexer.test.ts): `typebox` (pi's
 * extension loader aliases it to its bundled 1.1.x copy — the local install
 * serves only tsc/bun test), TYPE-ONLY imports from
 * `@earendil-works/pi-coding-agent` (erased at transpile time; the live API
 * object is the factory parameter), `node:*`, and relative paths into
 * ../core/. The binding never uses `resources_discover` — contributed paths
 * would feed the uncapped native listing this binding exists to replace.
 */

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  AVAILABLE_SKILLS_CLOSE,
  AVAILABLE_SKILLS_OPEN,
  buildIndex,
  DEFAULT_K,
  INJECTED_BLOCK_TRAILER,
  renderInjectedBlock,
  renderToolResult,
  SEARCH_SKILLS_TOOL_DESCRIPTION,
  type SearchFilters,
  type SearchResult,
  type SkillIndex,
} from "../core/index.ts";
import { loadConfig, resolvePins, type SkillDiscoveryConfig } from "./config.ts";

const PI_DIR = dirname(fileURLToPath(import.meta.url));
/** The bun package root — where `bun install` must have been run. */
export const ADAPTERS_DIR = resolve(PI_DIR, "..");
/**
 * repoRoot default: the extension lives inside the checkout it indexes
 * (adapters/pi/index.ts → two dirs up), so the common case is zero-config.
 */
export const DEFAULT_REPO_ROOT = resolve(ADAPTERS_DIR, "..");

/** The stable structural marker pi appends the skills block before. */
export const CWD_MARKER = "Current working directory:";

/**
 * Remove the `<available_skills>…</available_skills>` block from a system
 * prompt (indexOf/slice, not regex — no backtracking surface). The 4-line
 * native preamble is left in place: tag boundaries are stable structural
 * markers, prose isn't, and a preamble with no block after it is harmless.
 *
 * - No block present (the expected consumer state): no-op.
 * - Malformed (open tag without close): input returned unchanged.
 * - Our own previously injected block (close tag followed by the trailer
 *   line) is removed including the trailer, making strip+inject idempotent.
 */
export function stripAvailableSkillsBlock(systemPrompt: string): string {
  const open = systemPrompt.indexOf(AVAILABLE_SKILLS_OPEN);
  if (open === -1) return systemPrompt;
  const closeStart = systemPrompt.indexOf(AVAILABLE_SKILLS_CLOSE, open);
  if (closeStart === -1) return systemPrompt;
  let end = closeStart + AVAILABLE_SKILLS_CLOSE.length;
  if (systemPrompt[end] === "\n") end += 1;
  if (systemPrompt.startsWith(INJECTED_BLOCK_TRAILER, end)) {
    end += INJECTED_BLOCK_TRAILER.length;
    if (systemPrompt[end] === "\n") end += 1;
  }
  return systemPrompt.slice(0, open) + systemPrompt.slice(end);
}

/**
 * Insert the rendered block where the native listing sat: before the
 * trailing "Current working directory:" line when locatable, else appended
 * at the end (DESIGN §3.3).
 */
export function injectSkillsBlock(systemPrompt: string, block: string): string {
  const markerIdx = systemPrompt.lastIndexOf(CWD_MARKER);
  if (markerIdx === -1) {
    return systemPrompt.endsWith("\n")
      ? `${systemPrompt}${block}\n`
      : `${systemPrompt}\n${block}\n`;
  }
  const lineStart = systemPrompt.lastIndexOf("\n", markerIdx) + 1;
  return `${systemPrompt.slice(0, lineStart)}${block}\n${systemPrompt.slice(lineStart)}`;
}

/**
 * The minimal index surface the binding consumes — lets tests stub it with
 * a small typed object instead of building a real index or running pi.
 * The real SkillIndex satisfies it structurally.
 */
export interface SkillSearchIndex {
  entries: ReadonlyArray<{ id: string; name: string; description: string; path: string }>;
  search(query: string, k?: number, filters?: SearchFilters): Promise<SearchResult[]>;
}

export interface PushContext {
  index: SkillSearchIndex;
  config: SkillDiscoveryConfig;
}

/**
 * Build the per-turn system prompt: strip the native listing, rank against
 * the user prompt, inject pins + ranked top-k (pins first, deduped via the
 * excludeIds filter, capped at k by the shared renderer).
 */
export async function buildTurnSystemPrompt(
  systemPrompt: string,
  userPrompt: string,
  ctx: PushContext,
): Promise<{ systemPrompt: string; warnings: string[] }> {
  const { resolved: pins, warnings } = resolvePins(ctx.config.pins, ctx.index.entries);
  const filters = pins.length > 0 ? { excludeIds: pins.map((pin) => pin.id) } : undefined;
  const ranked = await ctx.index.search(userPrompt, ctx.config.k, filters);
  const block = renderInjectedBlock(pins, ranked, ctx.config.k);
  return {
    systemPrompt: injectSkillsBlock(stripAvailableSkillsBlock(systemPrompt), block),
    warnings,
  };
}

/**
 * The before_agent_start push handler body (DESIGN §3.3). Takes only the
 * event fields it needs; `event.systemPromptOptions` is deliberately not
 * accepted — treating it as read-only by construction (mutations can leak
 * into future prompt rebuilds).
 */
export async function handleBeforeAgentStart(
  event: { prompt: string; systemPrompt: string },
  ctx: PushContext,
): Promise<{ systemPrompt: string } | undefined> {
  if (!ctx.config.push) return undefined;
  const { systemPrompt } = await buildTurnSystemPrompt(event.systemPrompt, event.prompt, ctx);
  return { systemPrompt };
}

/**
 * search_skills execute body: top-k results with the SKILL.md path to read.
 * `details: {}` is always present — the AgentToolResult type declares it
 * required while docs examples omit it, so the defensive choice is to always
 * supply it. Failures throw (pi's convention) rather than being encoded in
 * content.
 */
export async function runSearchSkills(
  index: Pick<SkillSearchIndex, "search">,
  params: { query: string; k?: number },
): Promise<{ content: Array<{ type: "text"; text: string }>; details: Record<string, never> }> {
  const results = await index.search(params.query, params.k ?? DEFAULT_K);
  return { content: [{ type: "text", text: renderToolResult(results) }], details: {} };
}

const MODULE_RESOLUTION_CODES = new Set([
  "ERR_MODULE_NOT_FOUND",
  "MODULE_NOT_FOUND",
  "ERR_PACKAGE_PATH_NOT_EXPORTED",
]);

/**
 * Rethrow helper for the fresh-clone failure mode: a module-resolution error
 * gets an explicit "run `bun install` in <checkout>/adapters" message so the
 * consumer gets a diagnosable error instead of a bare resolution stack (and
 * pi's silent-skip in headless pre-trust modes doesn't compound an
 * undiagnosed one). Non-resolution errors pass through unchanged.
 */
export function wrapModuleResolutionError(
  err: unknown,
  specifier: string,
  adaptersDir: string = ADAPTERS_DIR,
): unknown {
  const code =
    typeof err === "object" && err !== null && "code" in err
      ? String((err as { code: unknown }).code)
      : "";
  const message = err instanceof Error ? err.message : String(err);
  const isResolution =
    MODULE_RESOLUTION_CODES.has(code) || /cannot (find|resolve) (module|package)/i.test(message);
  if (!isResolution) return err;
  return new Error(
    `skill-discovery: failed to resolve "${specifier}" — run \`bun install\` in ${adaptersDir} (original: ${message})`,
    { cause: err },
  );
}

/**
 * The binding's first import-dependent action (DESIGN §3.1). At pi runtime
 * the extension loader aliases/virtualizes "typebox" to pi's bundled copy,
 * so this never resolves from adapters/node_modules under pi; a dynamic
 * import keeps the failure catchable so the bun-install hint above can fire
 * where a static top-level import would abort module load first.
 */
async function importTypebox(): Promise<typeof import("typebox")> {
  try {
    return await import("typebox");
  } catch (err) {
    throw wrapModuleResolutionError(err, "typebox");
  }
}

/**
 * pi extension factory. Heavy work (index build) happens on session_start,
 * not here — factories run in invocations that never start a session;
 * teardown in session_shutdown. The index is built lazily and cached across
 * turns; config is read once per session.
 */
const skillDiscovery = async (pi: ExtensionAPI): Promise<void> => {
  const { Type } = await importTypebox();

  let loaded: { config: SkillDiscoveryConfig; warnings: string[] } | null = null;
  let indexPromise: Promise<SkillIndex> | null = null;

  const getConfig = (): SkillDiscoveryConfig => {
    loaded ??= loadConfig({ defaultRepoRoot: DEFAULT_REPO_ROOT });
    return loaded.config;
  };

  const ensureIndex = (): Promise<SkillIndex> => {
    if (indexPromise === null) {
      const config = getConfig();
      indexPromise = buildIndex({
        repoRoot: config.repoRoot,
        embed: { endpoint: config.endpoint, model: config.model },
      });
    }
    return indexPromise;
  };

  pi.registerTool({
    name: "search_skills",
    label: "Search skills",
    description: SEARCH_SKILLS_TOOL_DESCRIPTION,
    parameters: Type.Object({
      query: Type.String({ description: "What you are trying to do, in plain words" }),
      k: Type.Optional(Type.Number({ minimum: 1, maximum: 20 })),
    }),
    promptSnippet: "search_skills: find task-specific skills by describing the task",
    // Bullets are appended flat with no tool-name prefix — each must name
    // the tool explicitly.
    promptGuidelines: [
      "Use search_skills when a task looks routine enough that a skill may exist for it.",
      "After search_skills returns, read the SKILL.md path of the best match before acting.",
    ],
    async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
      return runSearchSkills(await ensureIndex(), params);
    },
  });

  pi.on("session_start", async () => {
    await ensureIndex();
  });

  pi.on("session_shutdown", () => {
    loaded = null;
    indexPromise = null;
  });

  pi.on("before_agent_start", async (event) => {
    const config = getConfig();
    const index = await ensureIndex();
    return handleBeforeAgentStart(
      { prompt: event.prompt, systemPrompt: event.systemPrompt },
      { index, config },
    );
  });
};

export default skillDiscovery;
