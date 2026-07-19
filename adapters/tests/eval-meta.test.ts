/**
 * Eval meta-tests (DESIGN §5.5) — the CI teeth, per
 * validate-adversarial-constructions (both halves: broken-fails AND
 * correct-passes). The cutover comparison itself is the §5.6 local
 * procedure, not CI.
 */

import { beforeAll, describe, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { tokenize } from "../core/bm25.ts";
import { parseFrontmatter } from "../core/frontmatter.ts";
import type { SkillIndex } from "../core/search.ts";
import { buildIndex } from "../core/search.ts";
import type { Ranker } from "../core/types.ts";
import { DEFAULT_K } from "../core/types.ts";
import {
  countExportedOcSkills,
  deriveOcBaseline,
  derivePiBaseline,
  listingTokens,
} from "../eval/baseline.ts";
import {
  bm25OnlyRanker,
  descriptionSubstringRanker,
  type EvalTask,
  nameSubstringRanker,
  oracleRanker,
  randomRanker,
} from "../eval/rankers.ts";
import { loadTaskSet, TASKS_PATH, validateTaskSet } from "../eval/run-eval.ts";

const REPO_ROOT = resolve(import.meta.dir, "..", "..");

const taskSet = loadTaskSet(TASKS_PATH);
const positiveTasks = taskSet.tasks.filter((t) => !t.negative);
let index: SkillIndex;

beforeAll(async () => {
  index = await buildIndex({ repoRoot: REPO_ROOT, embed: { disabled: true } });
});

async function hitAtK(ranker: Ranker, tasks: EvalTask[]): Promise<number> {
  let hits = 0;
  for (const task of tasks) {
    const ids = (await ranker(task.prompt, DEFAULT_K)).map((r) => r.id);
    const targets = new Set([...task.expected_skills, ...task.acceptable_skills]);
    if (ids.some((id) => targets.has(id))) hits++;
  }
  return hits / tasks.length;
}

async function hitAt1Expected(ranker: Ranker, tasks: EvalTask[]): Promise<number> {
  let hits = 0;
  for (const task of tasks) {
    const ids = (await ranker(task.prompt, DEFAULT_K)).map((r) => r.id);
    if (ids.length > 0 && task.expected_skills.includes(ids[0] as string)) hits++;
  }
  return hits / tasks.length;
}

describe("5. schema checks", () => {
  test("task set passes every schema check (gate block, acceptable_skills, tags, k === DEFAULT_K, unique ids)", () => {
    expect(validateTaskSet(taskSet)).toEqual([]);
    expect(taskSet.k).toBe(DEFAULT_K);
  });

  test("every expected/acceptable skill id resolves to a real SKILL.md", () => {
    const missing: string[] = [];
    for (const task of taskSet.tasks) {
      for (const id of [...task.expected_skills, ...task.acceptable_skills]) {
        const [plugin, skill] = id.split(":", 2) as [string, string];
        const p = join(REPO_ROOT, plugin, "skills", skill, "SKILL.md");
        if (!existsSync(p)) missing.push(`${task.id}: ${id}`);
      }
    }
    expect(missing).toEqual([]);
  });

  test("every expected/acceptable skill id is present in the built foreign index (reachable by real rankers)", () => {
    // Disk existence alone is not enough: a target carrying
    // `compatibility: claude-code` (or lacking a description) is out of the
    // foreign index, making the task structurally unwinnable for every real
    // ranker while the oracle still scores 100% — this keeps meta-test 1's
    // achievability proof honest.
    const indexIds = new Set(index.entries.map((e) => e.id));
    const unreachable: string[] = [];
    for (const task of taskSet.tasks) {
      for (const id of [...task.expected_skills, ...task.acceptable_skills]) {
        if (!indexIds.has(id)) unreachable.push(`${task.id}: ${id}`);
      }
    }
    expect(unreachable).toEqual([]);
  });

  test("derived OC baseline equals a live count of the export glob (dist-independent)", () => {
    // Independent recount of the exact glob export-opencode.sh iterates
    // (`*-plugin/skills/*/SKILL.md`), so the assertion holds in CI where the
    // gitignored dist/ never exists.
    const derived = deriveOcBaseline(REPO_ROOT).ids.size;
    let live = 0;
    for (const top of readdirSync(REPO_ROOT, { withFileTypes: true })) {
      if (!top.isDirectory() || !top.name.endsWith("-plugin")) continue;
      const skillsDir = join(REPO_ROOT, top.name, "skills");
      if (!existsSync(skillsDir)) continue;
      for (const sub of readdirSync(skillsDir, { withFileTypes: true })) {
        if (sub.isDirectory() && existsSync(join(skillsDir, sub.name, "SKILL.md"))) live++;
      }
    }
    expect(derived).toBe(live);
  });

  test("dist/ OUTPUT_SKILLS cross-check (informational — dist is a point-in-time artifact, absent in CI)", () => {
    const exported = countExportedOcSkills(REPO_ROOT);
    if (exported === null) {
      console.warn(
        "dist/opencode absent — OC export cross-check skipped (runs only after `just export-opencode`; CI always skips)",
      );
      return;
    }
    const derived = deriveOcBaseline(REPO_ROOT).ids.size;
    if (exported !== derived) {
      console.warn(
        `dist/opencode is stale: exported ${exported} vs derived ${derived} — rerun \`just export-opencode\` (informational, not a failure)`,
      );
    }
  });
});

describe("1. random fails every seed; oracle passes", () => {
  // Chance bound: k · max|E∪A| / N (DESIGN §5.5.1 — NOT the single-target
  // 1.25%). At authoring time: k=5, max targets 4, N=363 foreign entries →
  // ~5.5% worst case; measured random hit@5 max over seeds 0..19 was 7.9%.
  // The per-seed ceiling is 3× the bound (~16.5%) — far above sampling noise
  // on ~63 tasks, far below bm25Only (55.6%) and the oracle (100%).
  test("random(seed) stays at chance level with margin on ALL 20 seeds", async () => {
    const maxTargets = Math.max(
      ...positiveTasks.map((t) => t.expected_skills.length + t.acceptable_skills.length),
    );
    const chanceBound = (DEFAULT_K * maxTargets) / index.entries.length;
    const ceiling = 3 * chanceBound;
    for (let seed = 0; seed < 20; seed++) {
      const hit = await hitAtK(randomRanker(index, seed), positiveTasks);
      expect(hit).toBeLessThanOrEqual(ceiling);
    }
  });

  test("oracle scores 100% on hit@k AND hit@1", async () => {
    const oracle = oracleRanker(index, taskSet.tasks);
    expect(await hitAtK(oracle, positiveTasks)).toBe(1);
    expect(await hitAt1Expected(oracle, positiveTasks)).toBe(1);
  });
});

describe("2. substring rankers lose to bm25Only", () => {
  test("nameSubstring scores materially below bm25Only on stratum:paraphrase (no name echo)", async () => {
    const paraphrase = positiveTasks.filter((t) => t.tags.includes("stratum:paraphrase"));
    expect(paraphrase.length).toBeGreaterThan(10);
    const bm25 = await hitAtK(bm25OnlyRanker(index), paraphrase);
    const nameSub = await hitAtK(nameSubstringRanker(index), paraphrase);
    // Measured at authoring time: bm25 0.406 vs nameSubstring 0.094.
    expect(nameSub).toBeLessThanOrEqual(bm25 - 0.15);
  });

  test("descriptionSubstring scores materially below bm25Only across ALL strata (no description echo)", async () => {
    const bm25 = await hitAtK(bm25OnlyRanker(index), positiveTasks);
    const descSub = await hitAtK(descriptionSubstringRanker(index), positiveTasks);
    // Measured at authoring time: bm25 0.556 vs descriptionSubstring 0.460
    // (gap 0.096). The 0.05 margin is what the measured corpus supports; if
    // this narrows on a task-set change, re-derive per §5.5 ("the simulation
    // wins") rather than deleting the assertion.
    expect(descSub).toBeLessThanOrEqual(bm25 - 0.05);
  });
});

describe("3. token calibration (per-skill)", () => {
  const piBaseline = derivePiBaseline(REPO_ROOT);
  test.skipIf(piBaseline === null)(
    "mean rendered tokens/skill over the runtime-derived general tier ∈ 111 ± 20%",
    () => {
      // 111 tok/skill was measured on pi 0.80.6 with a real tokenizer. Our
      // chars/4 proxy over the same render measured −13.6% vs that (94.6
      // tok/skill over the then-95-skill tier; 104.0 at authoring time) —
      // inside the ±20% band [88.8, 133.2]. Record the offset so future
      // drift is interpretable: a breach means either the render template
      // diverged from what pi injects, or the tier's description profile
      // shifted materially.
      //
      // The render embeds each SKILL.md's absolute <location> path, so the
      // raw mean shifts with checkout-path length (a shallow clone could
      // spuriously breach the lower bound). Calibrate over a path-normalized
      // render: fixed 45-char prefix (the length of the checkout the 111
      // tok/skill reference was measured in) + the repo-relative path. The
      // runner's informational TOKENS output keeps real paths.
      const CANONICAL_PREFIX = "/canonical/checkout/claude-plugins".padEnd(45, "-");
      const normalized = (piBaseline as NonNullable<typeof piBaseline>).skills.map((s) => ({
        ...s,
        path: CANONICAL_PREFIX + s.path.slice(REPO_ROOT.length),
      }));
      const { perSkillMean } = listingTokens(normalized);
      expect(perSkillMean).toBeGreaterThanOrEqual(111 * 0.8);
      expect(perSkillMean).toBeLessThanOrEqual(111 * 1.2);
    },
  );

  test.skipIf(piBaseline !== null)("SKIPPED: pi/tiers.yaml absent (post-#2093 degradation)", () => {
    console.warn("pi/tiers.yaml absent — calibration meta-test skipped (BASELINE_ARM=ABSENT)");
  });
});

describe("4. leakage lint (deterministic)", () => {
  test("no non-negative task shares a token trigram with a target's name+description", () => {
    const trigrams = (tokens: string[]) => {
      const set = new Set<string>();
      for (let i = 0; i + 2 < tokens.length; i++) {
        set.add(`${tokens[i]} ${tokens[i + 1]} ${tokens[i + 2]}`);
      }
      return set;
    };
    const offenders: string[] = [];
    for (const task of positiveTasks) {
      const promptTrigrams = trigrams(tokenize(task.prompt));
      for (const id of [...task.expected_skills, ...task.acceptable_skills]) {
        const [plugin, skill] = id.split(":", 2) as [string, string];
        const skillPath = join(REPO_ROOT, plugin, "skills", skill, "SKILL.md");
        if (!existsSync(skillPath)) continue; // covered by the schema check
        const fm = parseFrontmatter(readFileSync(skillPath, "utf8")) ?? {};
        const doc = `${fm.name ?? skill} ${fm.description ?? ""}`;
        const shared = [...promptTrigrams].filter((t) => trigrams(tokenize(doc)).has(t));
        if (shared.length > 0) {
          offenders.push(`${task.id} vs ${id}: ${shared.join("; ")}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });
});
