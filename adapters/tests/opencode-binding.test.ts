/**
 * OpenCode binding tests (#2091): stubbed PluginInput/Hooks harness — no
 * live OpenCode required. Covers system.transform strip+inject (block
 * present / absent / positions collapsed), messages.transform capture,
 * tool execute output shape, options handling, and the module-resolution
 * rethrow.
 *
 * The index is built over the mini-marketplace fixture (same skilldirs/ →
 * skills/ rename trick as indexer.test.ts) with the embed endpoint pointed
 * at an unbound local port, so every test runs deterministic BM25-only
 * with zero network.
 */

import { beforeAll, describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdtempSync, readdirSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import type { Hooks, PluginInput, ToolContext } from "@opencode-ai/plugin";
import type { Model, Part } from "@opencode-ai/sdk";
import {
  AVAILABLE_SKILLS_CLOSE,
  AVAILABLE_SKILLS_OPEN,
  DEFAULT_ENDPOINT,
  DEFAULT_K,
  DEFAULT_MODEL,
  INJECTED_BLOCK_TRAILER,
} from "../core/index.ts";
import { scanSkills } from "../core/indexer.ts";
import { DEFAULT_REPO_ROOT, resolveOptions } from "../opencode/config.ts";
import { loadToolApi, resolvePins, SkillDiscoveryPlugin } from "../opencode/index.ts";

const FIXTURE_SRC = join(import.meta.dir, "fixtures", "mini-marketplace-src");
/** Unbound port: fetch rejects fast → index degrades to bm25-only, no network. */
const DEAD_ENDPOINT = "http://127.0.0.1:1";

let fixtureRoot = "";

beforeAll(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "oc-binding-"));
  cpSync(FIXTURE_SRC, fixtureRoot, { recursive: true });
  for (const entry of readdirSync(fixtureRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const src = join(fixtureRoot, entry.name, "skilldirs");
    if (existsSync(src)) renameSync(src, join(fixtureRoot, entry.name, "skills"));
  }
});

const STUB_MODEL = { modelID: "stub", providerID: "stub" } as unknown as Model;
const STUB_TOOL_CONTEXT = {
  sessionID: "ses_stub",
  messageID: "msg_stub",
  agent: "stub",
} as unknown as ToolContext;

function stubInput(): PluginInput {
  return {
    // Unbound port again: the informational health probe is fire-and-forget
    // and must never gate — a rejected fetch is the exercised path here.
    serverUrl: new URL(DEAD_ENDPOINT),
    directory: fixtureRoot,
    worktree: fixtureRoot,
  } as unknown as PluginInput;
}

function makeHooks(options?: Record<string, unknown>): Promise<Hooks> {
  return SkillDiscoveryPlugin(stubInput(), {
    repoRoot: fixtureRoot,
    endpoint: DEAD_ENDPOINT,
    ...options,
  });
}

function userMessage(text: string): { info: { role: "user" }; parts: Part[] } {
  return {
    info: { role: "user" },
    parts: [{ type: "text", text } as unknown as Part],
  };
}

function assistantMessage(text: string): { info: { role: "assistant" }; parts: Part[] } {
  return {
    info: { role: "assistant" },
    parts: [{ type: "text", text } as unknown as Part],
  };
}

type MessagesOutput = Parameters<NonNullable<Hooks["experimental.chat.messages.transform"]>>[1];

async function runSystemTransform(hooks: Hooks, system: string[]): Promise<string[]> {
  const output = { system };
  await hooks["experimental.chat.system.transform"]?.({ model: STUB_MODEL }, output);
  return output.system;
}

async function runMessagesTransform(hooks: Hooks, messages: MessagesOutput["messages"]) {
  await hooks["experimental.chat.messages.transform"]?.({}, { messages });
}

describe("options handling (resolveOptions)", () => {
  test("missing options yield all defaults", () => {
    const { config, warnings } = resolveOptions(undefined);
    expect(config).toEqual({
      repoRoot: DEFAULT_REPO_ROOT,
      k: DEFAULT_K,
      endpoint: DEFAULT_ENDPOINT,
      model: DEFAULT_MODEL,
      pins: [],
    });
    expect(warnings).toEqual([]);
  });

  test("DEFAULT_REPO_ROOT is the checkout root (two dirs above opencode/)", () => {
    expect(DEFAULT_REPO_ROOT).toBe(resolve(import.meta.dir, "..", ".."));
  });

  test("valid options pass through", () => {
    const { config, warnings } = resolveOptions({
      repoRoot: "/somewhere",
      k: 3,
      endpoint: "http://embed:1234",
      model: "custom-model",
      pins: ["a:one", "b:two"],
    });
    expect(config.repoRoot).toBe("/somewhere");
    expect(config.k).toBe(3);
    expect(config.endpoint).toBe("http://embed:1234");
    expect(config.model).toBe("custom-model");
    expect(config.pins).toEqual(["a:one", "b:two"]);
    expect(warnings).toEqual([]);
  });

  test("invalid values warn and fall back to defaults", () => {
    const { config, warnings } = resolveOptions({
      k: 0,
      repoRoot: 42,
      pins: "not-an-array",
      endpoint: "",
    });
    expect(config.k).toBe(DEFAULT_K);
    expect(config.repoRoot).toBe(DEFAULT_REPO_ROOT);
    expect(config.pins).toEqual([]);
    expect(config.endpoint).toBe(DEFAULT_ENDPOINT);
    expect(warnings).toHaveLength(4);
  });

  test("non-string pin entries are skipped with a warning, strings kept", () => {
    const { config, warnings } = resolveOptions({ pins: ["a:one", 7, null] });
    expect(config.pins).toEqual(["a:one"]);
    expect(warnings).toHaveLength(2);
  });

  test("unknown option keys warn and are ignored", () => {
    const { config, warnings } = resolveOptions({ push: false });
    expect(config.k).toBe(DEFAULT_K);
    expect(warnings.some((w) => w.includes('unknown option "push"'))).toBe(true);
  });
});

describe("resolvePins", () => {
  test("known pins resolve in order; unknown pins are reported", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const { pins, unknown } = resolvePins(
      ["gamma-plugin:quoted-description", "nope:missing", "alpha-plugin:normal-skill"],
      entries,
    );
    expect(pins.map((p) => p.id)).toEqual([
      "gamma-plugin:quoted-description",
      "alpha-plugin:normal-skill",
    ]);
    expect(unknown).toEqual(["nope:missing"]);
  });
});

describe("module-resolution failure", () => {
  test("rethrows with the bun-install remedy and preserves the cause", async () => {
    const cause = new Error("Cannot find module '@opencode-ai/plugin'");
    const promise = loadToolApi(() => Promise.reject(cause));
    await expect(promise).rejects.toThrow(/run `bun install` in .*\/adapters/);
    await expect(promise).rejects.toMatchObject({ cause });
  });

  test("resolves the real tool() helper when the package is installed", async () => {
    const tool = await loadToolApi();
    expect(typeof tool).toBe("function");
    expect(typeof tool.schema.string).toBe("function");
  });
});

describe("search_skills tool", () => {
  test("execute returns the numbered ToolResult string with SKILL.md paths", async () => {
    const hooks = await makeHooks();
    const definition = hooks.tool?.search_skills;
    expect(definition).toBeDefined();
    const result = await definition?.execute(
      { query: "render architecture diagrams for system topology", k: 2 },
      STUB_TOOL_CONTEXT,
    );
    expect(typeof result).toBe("string");
    const text = result as string;
    const lines = text.split("\n");
    expect(lines[0]).toMatch(/^1\. gamma-plugin:folded-description — /);
    expect(text).toContain(`read: ${fixtureRoot}/gamma-plugin/skills/folded-description/SKILL.md`);
    // Only one fixture doc matches these query tokens (BM25 returns
    // positive-scoring docs only), so k=2 still yields a single entry.
    expect(lines.filter((l) => /^\d+\. /.test(l))).toHaveLength(1);
  });

  test("k caps the result list", async () => {
    const hooks = await makeHooks();
    // "use when" appears in every fixture description → all 4 docs score.
    const result = await hooks.tool?.search_skills?.execute(
      { query: "use when", k: 2 },
      STUB_TOOL_CONTEXT,
    );
    const lines = (result as string).split("\n");
    expect(lines.filter((l) => /^\d+\. /.test(l))).toHaveLength(2);
  });

  test("no-match queries return the empty-result sentence, never throw", async () => {
    const hooks = await makeHooks();
    const result = await hooks.tool?.search_skills?.execute(
      { query: "zzz qqq xyzzy" },
      STUB_TOOL_CONTEXT,
    );
    expect(result).toBe("No matching skills found.");
  });

  test("tool description routes the model to read the returned path", async () => {
    const hooks = await makeHooks();
    expect(hooks.tool?.search_skills?.description).toContain("read that path to load the skill");
  });
});

describe("experimental.chat.system.transform — strip + inject", () => {
  const NATIVE_BLOCK = `${AVAILABLE_SKILLS_OPEN}\n  <skill><name>native</name><description>d</description><location>/x</location></skill>\n${AVAILABLE_SKILLS_CLOSE}`;

  test("native block element is stripped and one adapter block appended", async () => {
    const hooks = await makeHooks();
    const system = await runSystemTransform(hooks, ["You are opencode.", NATIVE_BLOCK, "cwd: /x"]);
    const withBlock = system.filter((s) => s.includes(AVAILABLE_SKILLS_OPEN));
    expect(withBlock).toHaveLength(1); // only the adapter's own block survives
    expect(withBlock[0]).not.toContain("<name>native</name>");
    expect(withBlock[0]?.endsWith(INJECTED_BLOCK_TRAILER)).toBe(true);
    expect(system[0]).toBe("You are opencode.");
    expect(system).toContain("cwd: /x");
  });

  test("block absent (permission.skill deny did its job): elements untouched, block appended", async () => {
    const hooks = await makeHooks();
    const system = await runSystemTransform(hooks, ["header", "body"]);
    expect(system.slice(0, 2)).toEqual(["header", "body"]);
    expect(system).toHaveLength(3);
    expect(system[2]?.startsWith(AVAILABLE_SKILLS_OPEN)).toBe(true);
  });

  test("positions collapsed: the block is found by content, never by index", async () => {
    const hooks = await makeHooks();
    // Simulates a pre-collapsed / reordered array: the native block rides
    // inside a merged element at a non-canonical position.
    const merged = `environment details\n${NATIVE_BLOCK}\ntrailing instructions`;
    const system = await runSystemTransform(hooks, [merged, "header moved"]);
    expect(system.some((s) => s.includes("<name>native</name>"))).toBe(false);
    expect(system[0]).toBe("header moved");
    expect(system[system.length - 1]?.endsWith(INJECTED_BLOCK_TRAILER)).toBe(true);
  });

  test("first turn with no captured message injects pins only", async () => {
    const hooks = await makeHooks({ pins: ["alpha-plugin:normal-skill"] });
    const system = await runSystemTransform(hooks, ["header"]);
    const block = system[system.length - 1] as string;
    expect(block).toContain("<name>alpha-plugin:normal-skill</name>");
    // No ranked entries without a captured user message.
    const entryCount = block.split("\n").filter((l) => l.startsWith("  <skill>")).length;
    expect(entryCount).toBe(1);
  });

  test("bad repoRoot degrades push to a no-op (pull-first), never throws", async () => {
    const hooks = await SkillDiscoveryPlugin(stubInput(), {
      repoRoot: join(fixtureRoot, "does-not-exist"),
      endpoint: DEAD_ENDPOINT,
    });
    const system = await runSystemTransform(hooks, ["header", NATIVE_BLOCK]);
    // Defensive strip still ran; failed injection appends nothing.
    expect(system).toEqual(["header"]);
  });
});

describe("experimental.chat.messages.transform — ranking-input capture", () => {
  test("latest user message drives the injected ranking", async () => {
    const hooks = await makeHooks();
    await runMessagesTransform(hooks, [
      userMessage("commit staged changes to git"),
      assistantMessage("done"),
      userMessage("render architecture diagrams from my notes"),
    ] as MessagesOutput["messages"]);
    const system = await runSystemTransform(hooks, ["header"]);
    const block = system[system.length - 1] as string;
    const first = block.split("\n").find((l) => l.startsWith("  <skill>"));
    expect(first).toContain("<name>gamma-plugin:folded-description</name>");
  });

  test("a trailing assistant message keeps the previous user capture (one-turn-stale contract)", async () => {
    const hooks = await makeHooks();
    await runMessagesTransform(hooks, [
      userMessage("inspect JSON payloads from the API"),
      assistantMessage("looking"),
    ] as MessagesOutput["messages"]);
    const system = await runSystemTransform(hooks, []);
    const block = system[0] as string;
    const first = block.split("\n").find((l) => l.startsWith("  <skill>"));
    expect(first).toContain("<name>beta-plugin:no-name</name>");
  });

  test("pins come first, ranked results fill k after pins, deduped", async () => {
    const hooks = await makeHooks({ pins: ["alpha-plugin:normal-skill"], k: 2 });
    await runMessagesTransform(hooks, [
      userMessage("render architecture diagrams from my notes"),
    ] as MessagesOutput["messages"]);
    const system = await runSystemTransform(hooks, []);
    const block = system[0] as string;
    const ids = block
      .split("\n")
      .filter((l) => l.startsWith("  <skill>"))
      .map((l) => /<name>([^<]+)<\/name>/.exec(l)?.[1]);
    expect(ids).toEqual(["alpha-plugin:normal-skill", "gamma-plugin:folded-description"]);
  });

  test("a ranked hit that duplicates a pin is deduped", async () => {
    const hooks = await makeHooks({ pins: ["gamma-plugin:folded-description"], k: 3 });
    await runMessagesTransform(hooks, [
      userMessage("render architecture diagrams from my notes"),
    ] as MessagesOutput["messages"]);
    const system = await runSystemTransform(hooks, []);
    const block = system[0] as string;
    const ids = block
      .split("\n")
      .filter((l) => l.startsWith("  <skill>"))
      .map((l) => /<name>([^<]+)<\/name>/.exec(l)?.[1]);
    // The pin is also the top ranked hit; excludeIds keeps it out of the
    // ranked arm and renderInjectedBlock dedupes — exactly one copy.
    expect(ids.filter((id) => id === "gamma-plugin:folded-description")).toHaveLength(1);
  });

  test("unknown pins are skipped without breaking injection", async () => {
    const hooks = await makeHooks({ pins: ["nope:missing", "alpha-plugin:normal-skill"] });
    const system = await runSystemTransform(hooks, []);
    const block = system[0] as string;
    expect(block).toContain("<name>alpha-plugin:normal-skill</name>");
    expect(block).not.toContain("nope:missing");
  });
});
