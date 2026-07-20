/**
 * pi binding tests (DESIGN §7.5) — pure helpers only, no live pi. The
 * ExtensionAPI surface is mocked with a minimal typed stub; harness-level
 * behavior (jiti loading, trust gating, prompt emission) is out of scope.
 */

import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI, ToolDefinition } from "@earendil-works/pi-coding-agent";
import type { SearchFilters, SearchResult } from "../core/index.ts";
import {
  AVAILABLE_SKILLS_CLOSE,
  AVAILABLE_SKILLS_OPEN,
  DEFAULT_ENDPOINT,
  DEFAULT_K,
  DEFAULT_MODEL,
  INJECTED_BLOCK_TRAILER,
} from "../core/index.ts";
import {
  CONFIG_FILE_NAME,
  defaultConfig,
  loadConfig,
  mergeConfig,
  parseConfigText,
  resolvePins,
} from "../pi/config.ts";
import skillDiscovery, {
  BM25_ONLY_MODE_WARNING,
  buildTurnSystemPrompt,
  CWD_MARKER,
  DEFAULT_REPO_ROOT,
  emitWarningsOnce,
  handleBeforeAgentStart,
  injectSkillsBlock,
  runSearchSkills,
  type SkillSearchIndex,
  stripAvailableSkillsBlock,
  wrapModuleResolutionError,
} from "../pi/index.ts";

// --- fixtures -------------------------------------------------------------

const NATIVE_BLOCK = [
  AVAILABLE_SKILLS_OPEN,
  "  <skill><name>foo</name><description>Foo skill</description><location>/abs/foo/SKILL.md</location></skill>",
  AVAILABLE_SKILLS_CLOSE,
].join("\n");

const PREAMBLE = "You are pi.\n\nSkills may be listed below.\n";
const PROMPT_WITH_BLOCK = `${PREAMBLE}${NATIVE_BLOCK}\n${CWD_MARKER} /work/dir\n`;
const PROMPT_WITHOUT_BLOCK = `${PREAMBLE}${CWD_MARKER} /work/dir\n`;
const PROMPT_NO_MARKER = "You are pi. No cwd line here.";

const entry = (id: string) => ({
  id,
  name: id.split(":")[1] as string,
  description: `Description for ${id}`,
  path: `/abs/${id.replace(":", "/")}/SKILL.md`,
});

const ENTRIES = [entry("a:pin"), entry("b:one"), entry("c:two"), entry("d:three")];

function stubIndex(overrides?: Partial<SkillSearchIndex>): SkillSearchIndex & {
  calls: Array<{ query: string; k: number | undefined; filters: SearchFilters | undefined }>;
} {
  const calls: Array<{
    query: string;
    k: number | undefined;
    filters: SearchFilters | undefined;
  }> = [];
  return {
    calls,
    entries: ENTRIES,
    async search(query, k, filters) {
      calls.push({ query, k, filters });
      const excluded = new Set(filters?.excludeIds ?? []);
      return ENTRIES.filter((e) => !excluded.has(e.id))
        .slice(0, k ?? DEFAULT_K)
        .map((e, i) => ({ ...e, score: 1 / (i + 1) }) satisfies SearchResult);
    },
    ...overrides,
  };
}

// --- strip ----------------------------------------------------------------

describe("stripAvailableSkillsBlock", () => {
  test("removes the native block, keeping preamble and cwd line", () => {
    const stripped = stripAvailableSkillsBlock(PROMPT_WITH_BLOCK);
    expect(stripped).not.toContain(AVAILABLE_SKILLS_OPEN);
    expect(stripped).not.toContain(AVAILABLE_SKILLS_CLOSE);
    expect(stripped).toContain("Skills may be listed below.");
    expect(stripped).toContain(`${CWD_MARKER} /work/dir`);
    expect(stripped).toBe(PROMPT_WITHOUT_BLOCK);
  });

  test("block-absent prompt passes through unchanged", () => {
    expect(stripAvailableSkillsBlock(PROMPT_WITHOUT_BLOCK)).toBe(PROMPT_WITHOUT_BLOCK);
  });

  test("malformed unclosed block returns the input unchanged", () => {
    const malformed = `${PREAMBLE}${AVAILABLE_SKILLS_OPEN}\n  <skill>oops\n${CWD_MARKER} /w\n`;
    expect(stripAvailableSkillsBlock(malformed)).toBe(malformed);
  });

  test("removes a previously injected block including the trailer line", () => {
    const block = `${AVAILABLE_SKILLS_OPEN}\n${AVAILABLE_SKILLS_CLOSE}\n${INJECTED_BLOCK_TRAILER}`;
    const injected = injectSkillsBlock(PROMPT_WITHOUT_BLOCK, block);
    expect(stripAvailableSkillsBlock(injected)).toBe(PROMPT_WITHOUT_BLOCK);
  });
});

// --- inject ---------------------------------------------------------------

describe("injectSkillsBlock", () => {
  const BLOCK = `${AVAILABLE_SKILLS_OPEN}\n${AVAILABLE_SKILLS_CLOSE}\n${INJECTED_BLOCK_TRAILER}`;

  test("inserts immediately before the Current working directory line", () => {
    const result = injectSkillsBlock(PROMPT_WITHOUT_BLOCK, BLOCK);
    const lines = result.split("\n");
    const cwdIdx = lines.findIndex((l) => l.startsWith(CWD_MARKER));
    expect(cwdIdx).toBeGreaterThan(0);
    expect(lines[cwdIdx - 1]).toBe(INJECTED_BLOCK_TRAILER);
    expect(lines).toContain(AVAILABLE_SKILLS_OPEN);
  });

  test("appends at the end when no marker is present", () => {
    const result = injectSkillsBlock(PROMPT_NO_MARKER, BLOCK);
    expect(result.startsWith(PROMPT_NO_MARKER)).toBe(true);
    expect(result.trimEnd().endsWith(INJECTED_BLOCK_TRAILER)).toBe(true);
  });

  test("strip+inject is idempotent on prompts with and without the block", () => {
    const edit = (prompt: string) => injectSkillsBlock(stripAvailableSkillsBlock(prompt), BLOCK);
    for (const prompt of [PROMPT_WITH_BLOCK, PROMPT_WITHOUT_BLOCK, PROMPT_NO_MARKER]) {
      const once = edit(prompt);
      expect(edit(once)).toBe(once);
    }
  });
});

// --- config ---------------------------------------------------------------

describe("pi config", () => {
  test("defaults", () => {
    const config = defaultConfig("/repo");
    expect(config).toEqual({
      repoRoot: "/repo",
      k: DEFAULT_K,
      endpoint: DEFAULT_ENDPOINT,
      model: DEFAULT_MODEL,
      pins: [],
      push: true,
    });
  });

  test("parseConfigText accepts valid fields and warns on bad ones", () => {
    const { partial, warnings } = parseConfigText(
      JSON.stringify({ k: 3, pins: ["a:pin"], push: false, endpoint: 7, unknownKey: true }),
      "test.json",
    );
    expect(partial).toEqual({ k: 3, pins: ["a:pin"], push: false });
    expect(warnings.some((w) => w.includes('"endpoint"'))).toBe(true);
    expect(warnings.some((w) => w.includes("unknownKey"))).toBe(true);
  });

  test("parseConfigText ignores a malformed file with a warning", () => {
    const { partial, warnings } = parseConfigText("{not json", "bad.json");
    expect(partial).toEqual({});
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toContain("invalid JSON");
  });

  test("non-integer or out-of-range k is ignored", () => {
    expect(parseConfigText(JSON.stringify({ k: 0 }), "s").partial).toEqual({});
    expect(parseConfigText(JSON.stringify({ k: 2.5 }), "s").partial).toEqual({});
  });

  test("mergeConfig: project overrides global key-by-key", () => {
    const merged = mergeConfig(
      defaultConfig("/repo"),
      { k: 3, pins: ["a:pin"] }, // global
      { k: 7 }, // project
    );
    expect(merged.k).toBe(7);
    expect(merged.pins).toEqual(["a:pin"]); // untouched by project
    expect(merged.repoRoot).toBe("/repo");
  });

  test("loadConfig: missing files yield all defaults", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-config-"));
    const { config, warnings } = loadConfig({
      defaultRepoRoot: "/repo",
      globalPath: join(dir, "absent-global.json"),
      projectPath: join(dir, "absent-project.json"),
    });
    expect(config).toEqual(defaultConfig("/repo"));
    expect(warnings).toEqual([]);
  });

  test("loadConfig: global <- project precedence over real files", () => {
    const dir = mkdtempSync(join(tmpdir(), "pi-config-"));
    const globalPath = join(dir, "global", CONFIG_FILE_NAME);
    const projectPath = join(dir, "project", CONFIG_FILE_NAME);
    mkdirSync(join(dir, "global"));
    mkdirSync(join(dir, "project"));
    writeFileSync(globalPath, JSON.stringify({ k: 3, pins: ["a:pin"], model: "custom-model" }));
    writeFileSync(projectPath, JSON.stringify({ k: 7, push: false }));
    const { config, warnings } = loadConfig({
      defaultRepoRoot: "/repo",
      globalPath,
      projectPath,
    });
    expect(config.k).toBe(7);
    expect(config.push).toBe(false);
    expect(config.pins).toEqual(["a:pin"]);
    expect(config.model).toBe("custom-model");
    expect(config.endpoint).toBe(DEFAULT_ENDPOINT);
    expect(warnings).toEqual([]);
  });
});

// --- pins -----------------------------------------------------------------

describe("resolvePins", () => {
  test("resolves known pins in order, warns and skips unknown, dedupes", () => {
    const { resolved, warnings } = resolvePins(
      ["c:two", "nope:missing", "a:pin", "c:two"],
      ENTRIES,
    );
    expect(resolved.map((r) => r.id)).toEqual(["c:two", "a:pin"]);
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toContain('"nope:missing"');
  });
});

// --- search_skills tool result --------------------------------------------

describe("runSearchSkills", () => {
  test("result shape: text content plus always-present details: {}", async () => {
    const index = stubIndex();
    const result = await runSearchSkills(index, { query: "commit my work" });
    expect(result.details).toEqual({});
    expect(result.content).toHaveLength(1);
    expect(result.content[0]?.type).toBe("text");
    expect(result.content[0]?.text).toContain("a:pin");
    expect(result.content[0]?.text).toContain("read: /abs/a/pin/SKILL.md");
    expect(index.calls[0]?.k).toBe(DEFAULT_K);
  });

  test("explicit k is passed through", async () => {
    const index = stubIndex();
    await runSearchSkills(index, { query: "q", k: 2 });
    expect(index.calls[0]?.k).toBe(2);
  });

  test("configured default k (config.k) is used when params.k is absent", async () => {
    const index = stubIndex();
    await runSearchSkills(index, { query: "q" }, 9);
    expect(index.calls[0]?.k).toBe(9);
  });

  test("explicit params.k wins over the configured default", async () => {
    const index = stubIndex();
    await runSearchSkills(index, { query: "q", k: 2 }, 9);
    expect(index.calls[0]?.k).toBe(2);
  });

  test("failures propagate as thrown errors, never encoded in content", async () => {
    const failing: Pick<SkillSearchIndex, "search"> = {
      search: async () => {
        throw new Error("index unavailable");
      },
    };
    await expect(runSearchSkills(failing, { query: "q" })).rejects.toThrow("index unavailable");
  });
});

// --- push channel ---------------------------------------------------------

describe("buildTurnSystemPrompt / handleBeforeAgentStart", () => {
  const config = { ...defaultConfig("/repo"), k: 3, pins: ["c:two"] };

  test("pins first, ranked fill k, native block replaced in place", async () => {
    const index = stubIndex();
    const { systemPrompt, warnings } = await buildTurnSystemPrompt(
      PROMPT_WITH_BLOCK,
      "what do I do",
      { index, config },
    );
    expect(warnings).toEqual([]);
    // Ranking used the user prompt and excluded the pin.
    expect(index.calls[0]?.query).toBe("what do I do");
    expect(index.calls[0]?.filters?.excludeIds).toEqual(["c:two"]);
    const ids = [...systemPrompt.matchAll(/<name>([^<]+)<\/name>/g)].map((m) => m[1]);
    expect(ids).toEqual(["c:two", "a:pin", "b:one"]); // pin first, k=3 cap
    expect(ids).not.toContain("foo"); // native block gone
    // Injected where the native block sat: before the cwd line.
    const lines = systemPrompt.split("\n");
    const cwdIdx = lines.findIndex((l) => l.startsWith(CWD_MARKER));
    expect(lines[cwdIdx - 1]).toBe(INJECTED_BLOCK_TRAILER);
  });

  test("unknown pins warn and are skipped", async () => {
    const index = stubIndex();
    const { warnings } = await buildTurnSystemPrompt(PROMPT_WITHOUT_BLOCK, "q", {
      index,
      config: { ...config, pins: ["nope:missing"] },
    });
    expect(warnings).toHaveLength(1);
    expect(warnings[0]).toContain("nope:missing");
  });

  test("pin warnings are forwarded to the onWarnings callback", async () => {
    const index = stubIndex();
    const received: string[][] = [];
    await handleBeforeAgentStart(
      { prompt: "q", systemPrompt: PROMPT_WITHOUT_BLOCK },
      { index, config: { ...config, pins: ["nope:missing"] } },
      (warnings) => received.push(warnings),
    );
    expect(received).toHaveLength(1);
    expect(received[0]?.[0]).toContain("nope:missing");
  });

  test("onWarnings is not called when there are no warnings", async () => {
    const index = stubIndex();
    const received: string[][] = [];
    await handleBeforeAgentStart(
      { prompt: "q", systemPrompt: PROMPT_WITHOUT_BLOCK },
      { index, config },
      (warnings) => received.push(warnings),
    );
    expect(received).toHaveLength(0);
  });

  test("push: false yields undefined (pull-only mode)", async () => {
    const index = stubIndex();
    const result = await handleBeforeAgentStart(
      { prompt: "q", systemPrompt: PROMPT_WITH_BLOCK },
      { index, config: { ...config, push: false } },
    );
    expect(result).toBeUndefined();
    expect(index.calls).toHaveLength(0);
  });

  test("event and systemPromptOptions are treated as read-only", async () => {
    const index = stubIndex();
    const systemPromptOptions = Object.freeze({ cwd: "/work/dir" });
    const event = Object.freeze({
      prompt: "q",
      systemPrompt: PROMPT_WITH_BLOCK,
      systemPromptOptions,
    });
    const result = await handleBeforeAgentStart(event, { index, config });
    expect(result?.systemPrompt).toContain(AVAILABLE_SKILLS_OPEN);
    expect(event.systemPrompt).toBe(PROMPT_WITH_BLOCK); // input untouched
    expect(systemPromptOptions).toEqual({ cwd: "/work/dir" });
  });
});

// --- session warning emission ---------------------------------------------

describe("emitWarningsOnce", () => {
  test("emits each warning once with the skill-discovery prefix", () => {
    const seen = new Set<string>();
    const sunk: string[] = [];
    emitWarningsOnce(seen, ["bad config", "unknown pin"], (m) => sunk.push(m));
    emitWarningsOnce(seen, ["bad config", "unknown pin"], (m) => sunk.push(m)); // repeat turn
    expect(sunk).toEqual(["skill-discovery: bad config", "skill-discovery: unknown pin"]);
  });

  test("new warnings still emit after earlier ones were seen", () => {
    const seen = new Set<string>();
    const sunk: string[] = [];
    emitWarningsOnce(seen, ["first"], (m) => sunk.push(m));
    emitWarningsOnce(seen, ["first", BM25_ONLY_MODE_WARNING], (m) => sunk.push(m));
    expect(sunk).toEqual(["skill-discovery: first", `skill-discovery: ${BM25_ONLY_MODE_WARNING}`]);
  });
});

// --- module-resolution rethrow --------------------------------------------

describe("wrapModuleResolutionError", () => {
  test("resolution errors get the bun-install hint", () => {
    const err = Object.assign(new Error('Cannot find package "typebox"'), {
      code: "ERR_MODULE_NOT_FOUND",
    });
    const wrapped = wrapModuleResolutionError(err, "typebox", "/checkout/adapters");
    expect(wrapped).toBeInstanceOf(Error);
    const message = (wrapped as Error).message;
    expect(message).toContain("run `bun install` in /checkout/adapters");
    expect(message).toContain('"typebox"');
    expect((wrapped as Error).cause).toBe(err);
  });

  test("message-only resolution errors (no code) are also wrapped", () => {
    const err = new Error("Cannot find module 'typebox' from '/x/pi/index.ts'");
    const wrapped = wrapModuleResolutionError(err, "typebox", "/a");
    expect((wrapped as Error).message).toContain("bun install");
  });

  test("unrelated errors pass through unchanged", () => {
    const err = new Error("boom");
    expect(wrapModuleResolutionError(err, "typebox", "/a")).toBe(err);
  });
});

// --- factory over a minimal typed ExtensionAPI stub -----------------------

describe("extension factory", () => {
  function createMockPi() {
    const tools: ToolDefinition[] = [];
    const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
    const mock = {
      registerTool(tool: ToolDefinition) {
        tools.push(tool);
      },
      on(event: string, handler: (event: unknown, ctx: unknown) => unknown) {
        handlers.set(event, handler);
      },
    };
    return { pi: mock as unknown as ExtensionAPI, tools, handlers };
  }

  test("registers search_skills and the session/push handlers", async () => {
    const { pi, tools, handlers } = createMockPi();
    await skillDiscovery(pi);

    expect(tools).toHaveLength(1);
    const tool = tools[0] as ToolDefinition;
    expect(tool.name).toBe("search_skills");
    expect(tool.label).toBe("Search skills");
    expect(tool.description).toContain("read that path to load the skill");
    expect(tool.promptSnippet).toContain("search_skills");
    for (const bullet of tool.promptGuidelines ?? []) {
      expect(bullet).toContain("search_skills"); // bullets must name the tool
    }
    const parameters = tool.parameters as unknown as {
      required?: string[];
      properties?: Record<string, { type?: string }>;
    };
    expect(parameters.required).toEqual(["query"]);
    expect(parameters.properties?.query?.type).toBe("string");
    expect(parameters.properties?.k?.type).toBe("number");

    for (const eventName of ["session_start", "session_shutdown", "before_agent_start"]) {
      expect(handlers.has(eventName)).toBe(true);
    }
  });

  test("zero-config repoRoot default points at the marketplace checkout", () => {
    expect(existsSync(join(DEFAULT_REPO_ROOT, ".claude-plugin", "marketplace.json"))).toBe(true);
  });
});
