/**
 * Indexer tests (DESIGN §7.2) over the mini-marketplace fixture, plus the
 * §1.2 static import-restriction checks.
 *
 * Fixture sources live under tests/fixtures/mini-marketplace-src with skill
 * dirs named `skilldirs/` — NO committed path may contain "/skills/", or
 * plugin-pr-checks.yml and every repo-wide skill guard would enroll the
 * fixtures. beforeAll copies the tree to a temp dir, renaming skilldirs/ →
 * skills/, and tests index the temp tree.
 */

import { beforeAll, describe, expect, test } from "bun:test";
import { cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, renameSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { documentText, scanSkills } from "../core/indexer.ts";

const FIXTURE_SRC = join(import.meta.dir, "fixtures", "mini-marketplace-src");
const ADAPTERS_ROOT = resolve(import.meta.dir, "..");

let fixtureRoot = "";

beforeAll(() => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "mini-marketplace-"));
  cpSync(FIXTURE_SRC, fixtureRoot, { recursive: true });
  for (const entry of readdirSync(fixtureRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const src = join(fixtureRoot, entry.name, "skilldirs");
    if (existsSync(src)) renameSync(src, join(fixtureRoot, entry.name, "skills"));
  }
});

describe("committed-fixture invariant", () => {
  test("no committed fixture path contains /skills/", () => {
    const offenders: string[] = [];
    const walk = (dir: string) => {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
          if (entry.name === "skills") offenders.push(full);
          else walk(full);
        }
      }
    };
    walk(FIXTURE_SRC);
    expect(offenders).toEqual([]);
  });
});

describe("scanSkills over the mini marketplace", () => {
  test('target "foreign" filters compatibility: claude-code and drops description-less', () => {
    const { entries, warnings } = scanSkills(fixtureRoot, "foreign");
    const ids = entries.map((e) => e.id).sort();
    expect(ids).toEqual([
      "alpha-plugin:normal-skill",
      "beta-plugin:no-name",
      "gamma-plugin:folded-description",
      "gamma-plugin:quoted-description",
    ]);
    expect(warnings.some((w) => w.includes("beta-plugin:no-description"))).toBe(true);
    expect(warnings.some((w) => w.includes("cc-only-skill"))).toBe(false); // filtered, not warned
  });

  test('target "claude-code" keeps the compatibility-marked skill', () => {
    const { entries } = scanSkills(fixtureRoot, "claude-code");
    const ids = entries.map((e) => e.id);
    expect(ids).toContain("alpha-plugin:cc-only-skill");
    expect(entries).toHaveLength(5);
    const ccOnly = entries.find((e) => e.id === "alpha-plugin:cc-only-skill");
    expect(ccOnly?.compatibility).toBe("claude-code");
  });

  test("name falls back to the skill directory basename", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const noName = entries.find((e) => e.id === "beta-plugin:no-name");
    expect(noName?.name).toBe("no-name");
  });

  test("folded description joins with spaces", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const folded = entries.find((e) => e.id === "gamma-plugin:folded-description");
    expect(folded?.description).toBe(
      "Render architecture diagrams from text sources. Use when documenting system topology.",
    );
  });

  test("quoted description with colons has quotes stripped", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const quoted = entries.find((e) => e.id === "gamma-plugin:quoted-description");
    expect(quoted?.description).toBe(
      "Debug HTTP APIs: trace requests, inspect headers. Use when a request fails: check status first.",
    );
  });

  test("entries carry marketplace category/keywords and an absolute SKILL.md path", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const normal = entries.find((e) => e.id === "alpha-plugin:normal-skill");
    expect(normal?.category).toBe("test-a");
    expect(normal?.keywords).toEqual(["alpha", "testing"]);
    expect(normal?.path.endsWith("alpha-plugin/skills/normal-skill/SKILL.md")).toBe(true);
    expect(normal?.path.startsWith("/")).toBe(true);
  });

  test("document text is name + description, nothing else", () => {
    const { entries } = scanSkills(fixtureRoot, "foreign");
    const normal = entries.find((e) => e.id === "alpha-plugin:normal-skill");
    expect(documentText(normal as NonNullable<typeof normal>)).toBe(
      `${normal?.name} ${normal?.description}`,
    );
    // Keywords/category stay out of the scored text.
    expect(documentText(normal as NonNullable<typeof normal>)).not.toContain("test-a");
  });
});

/**
 * §1.2 static import-restriction checks. Dependency discipline is enforced
 * by convention plus this test, not package boundaries.
 */
describe("static import restrictions", () => {
  const IMPORT_RE = /(?:from\s+|import\s+|import\s*\(\s*|require\s*\(\s*)["']([^"']+)["']/g;

  function importSpecifiers(filePath: string): string[] {
    const source = readFileSync(filePath, "utf8");
    const specs: string[] = [];
    for (const match of source.matchAll(IMPORT_RE)) {
      specs.push(match[1] as string);
    }
    return specs;
  }

  function tsFilesUnder(dir: string): string[] {
    const files: string[] = [];
    const walk = (d: string) => {
      for (const entry of readdirSync(d, { withFileTypes: true })) {
        const full = join(d, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.name.endsWith(".ts")) files.push(full);
      }
    };
    walk(dir);
    return files;
  }

  test("core/ imports nothing but node:* and relative paths", () => {
    const violations: string[] = [];
    for (const file of tsFilesUnder(join(ADAPTERS_ROOT, "core"))) {
      for (const spec of importSpecifiers(file)) {
        if (spec.startsWith("node:") || spec.startsWith("./") || spec.startsWith("../")) continue;
        violations.push(`${file}: ${spec}`);
      }
    }
    expect(violations).toEqual([]);
  });

  // pi/ lands in #2090; the restriction is encoded now so a future dep
  // addition cannot silently depend on unverified jiti-in-binary
  // node_modules resolution. Skips gracefully while the dir is absent.
  const piDir = join(ADAPTERS_ROOT, "pi");
  test.skipIf(!existsSync(piDir))(
    "pi/ imports only typebox, type-only pi-coding-agent, node:*, and relative paths",
    () => {
      const violations: string[] = [];
      for (const file of tsFilesUnder(piDir)) {
        const source = readFileSync(file, "utf8");
        for (const line of source.split("\n")) {
          const m = /(?:from\s+|import\s+|import\s*\(\s*|require\s*\(\s*)["']([^"']+)["']/.exec(
            line,
          );
          if (!m) continue;
          const spec = m[1] as string;
          if (spec.startsWith("node:") || spec.startsWith("./") || spec.startsWith("../")) continue;
          if (spec === "typebox") continue;
          if (spec === "@earendil-works/pi-coding-agent" && /^\s*import\s+type\s/.test(line)) {
            continue; // type-only: erased at transpile time
          }
          violations.push(`${file}: ${line.trim()}`);
        }
      }
      expect(violations).toEqual([]);
    },
  );

  // opencode/ (#2091): the documented single runtime dependency is
  // @opencode-ai/plugin (value, type, and dynamic `import(...)` forms all
  // allowed — the binding deliberately funnels the value import through one
  // dynamic import for the bun-install rethrow). Anything else — including
  // a direct @opencode-ai/sdk import, which is only a transitive dep of the
  // plugin package and would be a phantom dependency — is a violation.
  test("opencode/ imports only @opencode-ai/plugin, node:*, and relative paths", () => {
    const violations: string[] = [];
    for (const file of tsFilesUnder(join(ADAPTERS_ROOT, "opencode"))) {
      for (const spec of importSpecifiers(file)) {
        if (spec.startsWith("node:") || spec.startsWith("./") || spec.startsWith("../")) continue;
        if (spec === "@opencode-ai/plugin") continue;
        violations.push(`${file}: ${spec}`);
      }
    }
    expect(violations).toEqual([]);
  });
});
