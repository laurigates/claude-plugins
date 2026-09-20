/**
 * evaluate-plugin-batch.workflow.js — capped per-skill fan-out for
 * `/evaluate:plugin-batch`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation. Invoking this file against empty `args`
 * spends real opus agents to discover that it is a template.
 *
 * Shape: fan-out-and-aggregate.
 *   Fan-out unit — one `evaluate-skill` workflow run per eval-ready skill.
 *   Loop bound   — the inventory agent's `skills[]`, derived from
 *                  `evaluate-plugin/scripts/inspect_eval.sh --plugin-dir
 *                  <plugin>`. Never a prose "for each skill".
 *   Barrier      — Aggregate. `aggregate_benchmark.sh` walks the filesystem for
 *                  every skill's `eval-results/benchmark.json`, so its
 *                  denominators are only correct once EVERY cell has finished
 *                  writing. No single cell can know the plugin-level numbers.
 *
 * Three things this deliberately does NOT do:
 *   1. No per-skill worktree-isolated "normalize benchmark" stage. That would
 *      spend one worktree agent per skill to perform a Read — and a
 *      worktree reader cannot see a file another agent wrote anyway, so the
 *      normalization it performed would be of its own empty tree.
 *   2. No uncapped fan-out. Above CAP the run ABORTS rather than truncating:
 *      a silently-shortened sweep reports a pass rate over a denominator
 *      nobody chose.
 *   3. The workflow's own count is never the authority. `included.length` is a
 *      CROSS-CHECK against what `aggregate_benchmark.sh` actually found on
 *      disk; the script's numbers are the report's numbers.
 *
 * NOTE ON EMPTINESS: until a golden set of `evals.json` files exists this
 * harness legitimately finds almost nothing to run. An abort with
 * `reason: 'below-floor'` on a plugin with one eval-ready skill is the designed
 * outcome, not a failure — `.claude/rules/skill-evaluation.md` scopes eval
 * coverage to a small canary set on purpose.
 */

export const meta = {
  name: 'evaluate-plugin-batch',
  description: 'Batch-evaluate a plugin\'s eval-ready skills and aggregate one plugin-level report',
  phases: [
    { title: 'Discover', detail: 'inventory skills and evals — evaluates nothing' },
    { title: 'Evaluate', detail: 'one evaluate-skill run per eval-ready skill, <=--parallel N in flight' },
    { title: 'Aggregate', detail: 'aggregate_benchmark.sh owns the denominators' },
  ],
}

// The name `evaluate-skill`'s harness is registered under. #2172 defines it;
// this file calls it. Both children must agree on this literal — a mismatch
// does not degrade, it throws (see WAVE 1 handling below).
const EVALUATE_SKILL_WORKFLOW = 'evaluate-skill'

// Refuse above this many eval-ready skills. A CEILING, and it ABORTS: the
// golden set is deliberately ~15-25 skills, so a request to sweep more than
// this is a sign the caller meant a different scope, and a truncated sweep
// would publish a pass rate over a denominator nobody picked.
const CAP = 25

// Below this many eval-ready skills the harness is pure overhead: one skill is
// exactly what `/evaluate:skill` already does, without an inventory agent, a
// nested workflow and an aggregate agent on top. A FLOOR, not a knob.
const FLOOR = 2

// Per-skill cartesian ceiling handed to each child (`len(evals) x runs x
// configs`). It bounds ONE cell so a pathological skill cannot consume the
// batch's shared agent budget. The child owns the enforcement; we own the value.
const CELL_CAP = 30

// Default wave width. `args.parallel` (the skill's `--parallel N`) always wins
// over this — the harness never supersedes the caller's concurrency choice. The
// platform separately caps concurrency at min(16, CPUs-2) per workflow, and a
// nested child SHARES this run's cap and agent counter.
const DEFAULT_WAVE = 1

const INVENTORY_SCHEMA = {
  type: 'object',
  required: ['plugin', 'status', 'skillCount', 'evalsCount', 'skills'],
  additionalProperties: false,
  properties: {
    plugin: { type: 'string' },
    // Mirrors the script's own STATUS=. ERROR means the inventory could not be
    // taken (no skills/ dir) — distinct from "took the inventory, found none".
    status: { type: 'string', enum: ['OK', 'ERROR'] },
    skillCount: { type: 'integer' },
    evalsCount: { type: 'integer' },
    skills: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'dir', 'path', 'hasEvals'],
        additionalProperties: false,
        properties: {
          name: { type: 'string' },
          dir: { type: 'string' },
          path: { type: 'string' },
          // A boolean, not a judgement: the file is in the script's === EVALS ===
          // list or it is not.
          hasEvals: { type: 'boolean' },
        },
      },
    },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  required: [
    'status',
    'denominatorSource',
    'skillsEvaluated',
    'skillsTotal',
    'overallPassRate',
    'crossCheck',
    'rows',
  ],
  additionalProperties: false,
  properties: {
    // `partial-sweep` is the ANTI-LAZINESS signal, not a rounding error: it
    // means the script found a different number of benchmarks than this run
    // dispatched, so some cell did not land. It must never read as `complete`.
    status: { type: 'string', enum: ['complete', 'partial-sweep', 'aggregate-failed'] },
    // A one-value enum, on purpose: the report must state that its numbers came
    // from the script, so a hand-counted denominator is structurally impossible.
    denominatorSource: { type: 'string', enum: ['aggregate_benchmark.sh'] },
    skillsEvaluated: { type: 'integer' },
    skillsTotal: { type: 'integer' },
    overallPassRate: { type: 'number' },
    crossCheck: {
      type: 'object',
      required: ['workflowIncluded', 'scriptEvaluated', 'agrees'],
      additionalProperties: false,
      properties: {
        workflowIncluded: { type: 'integer' },
        scriptEvaluated: { type: 'integer' },
        agrees: { type: 'boolean' },
      },
    },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['skill', 'numEvals', 'meanPassRate', 'status'],
        additionalProperties: false,
        properties: {
          skill: { type: 'string' },
          numEvals: { type: 'integer' },
          meanPassRate: { type: 'number' },
          status: { type: 'string', enum: ['PASS', 'PARTIAL', 'FAIL'] },
        },
      },
    },
  },
}

const INVENTORY_PROMPT = (plugin) => `
Inventory the skills of the plugin at directory "${plugin}".

Run exactly:
  bash evaluate-plugin/scripts/inspect_eval.sh --plugin-dir ${plugin}

READ-ONLY. Evaluate NOTHING. Do not run /evaluate:skill, do not create or edit
an evals.json, do not write any file.

That script prints KEY=VALUE lines (SKILLS_DIR_EXISTS, SKILL_COUNT, EVALS_COUNT)
followed by two path lists under "=== SKILLS ===" and "=== EVALS ===". It does
NOT emit a per-skill hasEvals flag — derive it by joining the two lists on the
skill directory.

Return:
  plugin      — "${plugin}"
  status      — OK when SKILLS_DIR_EXISTS=true; ERROR when the script reported
                STATUS=ERROR or could not run at all. ERROR means "could not
                take the inventory", which is NOT the same as "found no skills".
  skillCount  — the script's SKILL_COUNT
  evalsCount  — the script's EVALS_COUNT
  skills      — one row per SKILL.md path the script listed:
                  name     the skill directory's basename
                  dir      the skill directory, repo-relative
                  path     the SKILL.md path, repo-relative
                  hasEvals true when <dir>/evals.json appears in the EVALS list
`

const AGGREGATE_PROMPT = (plugin, included, cells) => `
You are the aggregation stage of a plugin-level evaluation. Every per-skill
evaluation has already finished writing its own eval-results/benchmark.json.
Produce ONE plugin report.

Run exactly:
  bash evaluate-plugin/scripts/aggregate_benchmark.sh ${plugin}

THE DENOMINATORS ARE THE SCRIPT'S, NOT YOURS. Do not count skills yourself, do
not recompute a pass rate, and do not "correct" the script's numbers against the
cell results below. On success the script writes
${plugin}/eval-results/plugin-benchmark.json — read it and take:
  skillsEvaluated  <- .metadata.skills_evaluated
  skillsTotal      <- .metadata.skills_total
  overallPassRate  <- .summary.overall_pass_rate
  rows             <- .skills[] as {skill: .skill_name, numEvals: .num_evals,
                      meanPassRate: .mean_pass_rate, status: .status}

Three shapes to report honestly rather than smooth over:
  - A cell returned {"mode": "inline"}. It fell below the child's own floor and
    wrote no benchmark, so the script cannot have counted it.
  - The script prints "No benchmark results found" and writes NO file. Then
    scriptEvaluated is 0 and no rows exist.
  - The script exits non-zero or its directory is missing. Then status is
    "aggregate-failed" and every numeric field is 0 with rows empty.

CROSS-CHECK (this is the point of the stage):
  workflowIncluded = ${included}   — cells this run dispatched
  scriptEvaluated  = skillsEvaluated — benchmarks the script actually found
  agrees           = the two are equal

  status = "complete" only when agrees is true AND the script ran.
  status = "partial-sweep" when they disagree. A disagreement means a cell did
  not land its benchmark — it is the anti-laziness signal this stage exists for,
  never a rounding error, and must never be reported as "complete".

Per-cell results from this run, for your own diagnosis only — they are NOT a
source of denominators:
${JSON.stringify(cells, null, 2)}
`

// `args` may arrive stringified.
const INPUT = (typeof args === 'string') ? JSON.parse(args) : args
const {
  plugin,
  createMissingEvals = false,
  parallel: parallelArg,
  runs = 1,
  cap: capArg,
} = INPUT ?? {}

if (!plugin) {
  log('no plugin named in args — nothing to inventory; abort')
  return { abort: true, reason: 'no-plugin' }
}

// --parallel N is the caller's, and it is honoured verbatim. Only a value that
// is not a positive integer falls back to the default, and the fallback is
// logged rather than applied silently.
let WAVE = DEFAULT_WAVE
if (parallelArg !== undefined) {
  const n = Number(parallelArg)
  if (Number.isInteger(n) && n > 0) {
    WAVE = n
  } else {
    log(`--parallel ${parallelArg} is not a positive integer — falling back to ${DEFAULT_WAVE}`)
  }
}

const cap = Number.isInteger(capArg) && capArg > 0 ? capArg : CAP

phase('Discover')
const inv = await agent(INVENTORY_PROMPT(plugin), {
  label: 'inventory',
  phase: 'Discover',
  schema: INVENTORY_SCHEMA,
  model: 'opus',
  effort: 'low',
})

if (!inv) {
  log('inventory agent returned null — no loop bound, so there is nothing to fan out over; abort')
  return { abort: true, reason: 'inventory-null' }
}
if (inv.status === 'ERROR') {
  log(`inspect_eval.sh reported STATUS=ERROR for ${plugin} — could not take an inventory; abort`)
  return { abort: true, reason: 'inventory-error', plugin }
}

// Eval-readiness is a FILE that exists or does not. No agent classifies this.
const included = inv.skills.filter((s) => s.hasEvals || createMissingEvals)
const skipped = inv.skills
  .filter((s) => !included.includes(s))
  .map((s) => ({ ...s, reason: 'no evals.json and --create-missing-evals not set' }))

log(`${inv.skills.length} skill(s) in ${plugin}: ${included.length} eval-ready, ${skipped.length} skipped`)

// The ceiling ABORTS. Truncating here would publish a pass rate over a
// denominator nobody chose, which is exactly the number this skill exists to
// produce correctly.
if (included.length > cap) {
  log(`${included.length} eval-ready skills exceeds the cap of ${cap} — refusing to sweep a truncated set; abort`)
  return { abort: true, reason: 'above-cap', included: included.length, cap }
}

// The floor is as load-bearing as the ceiling: one skill is /evaluate:skill's
// job, and running it through an inventory agent plus an aggregate agent costs
// more than the thing it replaces.
if (included.length < FLOOR) {
  log(`${included.length} eval-ready skill(s) (< ${FLOOR}) — /evaluate:skill is the cheaper path; abort`)
  return { abort: true, reason: 'below-floor', included: included.length, floor: FLOOR, skipped }
}

phase('Evaluate')
log(`dispatching ${included.length} evaluate-skill run(s), <=${WAVE} in flight (--parallel)`)
const cells = []
for (let i = 0; i < included.length; i += WAVE) {
  const wave = included.slice(i, i + WAVE)
  const got = await parallel(
    wave.map((s) => async () => {
      try {
        // Nesting is ONE level: this call is legal here, and `evaluate-skill`'s
        // own harness must contain no workflow() call of its own.
        // `skillDir` is REQUIRED by the child (it derives the plugin and skill
        // name from it and aborts when it is empty). The inventory already has
        // it, so it is passed rather than re-derived.
        const r = await workflow(EVALUATE_SKILL_WORKFLOW, {
          skill: `${plugin}/${s.name}`,
          skillDir: s.dir,
          createEvals: createMissingEvals,
          runs,
          cellCap: CELL_CAP,
        })
        return r ?? { skill: s.name, error: 'child workflow returned null' }
      } catch (err) {
        // workflow() THROWS on an unknown name. Catching per cell keeps one bad
        // cell from killing the batch; the all-failed check below is what keeps
        // a systematically unreachable child from reading as a quiet sweep.
        return { skill: s.name, error: String((err && err.message) || err) }
      }
    }),
  )
  // A null cell is a MISSING result, not a passing one.
  cells.push(
    ...got.map((r, j) => r || { skill: wave[j].name, error: 'cell returned null' }),
  )

  if (i === 0 && cells.length > 0 && cells.every((c) => c && c.error)) {
    // Every cell of the first wave failed the same way. That is a systematic
    // fault (most likely `${EVALUATE_SKILL_WORKFLOW}` not resolving), and
    // grinding through the remaining waves would just repeat it.
    log(`every cell in the first wave failed — first error: ${cells[0].error}`)
    return { abort: true, reason: 'cells-unreachable', firstError: cells[0].error, cells }
  }
}

// A cell below the child's own inline floor returns `{mode:'inline'}` and
// writes no benchmark. That is not an error, but it IS a cell the aggregate
// script will not see — surfaced here so the partial-sweep verdict below is
// diagnosable rather than mysterious.
const inlineCells = cells.filter((c) => c && c.mode === 'inline')
if (inlineCells.length) {
  log(`${inlineCells.length} cell(s) returned mode:inline (below the child's own floor) — they wrote no benchmark`)
}

const failedCells = cells.filter((c) => c && c.error)
if (failedCells.length) {
  log(`${failedCells.length} of ${cells.length} cell(s) failed — the aggregate cross-check will surface this as partial-sweep`)
}

phase('Aggregate')
// BARRIER: aggregate_benchmark.sh reads every benchmark.json off disk, so it
// cannot run until the last cell has written its own.
const report = await agent(AGGREGATE_PROMPT(plugin, included.length, cells), {
  label: 'aggregate',
  phase: 'Aggregate',
  schema: REPORT_SCHEMA,
  model: 'opus',
  effort: 'medium',
})

if (!report) {
  log('aggregate agent returned null — surfacing the raw cells so the run is not silently empty')
  return { report: null, plugin, included: included.length, skipped, cells, failedCells }
}

// The skill maps report.status / report.overallPassRate onto its printed table
// and its exit code; a workflow returns a value, not a process status.
return { report, plugin, included: included.length, skipped, cells, failedCells }
