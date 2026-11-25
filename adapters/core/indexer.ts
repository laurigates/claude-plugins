/**
 * Marketplace scanner (DESIGN §2.3).
 *
 * Marketplace-first, not a bare repo glob: `.claude-plugin/marketplace.json`
 * is the discovery root, so a stray non-plugin skills dir cannot leak in.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parseFrontmatter } from "./frontmatter.ts";
import type { SkillEntry } from "./types.ts";

interface MarketplacePlugin {
  name: string;
  source: string;
  description: string;
  version: string;
  keywords: string[];
  category: string;
}

interface Marketplace {
  plugins: MarketplacePlugin[];
}

/** Suffix of the warning an unknown `plugins` name produces (bindings surface these). */
export const UNKNOWN_PLUGIN_WARNING_SUFFIX = "is not in the marketplace — ignored";

/** True for the warnings a binding should show: a `plugins` name the marketplace lacks. */
export function isUnknownPluginWarning(warning: string): boolean {
  return warning.endsWith(UNKNOWN_PLUGIN_WARNING_SUFFIX);
}

export interface ScanResult {
  entries: SkillEntry[];
  warnings: string[];
}

/**
 * Scan the marketplace checkout into SkillEntry[].
 *
 * - `name` falls back to the skill directory basename (both harnesses' own
 *   fallback/keying rule).
 * - Entries with an absent/empty `description` are dropped with a warning
 *   (mirrors pi, which silently drops description-less skills, and OpenCode,
 *   which delists them).
 * - Compatibility filter: when target === "foreign" (default), drop entries
 *   whose `compatibility` contains "claude-code". Substring match, not
 *   equality — the observed corpus is uniformly the bare string, but a future
 *   list syntax must not silently defeat the filter. Neither harness enforces
 *   the field itself, so the core is the only place this judgment executes.
 * - Plugin filter: a non-empty `plugins` keeps only those marketplace
 *   plugins. A name the marketplace does not list warns and is ignored, so a
 *   typo in the config degrades to "that plugin is missing" rather than a
 *   crash.
 */
export function scanSkills(
  repoRoot: string,
  target: "foreign" | "claude-code" = "foreign",
  plugins?: string[],
): ScanResult {
  const marketplacePath = join(repoRoot, ".claude-plugin", "marketplace.json");
  const marketplace = JSON.parse(readFileSync(marketplacePath, "utf8")) as Marketplace;

  const entries: SkillEntry[] = [];
  const warnings: string[] = [];

  const selected = plugins && plugins.length > 0 ? new Set(plugins) : null;
  if (selected) {
    const known = new Set(marketplace.plugins.map((plugin) => plugin.name));
    for (const name of selected) {
      if (!known.has(name)) warnings.push(`plugin "${name}" ${UNKNOWN_PLUGIN_WARNING_SUFFIX}`);
    }
  }

  for (const plugin of marketplace.plugins) {
    if (selected && !selected.has(plugin.name)) continue;
    const skillsDir = join(repoRoot, plugin.source, "skills");
    if (!existsSync(skillsDir)) continue;
    const skillDirs = readdirSync(skillsDir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
    for (const skillDir of skillDirs) {
      const skillPath = join(skillsDir, skillDir, "SKILL.md");
      if (!existsSync(skillPath)) continue;
      const id = `${plugin.name}:${skillDir}`;
      const frontmatter = parseFrontmatter(readFileSync(skillPath, "utf8"));
      if (frontmatter === null) {
        warnings.push(`${id}: no frontmatter — dropped (description required)`);
        continue;
      }
      const description = frontmatter.description ?? "";
      if (description.trim().length === 0) {
        warnings.push(`${id}: missing description — dropped`);
        continue;
      }
      const compatibility = frontmatter.compatibility;
      if (
        target === "foreign" &&
        compatibility !== undefined &&
        compatibility.includes("claude-code")
      ) {
        continue;
      }
      const name = (frontmatter.name ?? "").trim() || skillDir;
      const entry: SkillEntry = {
        id,
        name,
        plugin: plugin.name,
        description,
        path: skillPath,
        category: plugin.category,
        keywords: plugin.keywords,
      };
      if (compatibility !== undefined) entry.compatibility = compatibility;
      entries.push(entry);
    }
  }
  return { entries, warnings };
}

/**
 * BM25/embedding document text per entry: name + description. Plugin
 * keywords/category stay out of the scored text (they exist as filters, and
 * stuffing them in would let category words outrank intent words in short
 * descriptions).
 */
export function documentText(entry: SkillEntry): string {
  return `${entry.name} ${entry.description}`;
}
