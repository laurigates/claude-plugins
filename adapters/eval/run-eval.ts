/**
 * Eval runner (DESIGN §5.3).
 *
 * Smoke mode (default) is BM25-only, zero network — CI has no ollama and the
 * smoke gate must never flake on the soft dependency. `--with-embeddings`
 * exercises hybrid fusion when an endpoint is reachable (local dev; the
 * configuration the cutover thresholds are derived on, §5.6).
 *
 * All retrieval/token metrics are informational in CI. `GATE STATUS` asserts
 * only that the eval *machinery* ran (tasks parse + schema-validate, index
 * builds, every task scored, per-mode invariants hold); the correctness
 * teeth live in tests/eval-meta.test.ts. CI never gates on the cutover
 * thresholds — that comparison is the §5.6 local procedure.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import {
  estimateTokens,
  renderInjectedBlock,
  SEARCH_SKILLS_TOOL_DESCRIPTION,
} from "../core/render.ts";
import { buildIndex, type SkillIndex } from "../core/search.ts";
import { DEFAULT_K } from "../core/types.ts";
import { type BaselineSet, deriveOcBaseline, derivePiBaseline, listingTokens } from "./baseline.ts";
import { makeRetrievalProxyProbe } from "./probes.ts";
import { type EvalTask, hybridRanker, type TaskSet } from "./rankers.ts";

const EVAL_DIR = import.meta.dir;
const REPO_ROOT = resolve(EVAL_DIR, "..", "..");
export const TASKS_PATH = join(EVAL_DIR, "tasks.json");

const TAG_RE = /^(stratum|domain):[a-z0-9-]+$/;

export function loadTaskSet(path: string = TASKS_PATH): TaskSet {
  return JSON.parse(readFileSync(path, "utf8")) as TaskSet;
}

/**
 * Schema checks (DESIGN §5.5 item 5). Returns human-readable violations;
 * empty array = valid.
 */
export function validateTaskSet(tasks: TaskSet): string[] {
  const errors: string[] = [];
  if (typeof tasks.gate !== "object" || tasks.gate === null) {
    errors.push("missing top-level gate block");
  } else if (
    typeof tasks.gate.cutover_thresholds !== "object" ||
    tasks.gate.cutover_thresholds === null
  ) {
    errors.push("gate block missing cutover_thresholds");
  }
  if (tasks.k !== DEFAULT_K) {
    errors.push(`tasks.k (${tasks.k}) !== DEFAULT_K (${DEFAULT_K})`);
  }
  const seenIds = new Set<string>();
  for (const task of tasks.tasks) {
    for (const field of [
      "id",
      "prompt",
      "expected_skills",
      "acceptable_skills",
      "negative",
      "tags",
      "provenance",
    ] as const) {
      if (!(field in task)) errors.push(`${task.id ?? "?"}: missing field ${field}`);
    }
    if (!Array.isArray(task.acceptable_skills)) {
      errors.push(`${task.id}: acceptable_skills must be an array (empty when none)`);
    }
    if (seenIds.has(task.id)) errors.push(`duplicate task id ${task.id}`);
    seenIds.add(task.id);
    for (const tag of task.tags ?? []) {
      if (!TAG_RE.test(tag)) errors.push(`${task.id}: bad tag ${JSON.stringify(tag)}`);
    }
    if (!(task.tags ?? []).some((t) => t.startsWith("stratum:"))) {
      errors.push(`${task.id}: no stratum:* tag`);
    }
  }
  return errors;
}

interface TaskScore {
  task: EvalTask;
  rankedIds: string[];
  scores: number[];
  hitAt1: boolean;
  hitAtK: boolean;
  reciprocalRank: number;
  top1Margin: number | null;
}

export interface StratumMetrics {
  taskCount: number;
  hitAt1: number;
  hitAtK: number;
  mrr: number;
}

export interface EvalRun {
  mode: "hybrid" | "bm25-only";
  k: number;
  baselineArm: "PRESENT" | "ABSENT";
  inTier: StratumMetrics | null;
  excluded: StratumMetrics;
  negMargins: number[];
  posMargins: number[];
  baselinePiTokens: number | null;
  baselineOcTokensEstimated: number;
  adapterTokens: number;
  scores: TaskScore[];
  cutoverStatus: "UNFROZEN" | "PASS" | "FAIL";
  gateStatus: "PASS" | "FAIL";
  gateIssues: string[];
}

function aggregate(scores: TaskScore[]): StratumMetrics {
  const n = scores.length;
  if (n === 0) return { taskCount: 0, hitAt1: 0, hitAtK: 0, mrr: 0 };
  const sum = (f: (s: TaskScore) => number) => scores.reduce((acc, s) => acc + f(s), 0);
  return {
    taskCount: n,
    hitAt1: sum((s) => (s.hitAt1 ? 1 : 0)) / n,
    hitAtK: sum((s) => (s.hitAtK ? 1 : 0)) / n,
    mrr: sum((s) => s.reciprocalRank) / n,
  };
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, rank)] as number;
}

export async function scoreTasks(
  index: SkillIndex,
  tasks: EvalTask[],
  k: number,
): Promise<TaskScore[]> {
  const probe = makeRetrievalProxyProbe(hybridRanker(index), k, () => 0);
  const scores: TaskScore[] = [];
  for (const task of tasks) {
    const results = await index.search(task.prompt, k);
    const rankedIds = results.map((r) => r.id);
    // Keep the probe seam exercised (same ranker, same ids).
    await probe("pi", "adapter", task);
    const targets = new Set([...task.expected_skills, ...task.acceptable_skills]);
    const expected = new Set(task.expected_skills);
    const firstTargetRank = rankedIds.findIndex((id) => targets.has(id));
    scores.push({
      task,
      rankedIds,
      scores: results.map((r) => r.score),
      hitAt1: rankedIds.length > 0 && expected.has(rankedIds[0] as string),
      hitAtK: firstTargetRank >= 0,
      reciprocalRank: firstTargetRank >= 0 ? 1 / (firstTargetRank + 1) : 0,
      top1Margin:
        results.length >= 2
          ? (results[0] as { score: number }).score - (results[1] as { score: number }).score
          : results.length === 1
            ? (results[0] as { score: number }).score
            : null,
    });
  }
  return scores;
}

export async function runEval(options: {
  withEmbeddings: boolean;
  tasksPath?: string;
  repoRoot?: string;
}): Promise<EvalRun> {
  const repoRoot = options.repoRoot ?? REPO_ROOT;
  const gateIssues: string[] = [];

  const taskSet = loadTaskSet(options.tasksPath ?? TASKS_PATH);
  const schemaErrors = validateTaskSet(taskSet);
  gateIssues.push(...schemaErrors);
  const k = DEFAULT_K;

  const index = await buildIndex({
    repoRoot,
    target: "foreign",
    embed: { disabled: !options.withEmbeddings },
  });
  if (index.entries.length === 0) gateIssues.push("index built with zero entries");
  if (!options.withEmbeddings && index.mode !== "bm25-only") {
    gateIssues.push(`smoke mode invariant violated: mode=${index.mode}`);
  }

  const scores = await scoreTasks(index, taskSet.tasks, k);
  if (scores.length !== taskSet.tasks.length) gateIssues.push("not every task scored");

  // Baselines (runtime-derived, never stored per task).
  const piBaseline: BaselineSet | null = derivePiBaseline(repoRoot);
  const ocBaseline = deriveOcBaseline(repoRoot);
  const baselineArm = piBaseline === null ? "ABSENT" : "PRESENT";

  const positive = scores.filter((s) => !s.task.negative);
  const negative = scores.filter((s) => s.task.negative);

  // A task is in-tier iff its expected skill is in the installed set — so
  // baseline reachability is constant 1.0 on that stratum by construction
  // (DESIGN §5.2 "honest reading"). With the baseline absent, everything
  // degrades to headroom-only reporting.
  let inTierScores: TaskScore[] = [];
  let excludedScores: TaskScore[] = positive;
  if (piBaseline !== null) {
    inTierScores = positive.filter((s) =>
      s.task.expected_skills.some((id) => piBaseline.ids.has(id)),
    );
    excludedScores = positive.filter(
      (s) => !s.task.expected_skills.some((id) => piBaseline.ids.has(id)),
    );
  }

  // Metric B — standing tokens/turn (chars/4 over the shared render).
  const baselinePiTokens = piBaseline === null ? null : listingTokens(piBaseline.skills).total;
  const baselineOcTokensEstimated = listingTokens(ocBaseline.skills).total;
  const toolDescriptionTokens = estimateTokens(SEARCH_SKILLS_TOOL_DESCRIPTION);
  const idToEntry = new Map(index.entries.map((e) => [e.id, e]));
  let injectedSum = 0;
  for (const score of positive) {
    const ranked = score.rankedIds
      .map((id) => idToEntry.get(id))
      .filter((e) => e !== undefined)
      .map((e) => ({ id: e.id, description: e.description, path: e.path }));
    injectedSum += estimateTokens(renderInjectedBlock([], ranked, k));
  }
  const adapterTokens =
    toolDescriptionTokens + (positive.length > 0 ? Math.round(injectedSum / positive.length) : 0);

  // Cutover block — informational; numeric thresholds exist only after the
  // §5.6 freeze procedure.
  const thresholds = taskSet.gate?.cutover_thresholds ?? {};
  let cutoverStatus: EvalRun["cutoverStatus"] = "UNFROZEN";
  const inTierMetrics = piBaseline === null ? null : aggregate(inTierScores);
  if (typeof thresholds.status === "string" && thresholds.status.includes("unfrozen")) {
    cutoverStatus = "UNFROZEN";
  } else if (typeof thresholds.in_tier_hit_at_k_min === "number") {
    cutoverStatus =
      inTierMetrics !== null && inTierMetrics.hitAtK >= thresholds.in_tier_hit_at_k_min
        ? "PASS"
        : "FAIL";
  }

  return {
    mode: index.mode,
    k,
    baselineArm,
    inTier: inTierMetrics,
    excluded: aggregate(excludedScores),
    negMargins: negative.map((s) => s.top1Margin).filter((m): m is number => m !== null),
    posMargins: positive.map((s) => s.top1Margin).filter((m): m is number => m !== null),
    baselinePiTokens,
    baselineOcTokensEstimated,
    adapterTokens,
    scores,
    cutoverStatus,
    gateStatus: gateIssues.length === 0 ? "PASS" : "FAIL",
    gateIssues,
  };
}

function fmt(value: number | null): string {
  return value === null ? "NA" : value.toFixed(4);
}

export function renderReport(run: EvalRun): string {
  const lines: string[] = [];
  lines.push(`=== EVAL === MODE=${run.mode} K=${run.k} TASKS=${run.scores.length}`);
  if (run.inTier !== null) {
    lines.push(
      `=== RETRIEVAL_IN_TIER === HIT_AT_1=${fmt(run.inTier.hitAt1)} HIT_AT_K=${fmt(run.inTier.hitAtK)} MRR=${fmt(run.inTier.mrr)} BASELINE_ARM=${run.baselineArm}`,
    );
  } else {
    lines.push(
      `=== RETRIEVAL_IN_TIER === HIT_AT_1=NA HIT_AT_K=NA MRR=NA BASELINE_ARM=${run.baselineArm}`,
    );
  }
  lines.push(
    `=== RETRIEVAL_EXCLUDED_STRATUM === HIT_AT_1=${fmt(run.excluded.hitAt1)} HIT_AT_K=${fmt(run.excluded.hitAtK)} MRR=${fmt(run.excluded.mrr)}`,
  );
  lines.push(
    `=== NEGATIVES === TOP1_MARGIN_NEG_P50=${fmt(percentile(run.negMargins, 50))} TOP1_MARGIN_NEG_P90=${fmt(percentile(run.negMargins, 90))} TOP1_MARGIN_POS_P50=${fmt(percentile(run.posMargins, 50))} TOP1_MARGIN_POS_P90=${fmt(percentile(run.posMargins, 90))}`,
  );
  lines.push(
    `=== TOKENS === BASELINE_PI_TOKENS=${run.baselinePiTokens ?? "NA"} BASELINE_OC_TOKENS_ESTIMATED=${run.baselineOcTokensEstimated} ADAPTER_TOKENS=${run.adapterTokens}`,
  );
  lines.push(`=== CUTOVER === STATUS=${run.cutoverStatus}`);
  lines.push(`=== GATE === STATUS=${run.gateStatus}`);
  for (const issue of run.gateIssues) lines.push(`GATE_ISSUE=${issue}`);
  return lines.join("\n");
}

async function main(): Promise<void> {
  const withEmbeddings = process.argv.includes("--with-embeddings");
  const run = await runEval({ withEmbeddings });
  const report = renderReport(run);
  console.log(report);

  const resultsDir = join(EVAL_DIR, "results");
  mkdirSync(resultsDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const resultPath = join(resultsDir, `${stamp}-${run.mode}.json`);
  const { scores, ...summary } = run;
  writeFileSync(
    resultPath,
    JSON.stringify(
      {
        ...summary,
        report,
        perTask: scores.map((s) => ({
          id: s.task.id,
          rankedIds: s.rankedIds,
          hitAt1: s.hitAt1,
          hitAtK: s.hitAtK,
          reciprocalRank: s.reciprocalRank,
          top1Margin: s.top1Margin,
        })),
      },
      null,
      2,
    ),
  );
  console.log(`RESULTS_FILE=${resultPath}`);
  process.exit(run.gateStatus === "PASS" ? 0 : 1);
}

if (import.meta.main) {
  await main();
}
