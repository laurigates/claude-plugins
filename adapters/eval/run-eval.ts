/**
 * Eval runner (DESIGN §5.3).
 *
 * Smoke mode (default) is BM25-only, zero network — CI has no ollama and the
 * smoke gate must never flake on the soft dependency. `--with-embeddings`
 * exercises hybrid fusion when an endpoint is reachable (local dev; the
 * configuration the cutover threshold is derived on — see adapters/CUTOVER.md).
 *
 * All retrieval/token metrics are informational in CI. `GATE STATUS` asserts
 * only that the eval *machinery* ran (tasks parse + schema-validate, index
 * builds, every task scored, per-mode and hybrid-integrity invariants hold);
 * the correctness teeth live in tests/eval-meta.test.ts. CI never gates on the
 * cutover threshold — that comparison is the local procedure in CUTOVER.md.
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

/**
 * The headroom stratum — positives whose expected skill was never in any
 * curated install set. Everything else positive is the main stratum, so a
 * newly added stratum lands in main by default (partition stays covering).
 */
const HEADROOM_STRATA = new Set(["stratum:excluded"]);

/** Every key `gate.cutover_thresholds` may carry (CUTOVER.md "Freeze"). */
const THRESHOLD_KEYS = new Set([
  "status",
  "main_hit_at_k_min",
  "measured_main_hit_at_k",
  "margin",
  "mode",
  "embedding_model",
  "embedding_model_digest",
  "embedding_dimensions",
  "prefix_scheme",
  "corpus_entries",
  "task_count_main_stratum",
  "frozen_at",
  "frozen_commit",
  "procedure",
]);

/** Provenance a frozen (numeric) threshold must carry to be interpretable. */
const REQUIRED_PROVENANCE_KEYS = [
  "measured_main_hit_at_k",
  "margin",
  "mode",
  "embedding_model",
  "embedding_model_digest",
  "embedding_dimensions",
  "prefix_scheme",
  "corpus_entries",
  "task_count_main_stratum",
  "frozen_at",
  "frozen_commit",
  "procedure",
] as const;

export function loadTaskSet(path: string = TASKS_PATH): TaskSet {
  return JSON.parse(readFileSync(path, "utf8")) as TaskSet;
}

/**
 * Validate the freeze block itself. The failure this exists to prevent: a
 * misspelled threshold key (`main_hit_at_k_mim`) would otherwise leave the
 * cutover silently and permanently UNFROZEN — a green gate that asserts
 * nothing. An unknown key is a GATE FAIL, not a shrug.
 */
function validateThresholds(thresholds: Record<string, unknown>): string[] {
  const errors: string[] = [];
  for (const key of Object.keys(thresholds)) {
    if (!THRESHOLD_KEYS.has(key)) {
      errors.push(`cutover_thresholds: unknown key ${JSON.stringify(key)}`);
    }
  }

  const unfrozen = typeof thresholds.status === "string" && thresholds.status.includes("unfrozen");
  const frozen = typeof thresholds.main_hit_at_k_min === "number";
  if (unfrozen === frozen) {
    errors.push(
      "cutover_thresholds: need exactly one of a status containing 'unfrozen' " +
        "or a numeric main_hit_at_k_min",
    );
  }

  if (frozen) {
    const min = thresholds.main_hit_at_k_min as number;
    if (!Number.isFinite(min) || min < 0 || min > 1) {
      errors.push(`cutover_thresholds: main_hit_at_k_min ${min} outside [0, 1]`);
    }
    for (const key of REQUIRED_PROVENANCE_KEYS) {
      if (!(key in thresholds)) {
        errors.push(`cutover_thresholds: frozen threshold missing provenance field ${key}`);
      }
    }
  }
  return errors;
}

/**
 * Decide the cutover verdict. Pure so the freeze can be table-tested.
 *
 * **Numeric-first precedence**: a leftover `status: "unfrozen"` string can
 * never mask a frozen number. The frozen threshold is hybrid-scoped — the
 * default BM25-only CI run reports NA_BM25, never a bogus FAIL.
 */
export function computeCutoverStatus(
  thresholds: Record<string, unknown>,
  mode: "hybrid" | "bm25-only",
  mainHitAtK: number,
): "UNFROZEN" | "PASS" | "FAIL" | "NA_BM25" {
  if (typeof thresholds.main_hit_at_k_min === "number") {
    if (mode !== "hybrid") return "NA_BM25";
    return mainHitAtK >= thresholds.main_hit_at_k_min ? "PASS" : "FAIL";
  }
  return "UNFROZEN";
}

/**
 * Partition positives into the main and headroom strata using the task set's
 * own `stratum:` tags.
 *
 * Takes no repoRoot **by construction**: the partition must not depend on
 * `pi/tiers.yaml`, which #2093 deletes. A tiers-derived partition would make
 * the frozen threshold evaluate FAIL forever at exactly the moment the gate
 * is meant to authorize that deletion.
 */
export function partitionByStratum(scores: TaskScore[]): {
  main: TaskScore[];
  headroom: TaskScore[];
} {
  const positive = scores.filter((s) => !s.task.negative);
  const isHeadroom = (s: TaskScore) => (s.task.tags ?? []).some((t) => HEADROOM_STRATA.has(t));
  return {
    main: positive.filter((s) => !isHeadroom(s)),
    headroom: positive.filter(isHeadroom),
  };
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
  } else {
    errors.push(...validateThresholds(tasks.gate.cutover_thresholds));
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

export interface TaskScore {
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
  /** Non-nullable by design — the partition is tag-pinned, never tiers-derived. */
  main: StratumMetrics;
  headroom: StratumMetrics;
  degradedQueries: number;
  negMargins: number[];
  posMargins: number[];
  baselinePiTokens: number | null;
  baselineOcTokensEstimated: number;
  adapterTokens: number;
  scores: TaskScore[];
  cutoverStatus: "UNFROZEN" | "PASS" | "FAIL" | "NA_BM25";
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
  /** Override the embedding endpoint (guard tests point at a dead port). */
  embedEndpoint?: string;
  embedModel?: string;
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
    embed: {
      disabled: !options.withEmbeddings,
      ...(options.embedEndpoint !== undefined ? { endpoint: options.embedEndpoint } : {}),
      ...(options.embedModel !== undefined ? { model: options.embedModel } : {}),
    },
  });
  if (index.entries.length === 0) gateIssues.push("index built with zero entries");
  if (!options.withEmbeddings && index.mode !== "bm25-only") {
    gateIssues.push(`smoke mode invariant violated: mode=${index.mode}`);
  }
  // The smoke invariant above is one-directional: without this, a
  // --with-embeddings run that silently fell back still printed STATUS=PASS.
  if (options.withEmbeddings && index.mode !== "hybrid") {
    gateIssues.push(`--with-embeddings requested but index degraded: mode=${index.mode}`);
  }

  const scores = await scoreTasks(index, taskSet.tasks, k);
  if (scores.length !== taskSet.tasks.length) gateIssues.push("not every task scored");

  // Per-query embedding failures leave mode === "hybrid" and are otherwise
  // invisible (core/search.ts swallows them for the shipping path). A
  // threshold derived from a partly-BM25 run would be fiction.
  if (options.withEmbeddings && index.degradedQueries > 0) {
    gateIssues.push(
      `${index.degradedQueries} queries degraded to BM25 (last: ${index.lastDegradeReason})`,
    );
  }

  // Score-shape sanity: RRF is hard-capped at 2/RRF_K = 0.0333, while raw
  // BM25 tops ~1-10. A hybrid run whose scores look like BM25 is not hybrid,
  // whatever `mode` claims.
  const maxScore = scores.reduce((acc, s) => Math.max(acc, ...s.scores), 0);
  if (options.withEmbeddings && maxScore > 0.05) {
    gateIssues.push(`hybrid run has BM25-shaped scores (max=${maxScore.toFixed(4)} > 0.05)`);
  }

  // Baselines (runtime-derived, never stored per task).
  const piBaseline: BaselineSet | null = derivePiBaseline(repoRoot);
  const ocBaseline = deriveOcBaseline(repoRoot);
  const baselineArm = piBaseline === null ? "ABSENT" : "PRESENT";

  const positive = scores.filter((s) => !s.task.negative);
  const negative = scores.filter((s) => s.task.negative);

  // Tag-pinned partition (CUTOVER.md). RETRIEVAL_MAIN means exactly "hybrid
  // retrieval quality on the main positives" and asserts nothing about any
  // baseline — the DESIGN §5.2 "in-tier baseline reachability is 1.0 by
  // construction" reading is retired along with the tiers-derived stratum.
  const { main: mainScores, headroom: headroomScores } = partitionByStratum(scores);
  if (mainScores.length === 0) gateIssues.push("main stratum is empty");
  if (headroomScores.length === 0) gateIssues.push("headroom stratum is empty");

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
  // CUTOVER.md freeze procedure.
  const thresholds = taskSet.gate?.cutover_thresholds ?? {};
  const mainMetrics = aggregate(mainScores);
  const cutoverStatus = computeCutoverStatus(thresholds, index.mode, mainMetrics.hitAtK);

  return {
    mode: index.mode,
    k,
    baselineArm,
    main: mainMetrics,
    headroom: aggregate(headroomScores),
    degradedQueries: index.degradedQueries,
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
  lines.push(
    `=== EVAL === MODE=${run.mode} K=${run.k} TASKS=${run.scores.length} DEGRADED_QUERIES=${run.degradedQueries}`,
  );
  lines.push(
    `=== RETRIEVAL_MAIN === HIT_AT_1=${fmt(run.main.hitAt1)} HIT_AT_K=${fmt(run.main.hitAtK)} MRR=${fmt(run.main.mrr)} TASKS=${run.main.taskCount}`,
  );
  lines.push(
    `=== RETRIEVAL_HEADROOM === HIT_AT_1=${fmt(run.headroom.hitAt1)} HIT_AT_K=${fmt(run.headroom.hitAtK)} MRR=${fmt(run.headroom.mrr)} TASKS=${run.headroom.taskCount}`,
  );
  lines.push(
    `=== NEGATIVES === TOP1_MARGIN_NEG_P50=${fmt(percentile(run.negMargins, 50))} TOP1_MARGIN_NEG_P90=${fmt(percentile(run.negMargins, 90))} TOP1_MARGIN_POS_P50=${fmt(percentile(run.posMargins, 50))} TOP1_MARGIN_POS_P90=${fmt(percentile(run.posMargins, 90))}`,
  );
  lines.push(
    `=== TOKENS === BASELINE_PI_TOKENS=${run.baselinePiTokens ?? "NA"} BASELINE_OC_TOKENS_ESTIMATED=${run.baselineOcTokensEstimated} ADAPTER_TOKENS=${run.adapterTokens} BASELINE_ARM=${run.baselineArm}`,
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
