/**
 * Shared render tests (DESIGN §3.3 shape; used by both bindings and by the
 * eval token accounting): pins-first ordering, dedupe, k cap, exact XML
 * entry shape.
 */

import { describe, expect, test } from "bun:test";
import {
  AVAILABLE_SKILLS_CLOSE,
  AVAILABLE_SKILLS_OPEN,
  estimateTokens,
  INJECTED_BLOCK_TRAILER,
  renderInjectedBlock,
  renderSkillEntry,
  renderToolResult,
} from "../core/render.ts";

const skill = (id: string) => ({
  id,
  description: `Description for ${id}`,
  path: `/abs/${id.replace(":", "/")}/SKILL.md`,
});

describe("renderSkillEntry", () => {
  test("exact XML item shape (name/description/location)", () => {
    expect(renderSkillEntry(skill("git-plugin:git-commit"))).toBe(
      "  <skill><name>git-plugin:git-commit</name><description>Description for git-plugin:git-commit</description><location>/abs/git-plugin/git-commit/SKILL.md</location></skill>",
    );
  });
});

describe("renderInjectedBlock", () => {
  test("pins first, then ranked, deduped, capped at k, wrapped with trailer", () => {
    const pins = [skill("a:pin")];
    const ranked = [skill("a:pin"), skill("b:one"), skill("c:two"), skill("d:three")];
    const block = renderInjectedBlock(pins, ranked, 3);
    const lines = block.split("\n");
    expect(lines[0]).toBe(AVAILABLE_SKILLS_OPEN);
    expect(lines[lines.length - 2]).toBe(AVAILABLE_SKILLS_CLOSE);
    expect(lines[lines.length - 1]).toBe(INJECTED_BLOCK_TRAILER);
    const entryIds = lines
      .filter((l) => l.startsWith("  <skill>"))
      .map((l) => /<name>([^<]+)<\/name>/.exec(l)?.[1]);
    expect(entryIds).toEqual(["a:pin", "b:one", "c:two"]); // pin deduped, k=3 cap
  });

  test("empty inputs yield an empty block with the trailer intact", () => {
    const block = renderInjectedBlock([], [], 5);
    expect(block).toBe(
      `${AVAILABLE_SKILLS_OPEN}\n${AVAILABLE_SKILLS_CLOSE}\n${INJECTED_BLOCK_TRAILER}`,
    );
  });
});

describe("renderToolResult", () => {
  test("numbered entries carry the SKILL.md path to read", () => {
    const text = renderToolResult([{ ...skill("a:one"), score: 1.5 }]);
    expect(text).toContain("1. a:one — Description for a:one");
    expect(text).toContain("read: /abs/a/one/SKILL.md");
  });

  test("empty result set says so", () => {
    expect(renderToolResult([])).toBe("No matching skills found.");
  });
});

describe("estimateTokens", () => {
  test("chars/4, rounded up", () => {
    expect(estimateTokens("abcd")).toBe(1);
    expect(estimateTokens("abcde")).toBe(2);
    expect(estimateTokens("")).toBe(0);
  });
});
