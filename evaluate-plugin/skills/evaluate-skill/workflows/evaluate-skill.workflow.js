/**
 * evaluate-skill.workflow.js — the batch-only harness for
 * `evaluate-plugin:evaluate-skill`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: fan-out-and-synthesize.
 *   Fan-out unit — one (eval case x run x config) CELL. Each cell is a
 *                  rollout agent followed by an INDEPENDENT grader agent.
 *   Loop bound   — the cartesian product `evalIds.length * runs * configs.length`,
 *                  computed here in JS from the eval-case list the preflight
 *                  agent read off disk. Never a prose "for each eval case".
 *   Barrier      — Aggregate. Mean pass rate, standard deviation, and the
 *                  baseline delta are cross-cell statistics: no single cell can
 *                  compute them, and `benchmark.json` must be written once.
 *
 * Four things this deliberately does NOT do:
 *   1. No `workflow()` call. Nesting is ONE level only and this file is the
 *      child — `evaluate-plugin:evaluate-plugin-batch` calls
 *      `workflow('evaluate-skill', {...})`, so a `workflow()` here would throw
 *      and kill the whole batch.
 *   2. No worktree isolation on any agent. Every rollout agent writes under
 *      `<skillDir>/eval-results/`, and the Aggregate agent has to read what all
 *      of them wrote. A worktree-isolated agent's writes are invisible to its
 *      siblings, so isolating them would silently empty the benchmark. Nothing
 *      here pushes, opens a PR, or mutates a forge either, so the two
 *      worktree clauses `.claude/rules/workflow-vs-skill.md` requires of a
 *      worktree-dispatching template do not apply to this one.
 *   3. No hand-rolled wave width. The platform already caps concurrency at
 *      min(16, CPUs - 2) per workflow, and a nested child SHARES its parent's
 *      cap and agent counter. A second ceiling here would silently supersede
 *      the `--parallel N` the batch caller was given.
 *   4. No truncation at the ceiling. `CELL_CAP` ABORTS with a stated reason;
 *      an eval sweep that quietly evaluates 30 of 84 cells and reports a mean
 *      is worse than one that refuses.
 *
 * REGISTRATION. This is the only template in the marketplace that ships to
 * `~/.claude/workflows` as well as beside its SKILL.md, because
 * `evaluate-plugin-batch` must resolve it BY NAME. `meta.name` below is
 * therefore load-bearing, not cosmetic — see
 * `docs/dynamic-workflow-registration.md`.
 */

export const meta = {
  name: 'evaluate-skill',
  description:
    'Evaluate one skill: fan out a rollout+grade agent pair per (case x run x config) cell, then aggregate one benchmark.',
  phases: [{ title: 'Preflight' }, { title: 'Rollout' }, { title: 'Grade' }, { title: 'Aggregate' }],
}

// Ceiling on the cartesian product. `evaluate-plugin-batch` passes 30
// explicitly; the default matches it so a direct invocation behaves the same.
// 30 is `5 evals x 3 runs x 2 configs` — the largest shape a single golden-set
// canary is expected to take (`.claude/rules/skill-evaluation.md`). ABORT, not
// truncate: see note 4 in the header.
const DEFAULT_CELL_CAP = 30

// Below this many cells the linear path in SKILL.md is cheaper. It is
// deliberately LOW — far lower than `configure-all`'s 15 — because the marginal
// cost of this harness is a CONSTANT 2 agents (Preflight + Aggregate): the
// skill's inline path already spawns one rollout subagent and one grader
// subagent per cell, so the harness does not multiply the agent count the way a
// check fan-out does. Two cells (one eval x two runs, or two evals x one run)
// is a spot check, and a spot check is a linear pass.
const INLINE_FLOOR = 3

// The third axis. `--baseline` reruns the same prompts with the skill content
// withheld, which is the only signal `.claude/rules/skill-evaluation.md`
// Principle 2 accepts: a bare pass rate means nothing, the delta against the
// model's own baseline does.
const CONFIGS_WITH_BASELINE = ['with-skill', 'baseline']
const CONFIGS_WITHOUT_BASELINE = ['with-skill']

const PREFLIGHT_SCHEMA = {
  type: 'object',
  required: ['compliance', 'evalsPath', 'evalIds', 'evalsCreated'],
  additionalProperties: false,
  properties: {
    // Closed enum so "the structural check was inconclusive" is impossible.
    // ERROR is the check failing to RUN and is distinct from FAIL.
    compliance: { type: 'string', enum: ['PASS', 'WARN', 'FAIL', 'ERROR'] },
    complianceIssues: { type: 'array', items: { type: 'string' } },
    evalsPath: { type: 'string' },
    // THE LOOP BOUND. One id per eval case, read off disk — never invented.
    evalIds: { type: 'array', items: { type: 'string' } },
    evalsCreated: { type: 'boolean' },
    // The token-frugality split (`skill-evaluation.md` Principle 1), surfaced
    // so a run that is 100% judge-graded is visible before it is paid for.
    deterministicExpectations: { type: 'integer' },
    judgeExpectations: { type: 'integer' },
  },
}

const ROLLOUT_SCHEMA = {
  type: 'object',
  required: ['cellId', 'status', 'runDir', 'transcriptPath', 'durationMs'],
  additionalProperties: false,
  properties: {
    cellId: { type: 'string' },
    // COMPLETED means the rollout produced a transcript, NOT that the skill
    // under test behaved well — that verdict belongs to the grader alone.
    status: { type: 'string', enum: ['COMPLETED', 'FIXTURE_FAILED', 'ERROR'] },
    runDir: { type: 'string' },
    transcriptPath: { type: 'string' },
    durationMs: { type: 'integer' },
    notes: { type: 'array', items: { type: 'string' } },
  },
}

const GRADE_SCHEMA = {
  type: 'object',
  required: ['cellId', 'evalId', 'run', 'config', 'status', 'assertionsTotal', 'assertionsPassed', 'passRate'],
  additionalProperties: false,
  properties: {
    cellId: { type: 'string' },
    evalId: { type: 'string' },
    run: { type: 'integer' },
    config: { type: 'string', enum: ['with-skill', 'baseline'] },
    status: { type: 'string', enum: ['PASS', 'PARTIAL', 'FAIL', 'ERROR'] },
    assertionsTotal: { type: 'integer' },
    assertionsPassed: { type: 'integer' },
    // Split so the deterministic half stays auditable: a grader that judged an
    // expectation the script already decided is a bug, not a second opinion.
    deterministicPassed: { type: 'integer' },
    deterministicTotal: { type: 'integer' },
    judgePassed: { type: 'integer' },
    judgeTotal: { type: 'integer' },
    passRate: { type: 'number' },
    gradingPath: { type: 'string' },
    failedAssertions: { type: 'array', items: { type: 'string' } },
    durationMs: { type: 'integer' },
  },
}

const BENCHMARK_SCHEMA = {
  type: 'object',
  required: ['benchmarkPath', 'overall', 'summary', 'rows'],
  additionalProperties: false,
  properties: {
    benchmarkPath: { type: 'string' },
    overall: { type: 'string', enum: ['PASS', 'PARTIAL', 'FAIL', 'ERROR'] },
    summary: {
      type: 'object',
      required: ['withSkillMeanPassRate', 'withSkillStdev', 'meanDurationMs', 'cellsGraded', 'cellsErrored'],
      additionalProperties: false,
      properties: {
        withSkillMeanPassRate: { type: 'number' },
        withSkillStdev: { type: 'number' },
        // Present only when a baseline config was actually run. Absent is a
        // truthful "not measured"; a 0 would read as "the model scored zero".
        baselineMeanPassRate: { type: 'number' },
        delta: { type: 'number' },
        meanDurationMs: { type: 'number' },
        cellsGraded: { type: 'integer' },
        cellsErrored: { type: 'integer' },
      },
    },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['evalId', 'passRate', 'status'],
        additionalProperties: false,
        properties: {
          evalId: { type: 'string' },
          description: { type: 'string' },
          passRate: { type: 'number' },
          status: { type: 'string', enum: ['PASS', 'PARTIAL', 'FAIL', 'ERROR'] },
        },
      },
    },
  },
}

const PREFLIGHT_PROMPT = (plugin, skill, skillDir, createEvals) => `
You are the preflight stage of a skill evaluation. Do NOT evaluate anything.

1. Structural gate. Run:
     bash scripts/plugin-compliance-check.sh ${plugin}
   Report the verdict for ${plugin}/${skill} as \`compliance\`, with one short
   line per finding in \`complianceIssues\`. Behavioural evaluation of a
   structurally broken skill is wasted effort, so a FAIL here stops the run.

2. Eval cases. Run:
     bash evaluate-plugin/scripts/inspect_eval.sh --plugin ${plugin} --skill ${skill} --print-evals
   Report \`evalsPath\` and \`evalIds\` — one entry per \`evals[].id\`, in file
   order. Count the expectations across every case and split them:
   \`deterministicExpectations\` are the typed-object checks
   (regex / substring / substring_all / absent_regex) that
   \`grade_deterministic.py\` grades for zero model tokens;
   \`judgeExpectations\` are bare strings plus \`"check": "judge"\` objects.

3. ${
   createEvals
     ? `No evals.json exists and --create-evals was requested. Read
   ${skillDir}/SKILL.md thoroughly and generate 3-5 cases covering a happy path,
   an edge case, and a boundary, following the schema in
   evaluate-plugin/references/schemas.md. Prefer TYPED checks over bare strings
   wherever the assertion is machine-checkable. Write the file to
   ${skillDir}/evals.json, then re-run inspect_eval.sh and report the real ids.
   Set evalsCreated true.`
     : `Do NOT create evals.json. If it is absent, report evalIds as an empty
   array and evalsCreated false — the caller decides whether to ask for
   --create-evals.`
 }
`

const ROLLOUT_PROMPT = (cell, ctx) => `
You are executing ONE evaluation cell of a skill benchmark. You are the
rollout, not the judge: produce a transcript and stop. Do not grade yourself,
do not edit the skill under test, and do not touch any other cell's directory.

Cell: ${cell.id}
  eval case: ${cell.evalId}
  run:       ${cell.run}
  config:    ${cell.config}

1. Scaffold the run directory:
     bash evaluate-plugin/scripts/prepare_run.sh \\
       --skill-dir ${ctx.skillDir} --eval-id ${cell.evalId} --run ${cell.run}${
         cell.config === 'baseline' ? ' \\\n       --baseline' : ''
       }
   Parse RUN_DIR=, MANIFEST= and STARTED_AT= from its output.

2. Read ${ctx.evalsPath} and take the case whose id is ${cell.evalId}. If it
   carries a \`fixture\` block, apply it:
     bash evaluate-plugin/scripts/apply_fixture.sh --fixture '<the fixture JSON>' --repo-root "$(pwd)"
   and parse WORKDIR=. An eval WITHOUT a fixture runs in the repository, as
   before. If the fixture fails to apply, report status FIXTURE_FAILED with the
   reason in notes and stop — a fixture-less run of a context-needing eval is a
   false negative, not a result.

3. Execute the case's \`prompt\` exactly as written, in \$WORKDIR when a fixture
   was applied.
   ${
     cell.config === 'baseline'
       ? `This is the BASELINE config: run the prompt WITHOUT loading
   ${ctx.skillDir}/SKILL.md and without invoking the skill. This measures what
   the model does unaided, which is the only thing the delta is a delta against.
   Do not quote, paraphrase, or summarise the skill's guidance.`
       : `This is the WITH-SKILL config: load ${ctx.skillDir}/SKILL.md as context
   first, then execute the prompt following it.`
   }

4. Write the full transcript to \$RUN_DIR/transcript.md and the measured wall
   clock to \$RUN_DIR/timing.json. Report durationMs from that measurement, not
   an estimate.

5. If the case had a fixture, tear it down AFTER the transcript is copied out:
     bash evaluate-plugin/scripts/apply_fixture.sh --teardown "\$WORKDIR" --fixture '<the fixture JSON>'

Report runDir and transcriptPath as absolute or repo-relative paths that
another agent can open.
`

const GRADE_PROMPT = (cell, rollout, ctx) => `
Grade ONE evaluation cell against its assertions. You did not produce this
transcript and must not defend it: grade what is there.

Cell: ${cell.id} (eval ${cell.evalId}, run ${cell.run}, config ${cell.config})
Eval file:  ${ctx.evalsPath}
Transcript: ${rollout.transcriptPath}
Run dir:    ${rollout.runDir}

1. Grade the machine-checkable expectations FIRST, for zero model tokens:
     python3 evaluate-plugin/scripts/grade_deterministic.py \\
       --evals ${ctx.evalsPath} --eval-id ${cell.evalId} \\
       --output ${rollout.transcriptPath} --json
   Take its PASS/FAIL verdicts as final. Do NOT re-judge an expectation the
   script already decided — a second opinion on a regex is noise, and the whole
   point of the split is that ~70% of assertions cost nothing to grade.

2. Judge ONLY the expectations the script reported as DEFERRED. Cite evidence
   from the transcript or from the artifacts under the run dir for each verdict.

3. Write the combined per-assertion result to ${rollout.runDir}/grading.json and
   report its path as gradingPath.

Report deterministicPassed/Total and judgePassed/Total separately, then
assertionsPassed/Total as their sums, and passRate = passed / total (0 when
total is 0). status: PASS when every assertion passed, FAIL when none did,
PARTIAL in between, ERROR only when grading itself could not run.
`

const AGGREGATE_PROMPT = (grades, ctx) => `
You are the aggregation barrier of a skill evaluation. Every cell has already
been rolled out and graded independently; below is the complete set. You see
them all at once because the statistics below are CROSS-CELL — no individual
cell can compute a standard deviation or a baseline delta.

Skill:  ${ctx.skill} (${ctx.skillDir})
Config: ${ctx.runs} run(s) per case, baseline ${ctx.baseline ? 'ON' : 'OFF'}

Graded cells (JSON):
${JSON.stringify(grades, null, 2)}

Required of the report:
  - rows      One per eval case, averaging its WITH-SKILL cells only. Pull each
              \`description\` from ${ctx.evalsPath}.
  - summary   withSkillMeanPassRate and withSkillStdev across the with-skill
              cells; meanDurationMs across every cell that ran; cellsGraded and
              cellsErrored (status ERROR counts as errored, never as a pass).
              ${
                ctx.baseline
                  ? 'Also baselineMeanPassRate across the baseline cells and delta = withSkill - baseline.'
                  : 'OMIT baselineMeanPassRate and delta — no baseline config ran. Do not emit 0 for an unmeasured value.'
              }
  - overall   FAIL if any row is FAIL or ERROR, else PARTIAL if any row is
              PARTIAL, else PASS.

Then write the benchmark to ${ctx.skillDir}/eval-results/benchmark.json in the
shape evaluate-plugin/references/schemas.md documents, and report that path as
benchmarkPath. That file is the CONTRACT with the plugin-level roll-up:
\`evaluate-plugin/scripts/aggregate_benchmark.sh\` reads
\`.summary.with_skill.mean_pass_rate\` and \`.metadata.num_evals\` out of it, so
those two keys must be populated even when the run is partial.
`

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

const SKILL = INPUT.skill ?? ''
const SKILL_DIR = INPUT.skillDir ?? ''
const RUNS = Math.max(1, INPUT.runs ?? 1)
const BASELINE = INPUT.baseline ?? false
const CREATE_EVALS = INPUT.createEvals ?? false
const CELL_CAP = INPUT.cellCap ?? DEFAULT_CELL_CAP

if (!SKILL_DIR) {
  log('no skillDir — nothing to evaluate; abort')
  return { abort: true, reason: 'missing-skill-dir' }
}

// `<plugin>/skills/<skill>` — the shape `/evaluate:skill` already parses out of
// `$ARGUMENTS`, so the split is manifest data, not a judgement.
const PLUGIN = SKILL_DIR.split('/')[0]
const SKILL_NAME = SKILL_DIR.split('/').pop()

phase('Preflight — structural gate + eval-case inventory, evaluate NOTHING')
const pre = await agent(PREFLIGHT_PROMPT(PLUGIN, SKILL_NAME, SKILL_DIR, CREATE_EVALS), {
  label: 'preflight',
  phase: 'Preflight',
  schema: PREFLIGHT_SCHEMA,
  model: 'opus',
  effort: 'low',
})

if (!pre) {
  log('preflight returned null — the eval-case list is unknown, so the loop bound is unknown; abort')
  return { abort: true, reason: 'preflight-null' }
}

// PRESERVE — the structural gate. SKILL.md Step 2 stops here for a reason:
// a behavioural benchmark of a structurally broken skill measures the breakage.
if (pre.compliance === 'FAIL' || pre.compliance === 'ERROR') {
  log(`compliance ${pre.compliance} for ${SKILL_DIR} — refusing to benchmark a structurally broken skill`)
  return { abort: true, reason: `compliance-${pre.compliance.toLowerCase()}`, issues: pre.complianceIssues ?? [] }
}

if (!pre.evalIds?.length) {
  log(`no eval cases for ${SKILL_DIR}${CREATE_EVALS ? '' : ' — re-run with --create-evals to generate them'}`)
  return { abort: true, reason: 'no-eval-cases', evalsCreated: pre.evalsCreated ?? false }
}

// --------------------------------------------------------------------------
// THE LOOP BOUND. A cartesian product, computed here, from a list read off
// disk. This is the whole reason the harness exists: `evals x runs x configs`
// expanded by hand in prose drifts, and a model asked to "run each case N
// times, with and without the skill" silently drops cells.
// --------------------------------------------------------------------------
const CONFIGS = BASELINE ? CONFIGS_WITH_BASELINE : CONFIGS_WITHOUT_BASELINE
const CELLS = []
for (const evalId of pre.evalIds) {
  for (let run = 1; run <= RUNS; run++) {
    for (const config of CONFIGS) {
      CELLS.push({ id: `${evalId}/run-${run}/${config}`, evalId, run, config })
    }
  }
}

// CEILING — a refusal. The run does not proceed at all, and the reason names
// every factor, so the caller can lower `runs`, drop `--baseline`, or raise the
// cap deliberately. Nothing is dropped, so there is nothing to log as dropped.
if (CELLS.length > CELL_CAP) {
  log(
    `${CELLS.length} cells (${pre.evalIds.length} evals x ${RUNS} runs x ${CONFIGS.length} configs) exceeds cellCap ${CELL_CAP} — aborting rather than truncating`,
  )
  return {
    abort: true,
    reason: 'cell-cap-exceeded',
    cells: CELLS.length,
    cellCap: CELL_CAP,
    evals: pre.evalIds.length,
    runs: RUNS,
    configs: CONFIGS.length,
  }
}

// FLOOR — a route, not a refusal. The work SHOULD happen; it should just happen
// linearly, on SKILL.md's own path. That is why this returns `mode: 'inline'`
// rather than `abort: true`.
if (CELLS.length < INLINE_FLOOR) {
  log(`${CELLS.length} cell(s) (< ${INLINE_FLOOR}) — the linear path in SKILL.md is cheaper; returning mode:inline`)
  return { mode: 'inline', reason: 'below-floor', cells: CELLS.length, evalIds: pre.evalIds }
}

log(
  `${CELLS.length} cells = ${pre.evalIds.length} evals x ${RUNS} runs x ${CONFIGS.length} configs; ` +
    `${pre.deterministicExpectations ?? 0} deterministic / ${pre.judgeExpectations ?? 0} judged expectations`,
)

const CTX = {
  skill: SKILL || SKILL_DIR,
  skillDir: SKILL_DIR,
  evalsPath: pre.evalsPath,
  runs: RUNS,
  baseline: BASELINE,
}

phase(`Rollout + grade — ${CELLS.length} cells, rollout and grader are SEPARATE agents`)

// `pipeline`, not two `parallel` waves: cell A's grade does not wait on cell
// B's rollout, and there is no cross-cell fact until Aggregate. The two stages
// stay separate because the grader MUST NOT be the agent that produced the
// transcript — `.claude/rules/loop-integrity.md` Pillar 1: an author asked to
// judge its own output optimises for done, not for correct.
const graded = await pipeline(
  CELLS,

  // Stage 1 — roll the cell out. Read-mostly: writes only under its own run dir.
  async (cell) => {
    const rollout = await agent(ROLLOUT_PROMPT(cell, CTX), {
      label: `rollout:${cell.id}`,
      phase: 'Rollout',
      schema: ROLLOUT_SCHEMA,
      model: 'opus',
      effort: 'medium',
    })
    // A null return is a dead agent, not a finished rollout. Carry the cell
    // forward explicitly so stage 2 can turn it into an ERROR row instead of
    // letting the cell vanish from the denominator.
    return rollout ? { cell, rollout } : { cell, rollout: null }
  },

  // Stage 2 — grade it, with a different agent. `prev` may be null if stage 1
  // threw; `cell` comes from the ORIGINAL item, so the error row is always
  // attributable.
  async (prev, cell) => {
    const rollout = prev?.rollout
    if (!rollout || rollout.status !== 'COMPLETED') {
      return {
        cellId: cell.id,
        evalId: cell.evalId,
        run: cell.run,
        config: cell.config,
        status: 'ERROR',
        assertionsTotal: 0,
        assertionsPassed: 0,
        passRate: 0,
        failedAssertions: [rollout ? `rollout ${rollout.status}` : 'rollout agent returned null'],
      }
    }
    const grade = await agent(GRADE_PROMPT(cell, rollout, CTX), {
      label: `grade:${cell.id}`,
      phase: 'Grade',
      schema: GRADE_SCHEMA,
      // The grading brief already lives in this agent definition — reusing it
      // keeps the harness and the inline path grading the same way.
      agentType: 'evaluate-plugin:eval-grader',
      model: 'opus',
      effort: 'low',
    })
    return (
      grade ?? {
        cellId: cell.id,
        evalId: cell.evalId,
        run: cell.run,
        config: cell.config,
        status: 'ERROR',
        assertionsTotal: 0,
        assertionsPassed: 0,
        passRate: 0,
        failedAssertions: ['grader agent returned null'],
      }
    )
  },
)

// A pipeline item whose stage threw arrives as `null`. Convert it, rather than
// filtering it out: a missing verdict is an ERROR, never a pass, and it must
// stay in the denominator.
const rows = graded.map((g, i) =>
  g && g.cellId
    ? g
    : {
        cellId: CELLS[i].id,
        evalId: CELLS[i].evalId,
        run: CELLS[i].run,
        config: CELLS[i].config,
        status: 'ERROR',
        assertionsTotal: 0,
        assertionsPassed: 0,
        passRate: 0,
        failedAssertions: ['cell pipeline dropped the item'],
      },
)

const errored = rows.filter((r) => r.status === 'ERROR').length
if (errored) log(`${errored} of ${rows.length} cells ERRORed — they stay in the denominator, they are not passes`)

phase('Aggregate — BARRIER: stdev and the baseline delta are cross-cell facts')
const report = await agent(AGGREGATE_PROMPT(rows, CTX), {
  label: 'aggregate',
  phase: 'Aggregate',
  schema: BENCHMARK_SCHEMA,
  model: 'opus',
  effort: 'medium',
})

if (!report) {
  // Surface the raw cells rather than returning an empty success. The caller
  // (`evaluate-plugin-batch`, or the skill) can still see every graded cell.
  log('aggregation returned null — returning the raw graded cells so the run is not silently empty')
  return { report: null, cells: rows, skillDir: SKILL_DIR, cellsErrored: errored }
}

// The return value IS the skill's documented Step 7 input: the benchmark path
// the plugin-level `aggregate_benchmark.sh` roll-up will read, plus the rows
// the summary table renders. The workflow renders no table and sets no exit
// code — a workflow returns a value, not a process status.
return { report, benchmarkPath: report.benchmarkPath, cells: rows, skillDir: SKILL_DIR, cellsErrored: errored }
