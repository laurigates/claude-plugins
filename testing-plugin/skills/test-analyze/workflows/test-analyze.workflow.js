/**
 * test-analyze — classify-and-act harness.
 *
 * TEMPLATE, not a runnable script. Read `../SKILL.md` § "Workflow harness
 * (template)" before adapting it; invoking this file against empty `args`
 * spends real opus agents to discover that it is a template.
 *
 * Shape: classify-and-act (docs/plans/dynamic-workflow-migration.md §4).
 *   Parse+classify (1 agent)  →  plan per agent type (≤8 in parallel)  →  synthesize (1 agent)
 *
 * Three things are structure, not preference (see SKILL.md for the full framing):
 *   1. The fan-out width is `AGENT_FOR`'s key set — a fixed table of agent types
 *      that exist on disk, never a count the model invents.
 *   2. `category` / `severity` are closed enums, so every failure either routes
 *      or lands in `unroutable[]` with a stated reason.
 *   3. `parallel()` is a real barrier: `depends_on` edges cross groups, so
 *      sequencing cannot happen inside a group.
 *
 * Classify is deliberately MERGED into parse: an 8-row lookup plus a 4-value
 * enum is something the parse agent can do while it already holds the failures.
 * A separate classifier agent would be pure overhead.
 *
 * `mcp__pal-mcp-server__planner` is NOT available inside a workflow. The dependency edges
 * below are *inferred* by the group agents, not planned. A run that genuinely
 * needs PAL planning belongs on the inline path in SKILL.md.
 */

// --- The contract this harness shares with SKILL.md § Subagent Routing -------
// Editing either side alone breaks the skill. The keys are the table's "Issue
// category" column; the values are its "Dispatch" column, in the
// plugin-qualified `plugin:agent` form the Task/Agent tool resolves for a
// plugin-provided agent. Every value below is backed by a real
// `agents-plugin/agents/<name>.md` — `scripts/check-subagent-types.sh` is the
// guard that keeps the SKILL.md side honest.
const AGENT_FOR = {
  accessibility: 'agents-plugin:review',
  security: 'agents-plugin:security-audit',
  performance: 'agents-plugin:performance',
  quality: 'agents-plugin:refactor',
  flaky: 'agents-plugin:test',
  integration: 'agents-plugin:debug',
  ci: 'agents-plugin:ci',
  docs: 'agents-plugin:docs',
};

const CATEGORIES = Object.keys(AGENT_FOR); // 8 — the structural fan-out cap
const SEVERITIES = ['critical', 'high', 'medium', 'low'];

// A failure count below this stays on the inline path in SKILL.md. HARD FLOOR,
// not a knob: below it, one opus agent per category costs more than the linear
// pass it replaces.
const INLINE_FLOOR = 5;

const RoutedFailuresSchema = {
  type: 'object',
  required: ['failures', 'unroutable'],
  properties: {
    failures: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'test', 'message', 'category', 'severity'],
        properties: {
          id: { type: 'string' },
          test: { type: 'string' },
          file: { type: 'string' },
          message: { type: 'string' },
          stack_head: { type: 'string' },
          category: { type: 'string', enum: CATEGORIES },
          severity: { type: 'string', enum: SEVERITIES },
        },
      },
    },
    // Anything that fits no category lands here WITH a reason, rather than
    // being forced into the nearest-looking row.
    unroutable: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'test', 'reason'],
        properties: {
          id: { type: 'string' },
          test: { type: 'string' },
          reason: { type: 'string' },
        },
      },
    },
  },
};

const PlanSchema = {
  type: 'object',
  required: ['agentType', 'items'],
  properties: {
    agentType: { type: 'string' },
    items: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'objective', 'success_criteria', 'verification'],
        properties: {
          id: { type: 'string' },
          objective: { type: 'string' },
          success_criteria: { type: 'string' },
          // Failure ids, which may belong to ANOTHER group — this is why the
          // barrier below exists.
          depends_on: { type: 'array', items: { type: 'string' } },
          verification: { type: 'string' },
        },
      },
    },
  },
};

const FixPlanSchema = {
  type: 'object',
  required: ['ordered_steps', 'unroutable'],
  properties: {
    ordered_steps: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'agentType', 'objective', 'verification'],
        properties: {
          id: { type: 'string' },
          agentType: { type: 'string' },
          objective: { type: 'string' },
          success_criteria: { type: 'string' },
          verification: { type: 'string' },
        },
      },
    },
    unroutable: { type: 'array', items: { type: 'object' } },
    dropped_groups: { type: 'array', items: { type: 'string' } },
  },
};

// --- Stage 1: parse + classify (one agent, no separate classifier) -----------
phase('Parse + classify');
const parsed = await agent(
  `Read every result file under ${args.resultsPath}.
   ${args.testType ? `Test type: ${args.testType}.` : 'Auto-detect the result format (JUnit XML, JSON, TAP, plain text).'}
   ${args.focusArea ? `Prioritise failures related to: ${args.focusArea}.` : ''}

   Per failure emit {id, test, file, message, stack_head, category, severity}.
   category MUST be one of: ${CATEGORIES.join(', ')}.
   severity MUST be one of: ${SEVERITIES.join(', ')}.
   A failure that fits no category goes to unroutable[] with a stated reason —
   do NOT force it into the nearest-looking category.`,
  { label: 'parse', schema: RoutedFailuresSchema, model: 'opus', effort: 'medium' },
);

const failures = (parsed && parsed.failures) || [];
const unroutable = (parsed && parsed.unroutable) || [];

if (failures.length < INLINE_FLOOR) {
  log(`only ${failures.length} routable failures — use the inline path in SKILL.md`);
  return { mode: 'inline', failures, unroutable };
}

// --- Stage 2: act, one agent per AGENT TYPE (not per category, not per failure)
// Grouping by agent type is what bounds the fan-out at CATEGORIES.length.
const groups = Object.values(
  failures.reduce((acc, f) => {
    const at = AGENT_FOR[f.category];
    if (!at) return acc; // schema-enforced; belt and braces
    (acc[at] ??= { at, items: [] }).items.push(f);
    return acc;
  }, {}),
);

phase('Act');
const plans = await parallel(
  groups.map((g) => () =>
    agent(
      `You own these failures ONLY — do not comment on any others.
       For each, emit: objective, success_criteria, depends_on (failure ids that
       must be fixed first — ids from OTHER groups are expected and welcome),
       and a verification command that re-runs just this failure.
       ${JSON.stringify(g.items)}`,
      {
        label: `plan:${g.at}`,
        phase: 'plan',
        schema: PlanSchema,
        agentType: g.at,
        model: 'opus',
        effort: 'low',
      },
    ),
  ),
);
// BARRIER: sequencing resolves depends_on edges ACROSS groups, so it cannot
// start until every group has returned.

// A dead agent resolves to null. Surface which group was lost instead of
// silently shipping a plan that is missing a whole agent type.
const returned = plans.filter((p) => p && p.items);
const droppedGroups = groups
  .map((g) => g.at)
  .filter((at) => !returned.some((p) => p.agentType === at));
if (droppedGroups.length) log(`plan agents returned nothing for: ${droppedGroups.join(', ')}`);

// --- Stage 3: synthesize one ordered plan ------------------------------------
phase('Synthesize');
return await agent(
  `Merge these per-agent-type plans into ONE ordered fix plan. Topologically
   sequence the depends_on edges the group agents emitted; those edges are
   INFERRED by the group agents, not planned (mcp__pal-mcp-server__planner is not available
   here), so state any cycle or unresolvable edge rather than guessing an order.
   Carry unroutable failures through untouched so they stay visible.
   ${droppedGroups.length ? `These agent types returned nothing and their failures are NOT covered: ${droppedGroups.join(', ')}. List them in dropped_groups.` : ''}
   unroutable: ${JSON.stringify(unroutable)}
   plans: ${JSON.stringify(returned)}`,
  { label: 'synthesize', schema: FixPlanSchema, model: 'opus', effort: 'medium' },
);
