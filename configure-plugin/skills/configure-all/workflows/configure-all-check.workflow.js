/**
 * configure-all-check.workflow.js — parallel check fan-out for `/configure:all`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: fan-out-and-synthesize.
 *   Fan-out unit  — one READ-ONLY check agent per applicable roster row.
 *   Loop bound    — `scripts/list-components.sh`'s `COMPONENT=` rows, passed in
 *                   as `args.roster`. Never a prose "for each component".
 *   Barrier       — Synthesize. The fix plan has to see every component at once
 *                   to group the ones contending for the same file.
 *
 * Three things this deliberately does NOT do:
 *   1. No classify agent. Applicability is
 *      `types === 'all' || types.split(',').includes(projectType)` over a field
 *      the lister already emits — manifest data, not a judgement.
 *   2. No `--fix`. Several components write the same files (pre-commit and
 *      linting both write `.pre-commit-config.yaml`); parallel fixers race.
 *      The `fixPlan` is returned for the SKILL to apply sequentially, outside.
 *   3. No exit code. A workflow returns a value, not a process status — the
 *      skill maps `report.overall` onto the documented 0/1/2 exit codes.
 */

export const meta = {
  name: 'configure-all-check',
  phases: [{ title: 'Check' }, { title: 'Synthesize' }],
}

// Below this many applicable components the sequential Step 3 pass is cheaper
// than paying an agent preamble per component. A ceiling AND a floor.
const FLOOR = 15

// Concurrency ceiling. Each agent invokes a slash command that reads files;
// wider waves buy little and risk the burst rate-limit.
const WAVE = 5

const CHECK_SCHEMA = {
  type: 'object',
  required: ['component', 'status', 'issues', 'files'],
  additionalProperties: false,
  properties: {
    component: { type: 'string' },
    // A closed enum, so "the agent was vague" is impossible. ERROR is reserved
    // for the check itself failing to run, and is distinct from FAIL.
    status: { type: 'string', enum: ['PASS', 'WARN', 'FAIL', 'ERROR'] },
    issues: { type: 'array', items: { type: 'string' } },
    // Files the component OWNS or would write under --fix. This is what makes
    // the synthesize barrier able to detect contention.
    files: { type: 'array', items: { type: 'string' } },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  required: ['overall', 'counts', 'rows', 'contention', 'fixPlan'],
  additionalProperties: false,
  properties: {
    overall: { type: 'string', enum: ['PASS', 'WARN', 'FAIL'] },
    counts: {
      type: 'object',
      required: ['pass', 'warn', 'fail', 'error', 'skip'],
      additionalProperties: false,
      properties: {
        pass: { type: 'integer' },
        warn: { type: 'integer' },
        fail: { type: 'integer' },
        error: { type: 'integer' },
        skip: { type: 'integer' },
      },
    },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['component', 'status', 'summary'],
        additionalProperties: false,
        properties: {
          component: { type: 'string' },
          status: { type: 'string', enum: ['PASS', 'WARN', 'FAIL', 'ERROR', 'SKIP'] },
          summary: { type: 'string' },
        },
      },
    },
    // Components whose fixes would write the same file. The whole reason
    // Synthesize is a barrier rather than a per-agent summary.
    contention: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'components'],
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          components: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    // Ordered so contending components never sit adjacent by accident. The
    // SKILL applies these one at a time; the workflow never applies them.
    fixPlan: {
      type: 'array',
      items: {
        type: 'object',
        required: ['component', 'command', 'reason'],
        additionalProperties: false,
        properties: {
          component: { type: 'string' },
          command: { type: 'string' },
          reason: { type: 'string' },
        },
      },
    },
  },
}

const CHECK_PROMPT = (component) => `
Invoke \`/configure:${component} --check-only\` using the SlashCommand tool.

READ-ONLY. Report findings; write nothing. Do not pass --fix, do not edit,
create, or delete any file, and do not run any command that mutates the repo.

Return:
  component — "${component}"
  status    — PASS (compliant) | WARN (advisory gaps) | FAIL (blocking gaps)
              | ERROR (the check itself could not run)
  issues    — one short line per finding, empty when PASS
  files     — the config files this component owns or would write under --fix
              (repo-relative paths), so the synthesis step can detect two
              components contending for the same file
`

const SYNTH_PROMPT = (checks, skipped) => `
You are the synthesis stage of a compliance run. Every component check has
already completed; below is the full set. Produce ONE report.

Checks (JSON):
${JSON.stringify(checks, null, 2)}

Skipped for project type (JSON):
${JSON.stringify(skipped, null, 2)}

Required of the report:
  - rows      — one per checked component plus one SKIP row per skipped
                component, carrying its TYPES= reason as the summary.
  - counts    — the roll-up. counts.skip is the skipped list's length.
  - overall   — FAIL if any FAIL or ERROR, else WARN if any WARN, else PASS.
  - contention— group components whose \`files\` overlap. This is why you see
                every component at once: no single check agent could know that
                pre-commit and linting both write .pre-commit-config.yaml.
  - fixPlan   — an ORDERED remediation list, one entry per component needing
                work, each a \`/configure:<component> --fix\` command with a
                one-line reason. Contending components must not be adjacent,
                and the plan must be safe to apply strictly sequentially.
                Do not apply anything: the caller applies this plan.
`

const { roster, projectType, ambiguous = [] } = (typeof args === 'string') ? JSON.parse(args) : args

if (!roster?.length) {
  log('empty roster — list-components.sh returned STATUS=ERROR; abort')
  return { abort: true, reason: 'empty-roster' }
}

// TYPES is manifest data, not a judgement. No agent decides this.
const applicable = roster.filter((r) => r.types === 'all' || r.types.split(',').includes(projectType))
const skipped = roster
  .filter((r) => !applicable.includes(r))
  .map((r) => ({ ...r, reason: `TYPES=${r.types}` }))

// The floor is as load-bearing as the ceiling: a harness that fires 8 agent
// preambles to replace 8 slash commands is pure overhead.
if (applicable.length < FLOOR) {
  log(`${applicable.length} applicable components (< ${FLOOR}) — sequential path is cheaper; abort`)
  return { abort: true, reason: 'below-floor', applicable: applicable.length }
}

if (ambiguous.length) {
  // Applicability judgements the manifest cannot express (e.g. Skaffold only
  // when a k8s/ dir exists) are resolved by the SKILL before dispatch and only
  // reported here — an agent deciding them would reintroduce the classify stage.
  log(`${ambiguous.length} component(s) flagged ambiguous by the caller: ${ambiguous.map((a) => a.component ?? a).join(', ')}`)
}

phase(`Check — ${applicable.length} components, READ-ONLY, <=${WAVE} in flight`)
const checks = []
for (let i = 0; i < applicable.length; i += WAVE) {
  const wave = applicable.slice(i, i + WAVE)
  const got = await parallel(
    wave.map((c) => () =>
      agent(CHECK_PROMPT(c.component), {
        label: `check:${c.component}`,
        phase: 'Check',
        schema: CHECK_SCHEMA,
        model: 'opus',
        effort: 'low',
        // SlashCommand is not optional. Without it the agent re-derives the
        // component's check from scratch instead of invoking the skill that
        // already encodes it.
        tools: ['SlashCommand', 'Read', 'Glob', 'Grep', 'Bash'],
      }),
    ),
  )
  // A null return is a missing verdict, not a passing one. Convert it into an
  // explicit ERROR row so it reaches the report instead of vanishing.
  checks.push(
    ...got.map((r, j) => r || {
      component: wave[j].component,
      status: 'ERROR',
      issues: ['agent returned null'],
      files: [],
    }),
  )
}

phase('Synthesize — BARRIER: the fix plan must see every component at once')
const report = await agent(SYNTH_PROMPT(checks, skipped), {
  label: 'synthesize',
  phase: 'Synthesize',
  schema: REPORT_SCHEMA,
  model: 'opus',
  effort: 'medium',
})

if (!report) {
  log('synthesis returned null — surfacing raw checks so the run is not silently empty')
  return { report: null, checks, skipped, fixPlan: [] }
}

// `--fix` is applied OUTSIDE, sequentially, by the skill. A workflow also
// cannot set a process exit code — the skill maps report.overall onto one.
return { report, fixPlan: report.fixPlan, checks, skipped }
