/**
 * Eval meta-tests (DESIGN §5.5) — the CI teeth, per
 * validate-adversarial-constructions (both halves: broken-fails AND
 * correct-passes). The cutover comparison itself is the local procedure in
 * adapters/CUTOVER.md, not CI — but the guards that make that procedure
 * trustworthy (describe 6) are CI teeth like the rest.
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
import {
  computeCutoverStatus,
  loadTaskSet,
  partitionByStratum,
  runEval,
  TASKS_PATH,
  type TaskScore,
  validateTaskSet,
} from "../eval/run-eval.ts";

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

describe("6. hybrid-integrity guards", () => {
  const stub = (task: EvalTask): TaskScore => ({
    task,
    rankedIds: [],
    scores: [],
    hitAt1: false,
    hitAtK: false,
    reciprocalRank: 0,
    top1Margin: null,
  });
  const allScores = taskSet.tasks.map(stub);

  // --- stratification: properties, not pinned counts -----------------------

  test("every task carries exactly one stratum: tag", () => {
    const offenders = taskSet.tasks
      .filter((t) => (t.tags ?? []).filter((tag) => tag.startsWith("stratum:")).length !== 1)
      .map((t) => t.id);
    expect(offenders).toEqual([]);
  });

  test("partition is disjoint, covers every positive, and excludes negatives", () => {
    const { main, headroom } = partitionByStratum(allScores);
    const mainIds = new Set(main.map((s) => s.task.id));
    const headroomIds = new Set(headroom.map((s) => s.task.id));
    const positiveIds = new Set(positiveTasks.map((t) => t.id));

    expect([...mainIds].filter((id) => headroomIds.has(id))).toEqual([]);
    expect(mainIds.size + headroomIds.size).toBe(positiveIds.size);
    expect([...mainIds, ...headroomIds].filter((id) => !positiveIds.has(id))).toEqual([]);
    expect(main.concat(headroom).filter((s) => s.task.negative)).toEqual([]);
  });

  test("both strata are non-degenerate (a threshold over an empty stratum is meaningless)", () => {
    const { main, headroom } = partitionByStratum(allScores);
    expect(main.length).toBeGreaterThanOrEqual(10);
    expect(headroom.length).toBeGreaterThanOrEqual(5);
  });

  test("partitionByStratum takes no repoRoot — structurally cannot read pi/tiers.yaml (#2093)", () => {
    expect(partitionByStratum.length).toBe(1);
  });

  // --- computeCutoverStatus: every branch, incl. the adversarial typo ------

  const FROZEN = { main_hit_at_k_min: 0.6 };
  const UNFROZEN = { status: "unfrozen — derive via the documented procedure" };

  const cases: Array<{
    name: string;
    thresholds: Record<string, unknown>;
    mode: "hybrid" | "bm25-only";
    hitAtK: number;
    expected: ReturnType<typeof computeCutoverStatus>;
  }> = [
    {
      name: "frozen, hybrid, above",
      thresholds: FROZEN,
      mode: "hybrid",
      hitAtK: 0.7,
      expected: "PASS",
    },
    {
      name: "frozen, hybrid, exactly at",
      thresholds: FROZEN,
      mode: "hybrid",
      hitAtK: 0.6,
      expected: "PASS",
    },
    {
      name: "frozen, hybrid, below",
      thresholds: FROZEN,
      mode: "hybrid",
      hitAtK: 0.5,
      expected: "FAIL",
    },
    {
      name: "frozen, bm25-only → NA_BM25, never a bogus FAIL",
      thresholds: FROZEN,
      mode: "bm25-only",
      hitAtK: 0.1,
      expected: "NA_BM25",
    },
    {
      name: "unfrozen, hybrid",
      thresholds: UNFROZEN,
      mode: "hybrid",
      hitAtK: 0.9,
      expected: "UNFROZEN",
    },
    {
      name: "unfrozen, bm25-only",
      thresholds: UNFROZEN,
      mode: "bm25-only",
      hitAtK: 0.9,
      expected: "UNFROZEN",
    },
    {
      name: "numeric-first: a leftover 'unfrozen' string cannot mask a frozen number",
      thresholds: { ...UNFROZEN, ...FROZEN },
      mode: "hybrid",
      hitAtK: 0.5,
      expected: "FAIL",
    },
    {
      name: "adversarial typo: misspelled key does NOT silently pass as frozen",
      thresholds: { main_hit_at_k_mim: 0.6 },
      mode: "hybrid",
      hitAtK: 0.1,
      expected: "UNFROZEN",
    },
  ];

  for (const c of cases) {
    test(`computeCutoverStatus — ${c.name}`, () => {
      expect(computeCutoverStatus(c.thresholds, c.mode, c.hitAtK)).toBe(c.expected);
    });
  }

  // --- the freeze block is itself validated --------------------------------

  const withThresholds = (thresholds: Record<string, unknown>) => ({
    ...taskSet,
    gate: { cutover_thresholds: thresholds },
  });
  const FULL_PROVENANCE = {
    main_hit_at_k_min: 0.6,
    measured_main_hit_at_k: 0.7,
    margin: 0.1,
    mode: "hybrid",
    embedding_model: "nomic-embed-text",
    embedding_model_digest: "sha256:abc",
    embedding_dimensions: 768,
    prefix_scheme: "search_document: /search_query: ",
    corpus_entries: 400,
    task_count_main_stratum: 55,
    frozen_at: "2026-07-22",
    frozen_commit: "deadbeef",
    procedure: "adapters/CUTOVER.md",
  };

  test("the shipped task set validates clean", () => {
    expect(validateTaskSet(taskSet)).toEqual([]);
  });

  test("a misspelled threshold key is a GATE FAIL, not a silent permanent UNFROZEN", () => {
    const errors = validateTaskSet(withThresholds({ main_hit_at_k_mim: 0.6 }));
    expect(errors.some((e) => e.includes("unknown key"))).toBe(true);
  });

  test("neither status nor numeric threshold is rejected", () => {
    expect(validateTaskSet(withThresholds({})).some((e) => e.includes("exactly one of"))).toBe(
      true,
    );
  });

  test("both status and numeric threshold is rejected", () => {
    const errors = validateTaskSet(
      withThresholds({ ...FULL_PROVENANCE, status: "unfrozen — stale" }),
    );
    expect(errors.some((e) => e.includes("exactly one of"))).toBe(true);
  });

  test("an out-of-range threshold is rejected", () => {
    const errors = validateTaskSet(withThresholds({ ...FULL_PROVENANCE, main_hit_at_k_min: 1.5 }));
    expect(errors.some((e) => e.includes("outside [0, 1]"))).toBe(true);
  });

  test("a frozen threshold must carry its provenance", () => {
    const { embedding_model_digest, frozen_commit, ...partial } = FULL_PROVENANCE;
    const errors = validateTaskSet(withThresholds(partial));
    expect(errors.some((e) => e.includes("embedding_model_digest"))).toBe(true);
    expect(errors.some((e) => e.includes("frozen_commit"))).toBe(true);
  });

  test("a fully-provenanced frozen block validates clean", () => {
    expect(validateTaskSet(withThresholds(FULL_PROVENANCE))).toEqual([]);
  });

  // --- a fake hybrid run cannot report GATE PASS ---------------------------

  test("--with-embeddings against a dead endpoint is a GATE FAIL, not a silent BM25 PASS", async () => {
    const run = await runEval({
      withEmbeddings: true,
      repoRoot: REPO_ROOT,
      // Reserved-for-testing port: dead on any dev machine, so this never
      // goes hybrid just because the author happens to be running ollama.
      embedEndpoint: "http://127.0.0.1:1",
    });
    expect(run.mode).toBe("bm25-only");
    expect(run.gateStatus).toBe("FAIL");
    expect(run.gateIssues.some((i) => i.includes("index degraded"))).toBe(true);
  });
});
