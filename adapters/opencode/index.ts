/**
 * OpenCode binding for the skill-discovery core (ADR-0022, DESIGN §4, #2091).
 *
 * Consumer wiring (adapters/README.md): step 1 is always
 * `cd <checkout>/adapters && bun install` — this file resolves
 * @opencode-ai/plugin from adapters/node_modules (OpenCode's
 * background-install into config dirs does not cover a checkout-resident
 * plugin). Then, in opencode.json:
 *
 *   {
 *     "plugin": [["<path-to>/adapters/opencode/index.ts", { "k": 5, "pins": [] }]],
 *     "permission": { "skill": "deny" }
 *   }
 *
 * Native-listing suppression (§4.3): the PRIMARY mechanism is the
 * consumer-side `"permission": { "skill": "deny" }` line above — a
 * "*"-pattern deny makes SystemPrompt.skills() omit the whole
 * <available_skills> block and hides the native `skill` tool, on a stable
 * (non-experimental) config surface. (`"tools": { "skill": false }` is the
 * deprecated-surface alias, normalized into permission upstream.) The
 * system.transform filter below is only the DEFENSIVE secondary for
 * consumers who forgot the config line.
 *
 * Claude Code variables (#2662): a `tool.execute.before` hook rewrites `bash`
 * calls that reference `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PLUGIN_ROOT}` or
 * `${CLAUDE_SESSION_ID}`, using the resolver pi's binding shares
 * (core/claude-env.ts).
 */

import { basename, dirname, isAbsolute, resolve } from "node:path";
import type { Hooks, Plugin, ToolDefinition } from "@opencode-ai/plugin";
import {
  type ClaudeEnvState,
  createClaudeEnvState,
  deriveSessionId,
  realpathOrResolve,
  recordSkillDir,
  rewriteClaudeEnvCommand,
} from "../core/claude-env.ts";
import {
  AVAILABLE_SKILLS_OPEN,
  buildIndex,
  DEFAULT_K,
  renderInjectedBlock,
  renderToolResult,
  SEARCH_SKILLS_TOOL_DESCRIPTION,
  type SkillEntry,
  type SkillIndex,
  scanSkills,
  stripAvailableSkillsBlocks,
} from "../core/index.ts";
import { DEFAULT_REPO_ROOT, type OpencodeBindingConfig, resolveOptions } from "./config.ts";

const LOG_PREFIX = "[skill-discovery]";

/**
 * The one runtime dependency. Type-only imports above are erased at
 * transpile time, so a missing adapters/node_modules surfaces exactly here —
 * rethrown with an explicit remedy instead of a bare resolution stack
 * (DESIGN §4.1).
 */
export async function loadToolApi(
  importer: () => Promise<typeof import("@opencode-ai/plugin")> = () =>
    import("@opencode-ai/plugin"),
): Promise<typeof import("@opencode-ai/plugin").tool> {
  try {
    return (await importer()).tool;
  } catch (cause) {
    throw new Error(
      `${LOG_PREFIX} could not resolve @opencode-ai/plugin — run \`bun install\` in ${DEFAULT_REPO_ROOT}/adapters (populates adapters/node_modules; see adapters/README.md)`,
      { cause },
    );
  }
}

/** Pins are ids ("plugin:skill") resolved against the index; unknown pins warn and skip (§3.4). */
export function resolvePins(
  ids: string[],
  entries: SkillEntry[],
): { pins: SkillEntry[]; unknown: string[] } {
  const byId = new Map(entries.map((e) => [e.id, e]));
  const pins: SkillEntry[] = [];
  const unknown: string[] = [];
  for (const id of ids) {
    const entry = byId.get(id);
    if (entry) pins.push(entry);
    else unknown.push(id);
  }
  return { pins, unknown };
}

interface PluginState {
  index: SkillIndex;
  pins: SkillEntry[];
}

/** The harness name the unresolved-directory reason gives the model. */
const HARNESS = "OpenCode";

/**
 * tool.execute.before body for the Claude Code variables (core/claude-env.ts).
 * A `read` of a SKILL.md records its directory (OpenCode's read tool takes
 * `filePath` and resolves a relative one against the instance directory). A
 * `bash` call referencing a variable has `output.args.command` rewritten IN
 * PLACE: session/tools.ts (verified at v1.18.3) passes the same `args` object
 * to the trigger and then to `item.execute`, so reassigning `output.args` is
 * silently discarded. An unresolvable or ambiguous skill directory THROWS:
 * the trigger runs the hook inside `Effect.promise`, so the rejection fails
 * the tool call before it runs and the model receives the reason — the same
 * path OpenCode's documented env-protection example and the generated hook
 * plugins (scripts/generate-opencode-hook-plugins.py) use to block a call.
 *
 * Unlike pi, OpenCode keeps the mutated `args` as the tool part's input, so
 * the prepended `export` line is visible in the transcript. OpenCode's shell
 * permission scan collects only tree-sitter `command` nodes, and `export …`
 * parses as a `declaration_command`, so the line adds no permission pattern.
 */
export function handleClaudeEnvToolExecute(
  input: { tool: string; sessionID: string },
  output: { args: Record<string, unknown> },
  state: ClaudeEnvState,
  indexedDirs: () => readonly string[],
  directory: string,
  exists?: (path: string) => boolean,
  realpath: (path: string) => string = realpathOrResolve,
): void {
  const args = output.args;
  if (input.tool === "read") {
    const filePath = args?.filePath;
    if (typeof filePath === "string" && basename(filePath) === "SKILL.md") {
      const absolute = isAbsolute(filePath) ? filePath : resolve(directory, filePath);
      recordSkillDir(state.readDirs, dirname(absolute));
    }
    return;
  }
  if (input.tool !== "bash") return;
  const command = args?.command;
  if (typeof command !== "string") return;
  const rewrite = rewriteClaudeEnvCommand(
    command,
    state,
    indexedDirs,
    { sessionId: deriveSessionId(input.sessionID) },
    HARNESS,
    exists,
    realpath,
  );
  if (rewrite === undefined) return;
  if ("reason" in rewrite) throw new Error(rewrite.reason);
  args.command = rewrite.command;
}

/**
 * Named Plugin export (§4.1): OpenCode resolves the path-like spec relative
 * to the declaring config file and calls every exported Plugin-typed const.
 */
export const SkillDiscoveryPlugin: Plugin = async (input, options) => {
  const { config, warnings } = resolveOptions(options);
  for (const warning of warnings) console.warn(`${LOG_PREFIX} ${warning}`);

  const tool = await loadToolApi();

  // Heavy work (index build) is lazy and memoized: the factory returns
  // fast, and a build failure surfaces on first use, not at plugin load.
  let statePromise: Promise<PluginState> | null = null;
  const getState = (): Promise<PluginState> => {
    statePromise ??= (async () => {
      const index = await buildIndex({
        repoRoot: config.repoRoot,
        embed: { endpoint: config.endpoint, model: config.model },
      });
      const { pins, unknown } = resolvePins(config.pins, index.entries);
      for (const id of unknown) console.warn(`${LOG_PREFIX} unknown pin "${id}" skipped`);
      return { index, pins };
    })();
    return statePromise;
  };

  // §4.4 informational (non-gating) version probe: a user debugging
  // "why no injected block" gets an answer without us gating behavior on
  // semver — unknown hook keys are silently never called on older
  // OpenCode versions, so declaring them below is a harmless no-op there.
  void fetch(new URL("/global/health", input.serverUrl))
    .then(async (res) => {
      const body = (await res.json()) as { healthy?: boolean; version?: string };
      console.log(
        `${LOG_PREFIX} opencode ${body.version ?? "unknown version"} at ${input.serverUrl}; ` +
          "push injection rides experimental.chat.system.transform (a silent no-op on versions without the hook — the binding is pull-first)",
      );
    })
    .catch(() => {
      // Health endpoint unreachable: purely informational, never gate.
    });

  // Ranking input for the push channel (§4.4 recorded defensive choice):
  // system.transform receives only {sessionID?, model} — no user prompt —
  // so the latest user-message text is captured in messages.transform
  // (which sees the full message array) into this closure slot.
  let latestUserMessage: string | null = null;
  let pushFailureLogged = false;

  // One plugin instance serves every session of an OpenCode instance, so the
  // read history behind ${CLAUDE_SKILL_DIR} is keyed by session. The indexed
  // skill directories (scan only, no embeddings) are built on first need.
  const claudeEnvBySession = new Map<string, ClaudeEnvState>();
  let indexedDirs: string[] | null = null;
  const claudeEnvFor = (sessionID: string): ClaudeEnvState => {
    let state = claudeEnvBySession.get(sessionID);
    if (state === undefined) {
      state = createClaudeEnvState();
      claudeEnvBySession.set(sessionID, state);
    }
    return state;
  };

  const hooks: Hooks = {
    tool: {
      search_skills: tool({
        description: SEARCH_SKILLS_TOOL_DESCRIPTION,
        args: {
          query: tool.schema.string().describe("What you are trying to do, in plain words"),
          k: tool.schema.number().int().min(1).max(20).optional(),
        },
        async execute(args, _ctx) {
          const { index } = await getState();
          const results = await index.search(args.query, args.k ?? DEFAULT_K);
          return renderToolResult(results);
        },
      }) satisfies ToolDefinition,
    },

    "tool.execute.before": async (toolInput, output) => {
      handleClaudeEnvToolExecute(
        toolInput,
        output,
        claudeEnvFor(toolInput.sessionID),
        () => {
          indexedDirs ??= scanSkills(config.repoRoot).entries.map((entry) => dirname(entry.path));
          return indexedDirs;
        },
        input.directory,
      );
    },

    "experimental.chat.messages.transform": async (_input, output) => {
      // One-turn-stale caveat (§4.4): if, on some version, system.transform
      // for a request fires before this hook has seen that request's
      // message, the injection ranks against the PREVIOUS turn's message —
      // pins are unaffected and search_skills is the recourse. Accepted
      // over message-array injection, which would mutate persisted
      // conversation shape with an input that carries no sessionID.
      for (let i = output.messages.length - 1; i >= 0; i--) {
        const message = output.messages[i];
        if (message?.info.role !== "user") continue;
        // Skip both upstream part flags: `synthetic` (OpenCode-generated
        // text) and `ignored` (text OpenCode excludes from the request) —
        // neither should drive the push ranking.
        const text = message.parts
          .flatMap((part) =>
            part.type === "text" && !part.synthetic && !part.ignored ? [part.text] : [],
          )
          .join("\n")
          .trim();
        if (text.length > 0) latestUserMessage = text;
        break;
      }
    },

    // Declared unconditionally (§4.4): Plugin.trigger only calls hook names
    // it knows, so on older OpenCode versions this is silently never
    // invoked and the binding degrades to pull-only.
    "experimental.chat.system.transform": async (_input, output) => {
      // In-place mutation is the upstream contract: request.ts (verified at
      // v1.18.3 and dev) reads the SAME local `system` array after the
      // trigger — Plugin.trigger does no copy-back, so reassigning
      // `output.system` is silently discarded. Every change below mutates
      // the original array object (index writes / length=0 + push).
      //
      // Defensive strip (§4.3 secondary): remove the native
      // <available_skills>…</available_skills> span by SUBSTRING, keeping
      // the rest of the element — upstream pre-joins the entire system
      // prompt into ONE element before this hook fires, so dropping whole
      // matching elements would delete the whole prompt. Elements that
      // were nothing but the block are removed. v2-rewrite note:
      // SkillGuidance drops <location> from the native block but keeps the
      // <available_skills> tag this scan matches — re-check at cutover
      // (#2094).
      const kept: string[] = [];
      for (const element of output.system) {
        if (!element.includes(AVAILABLE_SKILLS_OPEN)) {
          kept.push(element);
          continue;
        }
        const stripped = stripAvailableSkillsBlocks(element);
        if (stripped.trim().length > 0) kept.push(stripped);
      }
      output.system.length = 0;
      output.system.push(...kept);

      try {
        const { index, pins } = await getState();
        const ranked =
          latestUserMessage === null
            ? [] // first turn with no captured message: inject pins only
            : await index.search(latestUserMessage, config.k, {
                excludeIds: pins.map((pin) => pin.id),
              });
        // Nothing selected (no pins, no captured message or no ranked
        // hits): inject nothing — an empty <available_skills> block with
        // the "listed above" trailer would be self-contradictory, and
        // search_skills remains the routing surface.
        if (pins.length + ranked.length > 0) {
          output.system.push(renderInjectedBlock(pins, ranked, config.k));
        }
      } catch (error) {
        // Push is best-effort by design; the pull tool remains the recourse.
        if (!pushFailureLogged) {
          pushFailureLogged = true;
          console.warn(`${LOG_PREFIX} push injection failed: ${String(error)}`);
        }
      }
    },
  };
  return hooks;
};

export type { OpencodeBindingConfig };
