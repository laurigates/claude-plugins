// blueprint-story-audit.workflow.js — TEMPLATE, not a script to run verbatim.
//
// Shape: fan-out-and-synthesize (docs/plans/dynamic-workflow-migration.md §5).
// Governing rule: .claude/rules/workflow-vs-skill.md. The framing section that
// makes this file reachable lives in the sibling SKILL.md under
// `## Workflow harness (template)`.
//
// WHAT IS STRUCTURE (do not rewrite):
//
//   1. The capability lane is ONE agent. You cannot partition work by a
//      partition the work itself discovers — Agent 1's brief is literally
//      "group by area", so the areas do not exist until it has run. Only the
//      per-PRD and per-test-root splits are enumerable up front.
//   2. Steps 2 and 4 stay AGENT stages, never JS. Step 2 mandates "verify with
//      a file-level read where ambiguous" and a workflow script has no
//      filesystem; Step 4's core/non-core cutoff is explicitly heuristic.
//   3. The `parallel()` at Step 1 is a real barrier: every join downstream is a
//      cross-lane fact (a capability with no story; a story with no test), so
//      no lane's output is usable until all three have landed.
//   4. The row caps are the skill's own, not invented here — see ROW_LIMIT.
//
// A repo with one PRD and one test directory collapses to THREE agents total
// (capability + story + test), then the three sequential stages. At that width
// the harness is pure overhead; run the skill linearly instead.

export const meta = {
  name: 'blueprint-story-audit',
  phases: [
    { title: 'discover' },
    { title: 'join' },
    { title: 'triage' },
    { title: 'synthesize' },
  ],
};

// ---------------------------------------------------------------------------
// Args. The fan-out width is enumerated by the SKILL.md `## Context` block's
// `find` output (PRD files, test directories) — never by the model, and never
// by a prose "for each PRD".
// ---------------------------------------------------------------------------
const PRDS = args.prds ?? [];
const TEST_ROOTS = args.testRoots ?? [];
const SCOPE = args.scope ?? null;

// The capability lane's row cap, verbatim from SKILL.md Step 1 Agent 1
// ("Cap output at 200 rows"). It is NOT divided across lanes:
//   - the capability lane is one agent, so there is nothing to divide;
//   - the PRD and test lanes are exhaustive extractions ("Don't infer — only
//     extract", "List every test file"), so a derived per-lane budget would
//     silently drop stories and tests the audit is supposed to surface.
// AREA_ROW_LIMIT is REFERENCE.md's per-area cap in the artifact template.
const ROW_LIMIT = 200;
const AREA_ROW_LIMIT = 15;

// ---------------------------------------------------------------------------
// Schemas. These are the determinate-verdict half of the harness: the enums
// below are the four-status drift table (SKILL.md Step 2), the three-tier test
// match (Step 3), and the five-row tier table (Step 4). Prose can drift off
// them; a schema cannot.
// ---------------------------------------------------------------------------
const KIND = ['route', 'cli', 'event-handler', 'component', 'cron', 'worker'];
const DRIFT_STATUS = ['implemented', 'partial', 'missing', 'candidate'];
const CONFIDENCE = ['exact', 'weak', 'none']; // ✓ / ~ / ✗
const TIER = [1, 2, 3, 4, 5];

const capS = {
  type: 'object',
  required: ['rows', 'truncated'],
  additionalProperties: false,
  properties: {
    rows: {
      type: 'array',
      maxItems: ROW_LIMIT,
      items: {
        type: 'object',
        required: ['area', 'capability', 'evidence', 'kind'],
        additionalProperties: false,
        properties: {
          area: { type: 'string' },
          capability: { type: 'string' },
          evidence: { type: 'string' }, // file:line
          kind: { type: 'string', enum: KIND },
        },
      },
    },
    unusedDeps: {
      type: 'array',
      items: {
        type: 'object',
        required: ['dependency', 'evidence'],
        properties: {
          dependency: { type: 'string' },
          evidence: { type: 'string' },
        },
      },
    },
    // "+ N more in <area>" tails, so a truncated survey is visible rather than
    // presenting as a complete one.
    truncated: {
      type: 'array',
      items: {
        type: 'object',
        required: ['area', 'omitted'],
        properties: { area: { type: 'string' }, omitted: { type: 'integer' } },
      },
    },
  },
};

const storyS = {
  type: 'object',
  required: ['prd', 'rows'],
  additionalProperties: false,
  properties: {
    prd: { type: 'string' },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['prdId', 'storyId', 'behaviour'],
        additionalProperties: false,
        properties: {
          prdId: { type: 'string' },
          storyId: { type: 'string' },
          behaviour: { type: 'string' }, // verbatim, not paraphrased
          deps: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    knownDrift: { type: 'array', items: { type: 'string' } },
  },
};

const testS = {
  type: 'object',
  required: ['root', 'rows'],
  additionalProperties: false,
  properties: {
    root: { type: 'string' },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'suite', 'testCount', 'skippedCount'],
        additionalProperties: false,
        properties: {
          file: { type: 'string' },
          suite: { type: 'string' },
          testCount: { type: 'integer' },
          skippedCount: { type: 'integer' },
          storyRefs: { type: 'array', items: { type: 'string' } },
          skipComments: {
            type: 'array',
            items: {
              type: 'object',
              required: ['evidence', 'comment'],
              properties: {
                evidence: { type: 'string' }, // file:line
                comment: { type: 'string' },  // verbatim
              },
            },
          },
        },
      },
    },
  },
};

const joinS = {
  type: 'object',
  required: ['drift', 'coverage', 'tiers', 'tierCutoff', 'storyCount', 'tier1GapCount'],
  additionalProperties: false,
  properties: {
    drift: {
      type: 'array',
      items: {
        type: 'object',
        required: ['subject', 'status', 'evidence'],
        additionalProperties: false,
        properties: {
          subject: { type: 'string' },
          status: { type: 'string', enum: DRIFT_STATUS },
          evidence: { type: 'string' },
          note: { type: 'string' },
        },
      },
    },
    coverage: {
      type: 'array',
      items: {
        type: 'object',
        required: ['storyId', 'tests', 'testCount', 'skipped', 'confidence'],
        additionalProperties: false,
        properties: {
          storyId: { type: 'string' },
          tests: { type: 'array', items: { type: 'string' } },
          testCount: { type: 'integer' },
          skipped: { type: 'integer' },
          confidence: { type: 'string', enum: CONFIDENCE },
        },
      },
    },
    tiers: {
      type: 'array',
      items: {
        type: 'object',
        required: ['tier', 'subject', 'why'],
        additionalProperties: false,
        properties: {
          tier: { type: 'integer', enum: TIER },
          subject: { type: 'string' },
          why: { type: 'string' },
        },
      },
    },
    // Step 4: "Document the cutoff used at the top of the artifact so the user
    // can override." A schema field makes that non-optional.
    tierCutoff: { type: 'string' },
    storyCount: { type: 'integer' },
    tier1GapCount: { type: 'integer' },
  },
};

const bugS = {
  type: 'object',
  required: ['bugs'],
  additionalProperties: false,
  properties: {
    bugs: {
      type: 'array',
      items: {
        type: 'object',
        required: ['evidence', 'comment', 'classification'],
        additionalProperties: false,
        properties: {
          evidence: { type: 'string' },
          comment: { type: 'string' },
          classification: {
            type: 'string',
            enum: ['bug-report', 'not-yet-implemented'],
          },
        },
      },
    },
  },
};

// The composition agent's return IS the skill's Step 7 input. Every field here
// is consumed by SKILL.md Step 7 — artifactPath by the Write, and
// auditResult / storyCount / tier1GapCount by the manifest `jq` block.
const artifactS = {
  type: 'object',
  required: ['artifactPath', 'storyCount', 'tier1GapCount', 'auditResult', 'summaryLine'],
  additionalProperties: false,
  properties: {
    artifactPath: { type: 'string' },
    storyCount: { type: 'integer' },
    tier1GapCount: { type: 'integer' },
    auditResult: { type: 'string' }, // "success" | "{N} drift entries" | "failed: {reason}"
    summaryLine: { type: 'string' },
    body: { type: 'string' }, // the filled template, for the skill to Write
  },
};

// ---------------------------------------------------------------------------
// Step 1 — discovery fan-out.
// ---------------------------------------------------------------------------
phase('Step 1 — discovery fan-out');

const [caps, stories, tests] = await parallel([
  // BARRIER: every downstream join is a cross-lane fact, so nothing can start
  // until all three lanes have landed.

  // Lane 1 — capability map. ALWAYS ONE AGENT. It discovers the area
  // partition, so it cannot be split by that partition.
  () =>
    agent(
      `Survey ${SCOPE ?? 'the codebase'} and list every user-facing capability.
Group by area (auth, billing, search, ...). For each capability emit one row:
area, capability, entry-point evidence as "file:line", and kind (one of
${KIND.join(', ')}).
Also flag dependencies that look declared-but-unused (an imported library whose
main API is never called) under unusedDeps.
Cap output at ${ROW_LIMIT} rows total and about ${AREA_ROW_LIMIT} rows per area;
record every omission in truncated as {area, omitted} rather than silently
dropping it. Read-only.`,
      { label: 'cap', phase: 'discover', schema: capS, model: 'opus', effort: 'medium' },
    ),

  // Lane 2 — story extraction, one agent per PRD. Enumerable up front: the
  // list comes from --prd flags or the Context block's docs/prds/*.md find.
  () =>
    parallel(
      PRDS.map((p) => () =>
        agent(
          `Read ${p}. Emit one row per stated user story or functional requirement:
prdId, storyId (or section), the verbatim user-visible behaviour, and any linked
deps. Also list every "Known Drift" or status-marked entry verbatim under
knownDrift. Do not infer — only extract. Read-only.`,
          { label: `story:${p}`, phase: 'discover', schema: storyS, model: 'opus', effort: 'low' },
        ),
      ),
    ),

  // Lane 3 — test inventory, one agent per test root. Enumerable up front from
  // the Context block's test-directory find.
  () =>
    parallel(
      TEST_ROOTS.map((t) => () =>
        agent(
          `Inventory every test file under ${t}. Per file emit: file, suite
(describe/class name), testCount, skippedCount, and storyRefs for any story ID
cited in a top-level comment or describe block (PRD-NNN, FR-N.N, story name).
For each test.todo / xit / skip / @pytest.mark.skip block that carries a
comment, emit a skipComments entry with "file:line" evidence and the VERBATIM
comment. Read-only.`,
          { label: `test:${t}`, phase: 'discover', schema: testS, model: 'opus', effort: 'low' },
        ),
      ),
    ),
]);

// A failed agent() resolves to null. Drop the holes rather than letting them
// explode at the join (agent-development.md § Dynamic Workflows).
const storyLanes = (stories ?? []).filter(Boolean);
const testLanes = (tests ?? []).filter(Boolean);

if (!caps) {
  return {
    auditResult: 'failed: capability survey returned no result',
    storyCount: 0,
    tier1GapCount: 0,
  };
}

// ---------------------------------------------------------------------------
// Steps 2-4 — join, then rank. ONE agent, deliberately: Step 2 requires a
// file-level read where a match is ambiguous, and this script has no
// filesystem. Step 4's core/non-core cutoff is a documented heuristic, not a
// rule a script can apply.
// ---------------------------------------------------------------------------
phase('Steps 2-4 — join capabilities to stories, map tests, rank tiers');

const join = await agent(
  `You are performing Steps 2-4 of the story audit.

Step 2 — drift. Match each capability to a PRD story on substring overlap of
capability name vs story title. Where a match is AMBIGUOUS, do a file-level read
of the capability's evidence path before deciding. Classify every subject with
exactly one status: implemented (capability has a matching story), partial
(story exists but a named sub-behaviour is missing), missing (story with no
capability), candidate (capability with no story — an implicit story). Flag each
declared-but-unused dependency as a missing entry. Do NOT promote candidates
into the PRD.

Step 3 — coverage. For every story, find matching tests by (1) an explicit story
ID in the test file or describe block => confidence "exact"; (2) file-path
proximity => confidence "exact"; (3) keyword overlap only => confidence "weak".
A story with zero matched tests is confidence "none".

Step 4 — tiers. Apply the five-row tier table: 1 core capability x zero tests,
2 core capability x weak-confidence tests only, 3 missing PRD story, 4 candidate
from Step 2, 5 healthy. The core/non-core cutoff is heuristic — kind is the
strongest signal (route and event-handler lean core; component leans non-core).
State the cutoff you used in tierCutoff so the user can override it.

Set storyCount to the number of stories in the inventory and tier1GapCount to
the number of tier-1 rows.

Capabilities: ${JSON.stringify(caps)}
Stories: ${JSON.stringify(storyLanes)}
Tests: ${JSON.stringify(testLanes)}`,
  { label: 'join', phase: 'join', schema: joinS, model: 'opus', effort: 'medium' },
);

// ---------------------------------------------------------------------------
// Step 5 — classify skipped tests. Skipped when there is nothing to classify,
// so a clean repo pays no agent here.
// ---------------------------------------------------------------------------
phase('Step 5 — classify skipped tests');

const skips = testLanes.flatMap((lane) =>
  (lane.rows ?? []).flatMap((r) => r.skipComments ?? []),
);

const bugs = skips.length
  ? await agent(
      `Each entry below is a skipped/todo test and its verbatim comment. Classify
each as "bug-report" (the comment describes behaviour that is broken) or
"not-yet-implemented" (the comment describes work not started). Preserve the
evidence and comment fields verbatim. Do not file issues.

${JSON.stringify(skips)}`,
      { label: 'bug-triage', phase: 'triage', schema: bugS, model: 'opus', effort: 'low' },
    )
  : { bugs: [] };

// ---------------------------------------------------------------------------
// Steps 6/7 — compose ONE artifact. The skill writes it; this returns the
// values Step 7 interpolates.
// ---------------------------------------------------------------------------
phase('Steps 6/7 — compose one artifact');

return await agent(
  `Fill the audit-artifact template at REFERENCE.md#audit-template using the
data below. Fill all sections: Summary, Capability map (grouped by area, about
${AREA_ROW_LIMIT} rows per area with the long tail collapsed to "+ N more"),
Story inventory (explicit + candidate), Drift report, Coverage matrix, Tiered
gap analysis with a one-line "why this matters" per tier, and Bugs surfaced by
audit (only if there are any). Put the tier cutoff at the top of the artifact.

Set artifactPath to docs/blueprint/audits/${args.today ?? '<YYYY-MM-DD>'}-story-audit.md,
appending -2, -3, ... if a file with that name already exists. Return body as the
filled template.

Return storyCount, tier1GapCount, auditResult and summaryLine as well —
auditResult / storyCount / tier1GapCount are exactly the values the skill's
Step 7 manifest jq block interpolates as AUDIT_RESULT / STORY_COUNT /
TIER1_GAP_COUNT.

Join: ${JSON.stringify(join)}
Bugs: ${JSON.stringify(bugs)}`,
  { label: 'compose', phase: 'synthesize', schema: artifactS, model: 'opus', effort: 'medium' },
);
