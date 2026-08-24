/**
 * Baseline derivation (DESIGN §5.1–§5.2).
 *
 * Baseline membership is derived at runtime, never stored per task — a
 * hand-copied column silently drifts (the drift ADR-0022 exists to remove).
 *
 * - pi baseline: `pi/tiers.yaml` general tier + cherry-picks. Degrades
 *   gracefully (returns null) when the file is absent (post-#2093).
 * - OpenCode baseline: the whole-corpus `*-plugin/skills/<skill>/SKILL.md`
 *   glob the retired rulesync export used, computed offline from the checkout
 *   — no network, no `dist/`. It is a COUNTERFACTUAL cost baseline, not a
 *   description of current behaviour: since #2094 nothing copies skills into
 *   OpenCode. Its membership is trivially ~100% (whole-corpus, uncurated),
 *   which is why the OC comparison is reachability-at-cost, not
 *   reachability-delta.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parseFrontmatter } from "../core/frontmatter.ts";
import { estimateTokens, renderSkillEntry } from "../core/render.ts";

export interface BaselineSkill {
  id: string;
  description: string;
  path: string;
}

export interface BaselineSet {
  ids: Set<string>;
  skills: BaselineSkill[];
}

interface TierEntry {
  tier: "general" | "domain" | "exclude";
  category?: string;
  reason?: string;
  skills?: string[];
}

interface TiersYaml {
  version: number;
  plugins: Record<string, TierEntry>;
}

function skillDirsOf(repoRoot: string, plugin: string): string[] {
  const skillsDir = join(repoRoot, plugin, "skills");
  if (!existsSync(skillsDir)) return [];
  return readdirSync(skillsDir, { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(skillsDir, d.name, "SKILL.md")))
    .map((d) => d.name)
    .sort();
}

function toBaselineSkill(repoRoot: string, plugin: string, skillDir: string): BaselineSkill {
  const path = join(repoRoot, plugin, "skills", skillDir, "SKILL.md");
  const frontmatter = parseFrontmatter(readFileSync(path, "utf8"));
  return {
    id: `${plugin}:${skillDir}`,
    description: frontmatter?.description ?? "",
    path,
  };
}

/**
 * The pi-installed set: every skill of every `tier: general` plugin, with a
 * `skills:` cherry-pick list restricting the plugin to just those dirs.
 * Returns null when pi/tiers.yaml is absent (BASELINE_ARM=ABSENT degradation).
 */
export function derivePiBaseline(repoRoot: string): BaselineSet | null {
  const tiersPath = join(repoRoot, "pi", "tiers.yaml");
  if (!existsSync(tiersPath)) return null;
  const yaml = (Bun as unknown as { YAML: { parse: (text: string) => unknown } }).YAML.parse(
    readFileSync(tiersPath, "utf8"),
  ) as TiersYaml;

  const skills: BaselineSkill[] = [];
  for (const [plugin, entry] of Object.entries(yaml.plugins)) {
    if (entry.tier !== "general") continue;
    const dirs = entry.skills ?? skillDirsOf(repoRoot, plugin);
    for (const dir of dirs) {
      if (!existsSync(join(repoRoot, plugin, "skills", dir, "SKILL.md"))) continue;
      skills.push(toBaselineSkill(repoRoot, plugin, dir));
    }
  }
  return { ids: new Set(skills.map((s) => s.id)), skills };
}

/**
 * The counterfactual OpenCode flat-install set:
 * `<repoRoot>/*-plugin/skills/<skill>/SKILL.md`. Retained after #2094 as the
 * denominator for "what the native listing would have cost", not as a
 * description of anything the export still produces.
 */
export function deriveOcBaseline(repoRoot: string): BaselineSet {
  const skills: BaselineSkill[] = [];
  const topDirs = readdirSync(repoRoot, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name.endsWith("-plugin"))
    .map((d) => d.name)
    .sort();
  for (const plugin of topDirs) {
    for (const dir of skillDirsOf(repoRoot, plugin)) {
      skills.push(toBaselineSkill(repoRoot, plugin, dir));
    }
  }
  return { ids: new Set(skills.map((s) => s.id)), skills };
}

/**
 * Standing-token accounting for a listing arm: per-skill chars/4 over the
 * §3.3 XML entry template (the same render the push channel injects), so the
 * cost model and the injection share one template.
 */
export function listingTokens(skills: BaselineSkill[]): { total: number; perSkillMean: number } {
  if (skills.length === 0) return { total: 0, perSkillMean: 0 };
  let total = 0;
  for (const skill of skills) {
    total += estimateTokens(renderSkillEntry(skill));
  }
  return { total, perSkillMean: total / skills.length };
}
