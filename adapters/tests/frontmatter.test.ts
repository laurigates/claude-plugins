/**
 * Frontmatter parser tests (DESIGN §2.2, §7.2): unit cases for the DIY
 * parser, plus the whole-corpus diff test against Bun.YAML.parse over every
 * real SKILL.md in the checkout — the DIY rule's verify-against-reference
 * step, with zero added dependency.
 */

import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { extractFrontmatterBlock, parseFrontmatter } from "../core/frontmatter.ts";

const REPO_ROOT = resolve(import.meta.dir, "..", "..");

describe("parseFrontmatter", () => {
  test("plain scalar fields", () => {
    const fm = parseFrontmatter("---\nname: git-commit\ndescription: Commit things.\n---\nbody");
    expect(fm).toEqual({ name: "git-commit", description: "Commit things." });
  });

  test("no frontmatter fence returns null", () => {
    expect(parseFrontmatter("# Just a heading\n")).toBeNull();
    expect(parseFrontmatter("")).toBeNull();
  });

  test("unclosed fence returns null", () => {
    expect(parseFrontmatter("---\nname: x\nno closing fence")).toBeNull();
  });

  test("strips one level of matching quotes", () => {
    const fm = parseFrontmatter("---\ndescription: \"Debug: trace, inspect.\"\nother: 'ok'\n---\n");
    expect(fm?.description).toBe("Debug: trace, inspect.");
    expect(fm?.other).toBe("ok");
  });

  test("mismatched quotes are left alone", () => {
    const fm = parseFrontmatter('---\ndescription: "half quoted\n---\n');
    expect(fm?.description).toBe('"half quoted');
  });

  test("folded scalars (>- and |) join continuation lines with spaces", () => {
    const fm = parseFrontmatter(
      "---\ndescription: >-\n  Render diagrams.\n  Use when documenting.\nname: x\n---\n",
    );
    expect(fm?.description).toBe("Render diagrams. Use when documenting.");
    expect(fm?.name).toBe("x");
  });

  test("folded scalar at end of frontmatter is flushed", () => {
    const fm = parseFrontmatter("---\ndescription: |\n  line one\n  line two\n---\n");
    expect(fm?.description).toBe("line one line two");
  });

  test("lists and nested maps are skipped without corrupting scalars", () => {
    const fm = parseFrontmatter(
      "---\nname: x\ntags:\n  - one\n  - two\ndescription: after the list\n---\n",
    );
    expect(fm?.name).toBe("x");
    expect(fm?.description).toBe("after the list");
    // The list field itself parses as an empty scalar (we consume no such field).
    expect(fm?.tags).toBe("");
  });

  test("extractFrontmatterBlock returns the raw text between fences", () => {
    expect(extractFrontmatterBlock("---\na: 1\nb: 2\n---\nrest")).toBe("a: 1\nb: 2");
    expect(extractFrontmatterBlock("no fence")).toBeNull();
  });
});

describe("whole-corpus diff vs Bun.YAML.parse", () => {
  const yaml = (Bun as unknown as { YAML?: { parse: (t: string) => unknown } }).YAML;
  const haveYaml = typeof yaml?.parse === "function";

  // Every real */skills/*/SKILL.md in the checkout (406 at design time).
  const skillFiles: string[] = [];
  if (haveYaml) {
    for (const top of readdirSync(REPO_ROOT, { withFileTypes: true })) {
      if (!top.isDirectory() || !top.name.endsWith("-plugin")) continue;
      const skillsDir = join(REPO_ROOT, top.name, "skills");
      let dirs: string[] = [];
      try {
        dirs = readdirSync(skillsDir);
      } catch {
        continue;
      }
      for (const dir of dirs) {
        const p = join(skillsDir, dir, "SKILL.md");
        try {
          readFileSync(p);
          skillFiles.push(p);
        } catch {
          // not a skill dir
        }
      }
    }
  }

  test.skipIf(!haveYaml)(
    "name/description/compatibility match Bun.YAML on every real SKILL.md",
    () => {
      expect(skillFiles.length).toBeGreaterThan(300);
      const mismatches: string[] = [];
      for (const file of skillFiles) {
        const text = readFileSync(file, "utf8");
        const block = extractFrontmatterBlock(text);
        if (block === null) continue;
        const ours = parseFrontmatter(text) ?? {};
        let reference: Record<string, unknown>;
        try {
          reference = ((yaml as { parse: (t: string) => unknown }).parse(block) ?? {}) as Record<
            string,
            unknown
          >;
        } catch {
          // Bun.YAML rejects the file entirely; the DIY parser is fail-safe
          // per field, so there is nothing to diff against.
          continue;
        }
        for (const field of ["name", "description", "compatibility"] as const) {
          const refValue = reference[field];
          if (refValue === undefined || refValue === null) continue;
          if (typeof refValue !== "string") continue; // non-scalar: out of contract
          // YAML folded scalars end with a newline and preserve paragraph
          // breaks; our consumer semantics are single-line, so compare
          // whitespace-normalized.
          const normRef = refValue.replace(/\s+/g, " ").trim();
          const normOurs = (ours[field] ?? "").replace(/\s+/g, " ").trim();
          if (normRef !== normOurs) {
            mismatches.push(`${file} [${field}]\n  yaml: ${normRef}\n  ours: ${normOurs}`);
          }
        }
      }
      expect(mismatches).toEqual([]);
    },
  );

  test.skipIf(haveYaml)("SKIPPED: Bun.YAML unavailable in this environment", () => {
    console.warn("Bun.YAML.parse unavailable — frontmatter diff test skipped, parser unverified");
  });
});
