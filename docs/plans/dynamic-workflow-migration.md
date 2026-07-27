# Dynamic-workflow migration plan — claude-plugins

> **Status:** evaluation only — nothing in this plan has been implemented.
>
> **Question asked:** which of this repo's skills would work better as Claude Code
> *dynamic workflows*, and which harness shape fits each?
>
> **Method:** a 16-agent dynamic workflow (`skills-to-workflows-migration-eval`),
> run 2026-07-27. Four phases — fan-out triage of 47 candidate skills across 6
> domain groups against a 6-axis rubric; per-group harness design; adversarial
> challenge from three independent lenses (token economics, determinism
> regression, shape mismatch); synthesis. 18 candidates were nominated, 21
> individual refutations were raised, and 6 candidates were demoted by majority
> refutation. The rejections in this document are as load-bearing as the
> recommendations.
>
> **Source of the shape taxonomy:** [*A harness for every task: dynamic workflows
> in Claude Code*](https://claude.com/blog/a-harness-for-every-task-dynamic-workflows-in-claude-code).

## Verdict

Of the 47 skills evaluated, **five should actually ship a workflow harness** (`workflow-verify-before-filing`, `configure-all`, `evaluate-plugin-batch`, `test-analyze`, `blueprint-story-audit`), and four more get a **narrowed template scoped to a batch-only path** (`git-pr-feedback --all`, `evaluate-skill`, `git-issue --parallel`, `cold-read-gate` batch). The remaining 38 stay as they are — and for three survivors (`execution-grounded-review`, `agents-analyze`, `workflow-wave-dispatch`) the honest outcome is **schema and prose edits only, no `.js`**.

The single pattern that separates movers from stayers: **the fan-out width must already be enumerable by something other than the model.** Every genuine mover reads its N from a deterministic source that already exists — `list-components.sh`'s `COMPONENT=` rows, a candidate manifest, `len(evals) × runs × configs`, a plugin's `skills/*/SKILL.md` glob. Every rejection failed because either (a) the N was invented by the design (`agents-analyze`'s 40 plugin agents, `code-review`'s 6 clusters × 3 lenses), or (b) the "loop bound" the workflow would own was **already enforced by a shell script or a CI compliance pin**, so the harness bought bookkeeping at opus rates. The second-order pattern is that `context: fork` has already spent the context-pressure argument for 8 skills — if a skill holds `fork`, "the output floods the main window" is not available as a justification.

---

## Ranked migration candidates

Tier A = ship the harness. Tier B = ship a template narrowed to one path. Tier C = **do not ship a `.js`**; take the schema/prose edit and stop.

| # | Tier | Skill | Shape | Fan-out unit | Why a workflow wins | Distribution |
|---|------|-------|-------|--------------|---------------------|--------------|
| 1 | A | `workflow-orchestration-plugin/workflow-verify-before-filing` | composite (fan-out → generate-and-filter) | one (verify ∥ search) pair per candidate; then draft → haiku cold-read per survivor | Agent count is **identical before and after** — REFERENCE.md already ships the JS skeleton and the skill already runs this shape. The gate `['still-present','partially-fixed'].includes(verdict) && duplicateFound === 'no'` is a boolean prose kept re-deriving. Zero refutations. | skill-bundled |
| 2 | A | `configure-plugin/configure-all` | fan-out-and-synthesize | one check agent per applicable roster row (`list-components.sh`) | Fan-out width is **already deterministic** — the script emits it. 34 of 38 components have no script, so the checks are genuinely agent-shaped. Not a `context: fork` holder, so its context problem is live and unaddressed. Zero refutations. | skill-bundled |
| 3 | A | `evaluate-plugin/evaluate-plugin-batch` | fan-out-and-synthesize | one nested `evaluate-skill` run per `skills/*/SKILL.md` with evals | The clean textbook case: `parallel()` replaces a hand-rolled `--parallel N`, and `aggregate_benchmark.sh` is a real barrier. **Must ship capped** — see caveats. | skill-bundled |
| 4 | A | `testing-plugin/test-analyze` | classify-and-act | one agent per non-empty failure **agent type** | The only design in the set that **prices itself**: `if (failures.length < 5) return {mode:'inline'}` plus a structural cap of 8 categories. Zero refutations. | skill-bundled |
| 5 | A | `blueprint-plugin/blueprint-story-audit` | fan-out-and-synthesize | 3 lanes; per-PRD and per-test-root splits only | Step 1 is already "three Task calls in one message … wait for all three" — a barrier written as prose — and the pipe-delimited row format is a JSON Schema wanting to exist. | skill-bundled |
| 6 | B | `git-plugin/git-pr-feedback` (`--all` only) | fan-out-and-synthesize | one worktree agent per actionable PR | Step 6 already specifies a full JSON return contract; the harness makes it enforced. Single-PR path stays prose. | skill-bundled |
| 7 | B | `evaluate-plugin/evaluate-skill` | fan-out-and-synthesize | one rollout agent per (case × run × config) cell | The cartesian product belongs in a script. **Only skill that needs `~/.claude/workflows` registration**, so `evaluate-plugin-batch` can `workflow('evaluate-skill', …)`. | **both** |
| 8 | B | `git-plugin/git-issue` (`--parallel` only) | composite | one worktree agent per conflict-free group | Grouping + barrier + sequential finalise is real. Single-issue path is the modal case and stays linear. | skill-bundled |
| 9 | B | `agent-patterns-plugin/cold-read-gate` (batch only) | adversarial-verification | one haiku reader per outward-bound artifact | Weak. The #2063 motivation is already spent (SKILL.md:52 pins `run_in_background: false`). Ship only if a real N≥3 batch path is wanted. | skill-bundled |
| 10 | C | `agent-patterns-plugin/execution-grounded-review` | adversarial-verification | — | **No `.js`.** Add the `LEDGER` schema with the required `sequenceMatchesProduction` enum to the existing single-verifier dispatch. That is the entire gain at zero added agents. This skill is the Pillar-1 oracle other loops call — a 19-agent design multiplies through every iteration in the repo. | skill edit only |
| 11 | C | `agents-plugin/agents-analyze` | fan-out-and-synthesize | — | **No `.js`.** 42× multiplier against a skill that already holds `context: fork` (CI-pinned at `plugin-compliance-check.sh:826`). If goal drift across 40 plugins is real, chunk the existing forked agent's TodoWrite list. | skill edit only |
| 12 | C | `workflow-orchestration-plugin/workflow-wave-dispatch` | fan-out-and-synthesize | — | **No `.js`.** The harness requires a fixed `args.waves` array — which *is* writing wave N+1's plan before wave N's gate, the exact thing the skill forbids twice. Land the one new Common-Scheduling-Mistakes row and stop. | skill edit only |

### 1. `workflow-verify-before-filing`

Promote the REFERENCE.md skeleton to `verify-before-filing.workflow.js` beside SKILL.md. Two surviving caveats applied: **waves of ≤5** (the skill paces its *writes* at 70 s but left reads unbounded — a 24-candidate manifest would fire 48 concurrent agents at an instance the skill itself calls aggressively rate-limiting), and **`DRAFT_SCHEMA` carries the body**, because batch-dedup cannot merge on a path a workflow script cannot read.

```js
export const meta = { name: 'verify-before-filing',
  phases: [{title:'Verify'},{title:'Search'},{title:'Draft'},{title:'ColdRead'},{title:'Revise'},{title:'BatchDedup'}] }

const CANDIDATES = (typeof args === 'string') ? JSON.parse(args) : args.candidates
const WAVE = 5                                     // pace reads like Phase 3 paces writes

const triaged = []
for (let i = 0; i < CANDIDATES.length; i += WAVE) {
  phase(`Verify + dedup — candidates ${i + 1}..${Math.min(i + WAVE, CANDIDATES.length)}`)
  const wave = await pipeline(CANDIDATES.slice(i, i + WAVE),
    async (item) => {
      const [verify, search] = await parallel([     // BARRIER (intra-candidate): the gate needs BOTH
        () => agent(VERIFY_PROMPT(item), {label:`verify:${item.id}`, phase:'Verify', schema:VERIFY_SCHEMA}),
        () => agent(SEARCH_PROMPT(item), {label:`search:${item.id}`, phase:'Search', schema:SEARCH_SCHEMA}),
      ])
      if (!verify || !search) return {...item, disposition:'agent-error'}
      const passes = ['still-present','partially-fixed'].includes(verify.verdict)
                  && search.duplicateFound === 'no'  // gate precedence: a duplicate kills regardless of verdict
      return {...item, verify, search, disposition: passes ? 'draft'
        : (search.duplicateFound !== 'no' ? `duplicate: ${search.wave1Overlap}` : verify.verdict)}
    },
    async (c) => {                                   // draft only survivors; schema carries body, not just path
      if (c.disposition !== 'draft') return c
      const draft = await agent(DRAFT_PROMPT(c), {label:`draft:${c.id}`, phase:'Draft', schema:DRAFT_SCHEMA})
      return draft ? {...c, draft} : {...c, disposition:'draft-failed'}
    },
    async (c) => {                                   // adversarial gate — NEVER the drafter
      if (!c.draft) return c
      let cold = await agent(COLDREAD_PROMPT(c.draft.body),
        {label:`coldread:${c.id}`, phase:'ColdRead', model:'haiku', schema:COLD_SCHEMA})
      if (cold?.verdict === 'needs-revision') {
        const rev = await agent(REVISE_PROMPT(c.draft, cold.critique), {label:`revise:${c.id}`, phase:'Revise', schema:DRAFT_SCHEMA})
        if (rev) c = {...c, draft: rev}
        cold = await agent(COLDREAD_PROMPT(c.draft.body),
          {label:`recoldread:${c.id}`, phase:'ColdRead', model:'haiku', schema:COLD_SCHEMA})
      }                                              // exactly ONE revise round — a fixed gate, not a loop
      return {...c, cold, disposition:'file'}
    })
  triaged.push(...wave)
}

phase('Batch dedup — BARRIER: survivors compared to EACH OTHER, not just to the tracker')
const filing = triaged.filter(c => c.disposition === 'file')
const batch = await agent(BATCH_DEDUP_PROMPT(filing), {label:'batch-dedup', phase:'BatchDedup', schema:BATCH_SCHEMA})
return { file: batch.keep, merged: batch.merged,   // Phase 3 (scripts/file-wave.sh) consumes this
         dispositions: triaged.map(c => ({id:c.id, slug:c.slug, disposition:c.disposition})) }
```

**SKILL.md delta.** Under `## The Pipeline`, add the template framing (snippet in *Distribution decision* below), then: *"Phases 1–2 ship as `verify-before-filing.workflow.js`. Non-negotiable across any adaptation: the closed verdict vocabulary; the gate expression (a duplicate kills the filing regardless of verdict); the cold-read agent being a different agent from the drafter; the batch-dedup barrier; and the ≤5 read wave. A 24-candidate run is roughly 100–140 agents — if your run has one candidate, skip the workflow and do Phase 1 inline."* **Blocking prerequisite:** the rationale's claim that "Phase 3 is already a deterministic substrate" is false — there is no `scripts/` directory in this skill. Extract REFERENCE.md's pacing loop to `scripts/file-wave.sh` with `scripts/tests/test-file-wave.sh` **in the same change**, or the plan promotes the judgement half to an executable while leaving the purely mechanical half as retyped prose.

### 2. `configure-all` (check path only)

The classify agent is **deleted** — applicability is `types === 'all' || types.split(',').includes(projectType)` over a field `list-components.sh` already emits. `--fix` never enters the workflow: pre-commit and linting both write `.pre-commit-config.yaml`.

```js
export const meta = { name:'configure-all-check', phases:[{title:'Check'},{title:'Synthesize'}] }
const { roster, projectType, ambiguous = [] } = (typeof args === 'string') ? JSON.parse(args) : args
if (!roster?.length) { log('empty roster — list-components.sh returned STATUS=ERROR; abort'); return { abort:true } }

// TYPES is manifest data, not a judgement. No agent decides this.
const applicable = roster.filter(r => r.types === 'all' || r.types.split(',').includes(projectType))
const skipped    = roster.filter(r => !applicable.includes(r)).map(r => ({...r, reason:`TYPES=${r.types}`}))
if (applicable.length < 15) { log(`${applicable.length} components — sequential path is cheaper; abort`); return { abort:true } }

phase(`Check — ${applicable.length} components, READ-ONLY, ≤5 in flight`)
const checks = []
for (let i = 0; i < applicable.length; i += 5) {
  const wave = applicable.slice(i, i + 5)
  const got = await parallel(wave.map(c => () => agent(
    `Invoke /configure:${c.component} --check-only via SlashCommand. READ-ONLY — report findings, write nothing.`,
    { label:`check:${c.component}`, phase:'Check', schema: CHECK_SCHEMA })))
  checks.push(...got.map((r, j) => r || { component: wave[j].component, status:'ERROR', issues:['agent returned null'], files:[] }))
}

phase('Synthesize — BARRIER: the fix plan must see every component at once')
const report = await agent(SYNTH_PROMPT(checks, skipped),   // groups components contending for the same file
  { label:'synthesize', phase:'Synthesize', schema: REPORT_SCHEMA })
return { report, fixPlan: report.fixPlan }                  // --fix applied OUTSIDE, sequentially, by the skill
```

**SKILL.md delta.** New `### Step 3b: Heavy path — parallel check fan-out (optional)` between Steps 3 and 4, with the template framing and an explicit floor: *"below ~15 applicable components the sequential path is cheaper than 15 agent preambles."* Step 5 gains: *"`--fix` never runs inside the workflow. Several components mutate the same files; parallel fixers would race. Apply the `fixPlan` sequentially."* **Two hard prerequisites the design omitted:** `allowed-tools` currently has no `Task`/`Agent` — add it; and each check agent's toolset must include `SlashCommand`, or it will re-derive a component check from scratch instead of invoking it. Replace the hardcoded four-way `## Agent Teams (Optional)` table with a pointer to the harness. Note that `exitCode` cannot come from a workflow — the skill converts the report to a process exit code.

### 3. `evaluate-plugin-batch`

Ships only with three caps applied. Without them this is a one-command path to ~480 agents on a 48-skill plugin, against a repo that currently has **one `evals.json`** and a `skill-evaluation.md` Tier-2 cadence of "monthly + on model release".

```js
phase('Discover skills');
const inv = await agent(
  `Inventory ${args.plugin}: bash evaluate-plugin/scripts/inspect_eval.sh --plugin-dir ${args.plugin}.
   Report {path,dir,name,hasEvals} per skills/*/SKILL.md. Evaluate NOTHING.`,
  { label:'inventory', schema: InventorySchema, model:'opus', effort:'low' });

const included = inv.skills.filter(s => s.hasEvals || args.createMissingEvals);
const CAP = args.cap ?? 25;                      // skill-evaluation.md golden set — refuse above it
if (included.length > CAP) return { abort:true, reason:`${included.length} skills exceeds the golden-set cap ${CAP}` };
const WAVE = args.parallel ?? 1;                 // honour --parallel N (default 1); never supersede it
log(`${inv.skills.length} skills: ${included.length} included, ${inv.skills.length - included.length} skipped`);

phase(`Evaluate ${included.length} skills`);
const results = [];
for (let i = 0; i < included.length; i += WAVE) {
  const wave = included.slice(i, i + WAVE);
  results.push(...await parallel(wave.map(s => () => workflow('evaluate-skill', {
    skill: s.path, skillDir: s.dir, runs: args.runs ?? 1,
    baseline: args.baseline ?? false, createEvals: !s.hasEvals, cellCap: 30 }))));
}

phase('Aggregate plugin report');   // SYNTHESIS BARRIER
return await agent(
  `bash evaluate-plugin/scripts/aggregate_benchmark.sh ${args.plugin}
   Report denominators FROM that script's output (it computes total_skills and evaluated_count itself).
   Cross-check against workflow included=${included.length}; if they DISAGREE, emit status:"partial-sweep"
   — that disagreement is the anti-laziness signal, not a rounding error.`,
  { label:'aggregate', schema: PluginReportSchema, model:'opus' });
```

Three deletions from the original design: the per-skill `isolation:'worktree'` "normalize benchmark" stage (48 worktree agents to perform a `Read`, and a worktree reader cannot see a file another agent wrote); the uncapped `pipeline()`; and the workflow's own denominator count as the authority. `context: fork` stays **off** — sanctioned at `plugin-compliance-check.sh:818-821`.

### 4. `test-analyze`

Classify is **merged into Parse** (the 8-row routing table plus a 4-value severity enum is a lookup the parse agent can do while it already holds the failures), and `AGENT_FOR` is keyed off agent names that **actually exist**.

```js
phase('Parse + classify');
const parsed = await agent(
  `Read every result file under ${args.resultsPath}. Per failure emit
   {id, test, file, message, stack_head, category, severity} using the enums below.
   Anything fitting no category goes to unroutable[] with a reason.`,
  { label:'parse', schema: RoutedFailuresSchema, model:'opus' });

if (parsed.failures.length < 5) {            // HARD FLOOR, not a knob
  log(`only ${parsed.failures.length} failures — use the inline path in SKILL.md`);
  return { mode:'inline', failures: parsed.failures };
}

// Real agent names from agents-plugin/agents/*.md — NOT the stale table in SKILL.md.
const AGENT_FOR = { accessibility:'review', security:'security-audit', performance:'performance',
                    quality:'refactor', flaky:'test', integration:'debug', ci:'ci', docs:'docs' };
const groups = Object.values(parsed.failures.reduce((acc, f) => {   // group by AGENT TYPE, not category
  const at = AGENT_FOR[f.category]; (acc[at] ??= { at, items: [] }).items.push(f); return acc }, {}));

phase('Act');
const plans = await parallel(groups.map(g => () => agent(
  `You own these failures ONLY. Per failure: objective, success criteria, depends_on (by failure id),
   verification command. ${JSON.stringify(g.items)}`,
  { label:`plan:${g.at}`, phase:'plan', schema: PlanSchema, agentType: g.at, model:'opus' })));
// BARRIER: sequencing resolves dependencies ACROSS groups.

phase('Synthesize');
return await agent(`Merge into ONE ordered fix plan; topologically sequence the depends_on edges the
  group agents emitted (mcp__pal__planner is NOT available here — the edges are inferred, not planned).
  Unroutable: ${JSON.stringify(parsed.unroutable)}\n${JSON.stringify(plans.filter(Boolean))}`,
  { label:'synthesize', schema: FixPlanSchema, model:'opus' });
```

**SKILL.md delta.** Fix the stale agent-type names in the body first — that is a bug independent of any workflow. Collapse the routing table's two copies into one under `## Subagent Selection Logic`, annotated *"this table is the contract the workflow's category enum and `AGENT_FOR` map encode — edit them together."* Add to the new workflow section: *"the harness surrenders `mcp__pal__planner`; a run that needs PAL planning should stay inline"* and *"`context: fork` is pinned at `plugin-compliance-check.sh:826` and stays; the `parallel()` width is capped at the fixed agent-type set precisely so it does not become the wide fan-out `skill-fork-context.md` warns about."*

### 5. `blueprint-story-audit`

The capability lane stays **one agent** — you cannot partition work by a partition the work discovers (Agent 1's brief is literally "group by area"). Only the per-PRD and per-test-root splits are enumerable up front. Steps 2 and 4 stay agent stages, not JS: Step 2 mandates "verify with a file-level read where ambiguous" (a workflow script has no filesystem) and Step 4's tier cutoff is explicitly heuristic.

```js
const ROW_LIMIT = Math.floor(600 / (1 + args.prds.length + args.testRoots.length));  // preserve the artifact cap

phase('Step 1 — discovery fan-out');
const [caps, stories, tests] = await parallel([        // BARRIER: the joins need all three lanes
  () => agent(`Survey ${args.scope ?? 'the codebase'}. One row per user-facing capability, grouped by area,
               ${ROW_LIMIT} max, file:line evidence. Read-only.`,
       {label:'cap', phase:'discover', schema:capS, model:'opus'}),
  () => parallel(args.prds.map(p => () => agent(`Read ${p}. Extract stated stories/FRs verbatim + Known Drift.`,
       {label:`story:${p}`, phase:'discover', schema:storyS, effort:'low'}))),
  () => parallel(args.testRoots.map(t => () => agent(`Inventory tests under ${t}.`,
       {label:`test:${t}`, phase:'discover', schema:testS, effort:'low'}))),
])

phase('Steps 2-4 — join, then rank');
const join = await agent(`Match capabilities to stories on substring overlap; where AMBIGUOUS do a file-level
  read before deciding. Then apply the three-tier test match and the 5-row tier table.
  ${JSON.stringify({caps, stories: stories.flat(), tests: tests.flat()})}`,
  {label:'join', schema:joinS, model:'opus'})

phase('Step 5 — classify skipped tests');
const skips = tests.flat().filter(Boolean).flatMap(t => t.rows.flatMap(r => r.skipComments || []))
const bugs = skips.length ? await agent(`Classify each as bug-report or not-yet-implemented:\n${JSON.stringify(skips)}`,
  {label:'bug-triage', schema:bugS, effort:'low'}) : {bugs:[]}

phase('Step 6/7 — compose one artifact');
return await agent(`Fill REFERENCE.md#audit-template. Return artifactPath, storyCount, tier1GapCount,
  auditResult, summaryLine — exactly the values SKILL.md:161-163's jq block interpolates.
  ${JSON.stringify({join, bugs})}`, {label:'compose', phase:'synthesize', model:'opus', schema:artifactS})
```

**SKILL.md delta.** New `## Workflow harness (template)` between Parameters and Execution with the standard framing plus: *"a repo with one PRD and one test dir collapses to three agents; the capability lane is always ONE agent because it discovers the area partition."* Annotate Step 7's jq block *"values come from the composition agent's structured return"* and Step 8 *"stays in the skill — a workflow cannot AskUserQuestion; `--report-only` is the orchestrated path."*

---

## Shape assignments at a glance

| Shape | Skills that fit | One-line justification |
|---|---|---|
| **Fan-out-and-Synthesize** | `configure-all`, `evaluate-plugin-batch`, `evaluate-skill`, `blueprint-story-audit`, `git-pr-feedback --all` | The repo's dominant shape by a wide margin: every case has an N enumerated by a script or a manifest, plus an aggregation step that genuinely needs all N (`aggregate_benchmark.sh`, a cross-file fix plan, a cross-story tier ranking). |
| **Classify-and-Act** | `test-analyze` (primary); `git-issue --parallel` and `configure-all` as pre-stages | One clean fit — a fixed category→agent-type table restated twice in prose. Every *other* candidate's classifier turned out to be a shell script that already exists (`list-actionable-prs.sh`, `list-components.sh` `TYPES=`, `blueprint-autorun.sh`), which is why they were cut. |
| **Adversarial Verification** | `cold-read-gate` (batch), `verify-before-filing`'s cold-read stage, `execution-grounded-review` (as a schema, not a harness) | The repo already does this well in prose — isolated readers, intent-starved verifiers, separate `eval-grader` agents. The workflow adds a schema-forced verdict enum, not a new structure. `code-review`, the one skill with a *real* self-preference hazard, was rejected on cost. |
| **Generate-and-Filter** | `verify-before-filing` (survivors filtered by the gate) — only as a secondary shape | No skill in the repo is primarily generate-and-filter. Where it appears it is one `.filter()` inside a larger fan-out. `evaluate-improve` is the closest and its bracket was refuted down to exactly this. |
| **Tournament** | **NO fit.** | Both nominees fail structurally, not marginally. `evaluate-improve`'s "bracket" judges an already-sorted list — `survivors.sort((a,b) => b.sourceFailureDelta - a.sourceFailureDelta)` decides the winner and the pairwise rounds can only change it on an exact tie (SKILL.md agrees: comparator is for **ties only**). `multi-model-delegation`'s entire thesis is the *inverse* of a judge: "the value is the disagreement, not the union," resolved against the codebase, never by picking the more confident model. A judge agent would launder a coin-flip. **This repo has no tournament-shaped work**, because its ranking signals are deterministic scores from `grade_deterministic.py`, not judgements. |
| **Loop-Until-Done** | **NO fit.** | Every loop in the repo is bounded by an enumerable set before it starts — it is a fan-out with a ceiling, not unknown-size work. `workflow-checkpoint-refactor` (the one true loop) was rejected because its state packet must survive **session boundaries** and a workflow script runs inside one invocation. `execution-grounded-review`'s two-round loop is a ceiling on retries, and its own "stuck" guard requires two LLM-generated lists to be byte-identical, which never fires. Where this repo needs loop discipline it uses `loop-integrity.md` + a plan file, correctly. |

---

## Rejected, and why

The six that were nominated and killed:

| Skill | Proposed shape | Killed by (lens) | The objection |
|---|---|---|---|
| `code-quality-plugin/code-review` | adversarial-verification | token-economics (**fatal**) + shape-mismatch | Worst cost case in the set: **1 agent today → up to 69**, on the flagship many-times-daily review skill. Both justifications are already paid: `context: fork` (CI-pinned, #980/#1667) already isolates the file set, and the "self-preference" in step 7 is a **re-read of `file:line` against current source** — the judge is the source file, which `loop-integrity.md` classifies as already-independent. 24 of the 69 agents apply a 4-row severity rubric. `agentType:'code-review'` does not exist (`agents-plugin` ships `review`). |
| `workflow-orchestration-plugin/workflow-checkpoint-refactor` | loop-until-done | token-economics + shape-mismatch | Everything valuable is free (`--max-phases=N`, "same phase fails twice → stop", budget floor are frontmatter edits; the packet fields are already pinned by `check-loop-integrity.sh --strict`). Everything paid is waste: a third agent per phase whose brief is one Edit plus one Bash. And `stuck[p.n]`/`maxPhases` are **JS locals** — they silently reset on every `--continue`, defeating the exact runaway the ceiling exists to prevent. The ceiling must be a plan-file field. |
| `evaluate-plugin/evaluate-improve` | tournament | token-economics + shape-mismatch | The headline gain — structural enforcement of the delta-verify gate — **already ships and is already compliance-pinned** (`check_skill_body()` pins `Delta-verify gate`, `source-failure set`, `shrink`). What remains is a bracket that reproduces `sorted[0]`: up to 7 comparator agents to break ties that `grade_deterministic.py` already resolved. SKILL.md is more precise than the design — comparator is for **ties only**. |
| `evaluate-plugin/evaluate-matrix` | fan-out-and-synthesize | token-economics + shape-mismatch | Self-refuting: the sketch's own comment is *"Deliberately NO `parallel()` and NO `pipeline()`"* and `fan_out_unit` concedes *"fan-out is the shape of the work, not of the dispatch."* A strictly sequential `for … await` is a loop. The claim that a script *enforces* serialization where prose only requests it collapses under the template framing — the same model that could ignore the prose can write `parallel()` into the adapted template. If serialization needs teeth, it wants `scripts/run_matrix.sh` (a shell loop genuinely cannot fan out). |
| `blueprint-plugin/blueprint-autopilot` | classify-and-act | determinism-regression + shape-mismatch | `recordManifest()` is called as plain JS but must write `manifest.json` — the workflow API has **no filesystem**. And `blueprint-autorun.sh:185-189` already performs that exact `jq` mutation. So the design moves an already-deterministic write into a script that structurally cannot perform it. Multiplicity is ≤4 sequential agents by the guardrails' own caps. The rationale concedes the remaining prose "wants a routing script more than an agent workflow" — that conclusion should have set the verdict. |
| `agent-patterns-plugin/adversarial-review` | adversarial-verification | token-economics + shape-mismatch | A skill whose stated precondition is "stakes are high, spend deliberately" would pay an opus **gate agent on every invocation, including the ones it refuses** — the precondition exists to spend *less*. Modal case is 1 lens on 1 target (the design detects this, logs "prefer one inline Agent", and runs anyway). The reviewer brief also delegates to "that lens's owning skill checklist" by bare cross-plugin name, which an isolated subagent cannot resolve — the harness silently drops the skill's one load-bearing mechanism. |

**The 35 never nominated** split into two clean groups, and neither is a gap. *Keep-script* (`workflow-preflight`, `health-check`, `code-antipatterns`, `blueprint-feature-tracker-sync`, `blueprint-adr-validate`, `blueprint-derive-tests`, `git-triage`, `changelog-review`, `evaluate-context-engineering`): the mechanical core already lives in tested `check-*.sh`/`.py` with `STATUS=`/`KEY=VALUE` output, and moving it into agents would trade a byte-stable scan for a non-deterministic one — `offload-to-deterministic-substrate.md` run backwards. *Keep-skill* (`parallel-agent-dispatch`, `agent-teams`, `wave-based-dispatch`, `exclusive-lock-dispatch`, `verify-before-plan`, `multi-model-delegation`, `test-quality-analysis`, and the rest): reference/doctrine with no execution body, or judgement at every turn, or an `AskUserQuestion` gate a workflow cannot host.

---

## Distribution decision

**Default: skill-bundled `.js` beside `SKILL.md`.** Nine of the ten shipping templates go here. A file in `~/.claude/workflows/` reads as *runnable*, and these templates are deliberately incomplete — `wave-dispatch.workflow.js` contains no waves, `configure-all.workflow.js` contains no roster. Invoking one against empty `args` spends real worktree agents (some capable of opening PRs) to discover it was a template. Bundling keeps the surrounding prose that frames it.

**One exception — `evaluate-skill` ships to both.** `evaluate-plugin-batch`'s harness calls `workflow('evaluate-skill', {…})`, and one-level nesting needs a resolvable name. Register it; do not register anything else.

**Never `~/.claude/workflows` alone.** Nothing in this migration is repo-agnostic enough to live only in the global directory.

### The reusable SKILL.md framing snippet

Copy verbatim, filling the three bracketed slots. Slot 3 is what makes it a template rather than a script — it names what an adapter is *allowed to rewrite*, which implies everything else is structure:

```markdown
## Workflow harness (template)

`workflows/<name>.workflow.js` ships beside this skill. **It is a TEMPLATE to adapt,
not a script to run verbatim.** Read it, then rewrite it for the work in front of you.

**Adapt freely:** [the agent prompts, the partition/fan-out width, the filter rules,
the project-specific commands].

**Preserve across any adaptation:** [(a) the loop bound comes from <the deterministic
source>, never from a prose "for each"; (b) <the schema/enum that forces a determinate
verdict>; (c) <the barrier and why it is a barrier>].

**Skip the harness when:** [<the modal small case>] — that is a linear pass and the
harness is pure overhead. The steps below remain the authoritative description of
*what* each stage must produce; the harness only fixes *how* the work is split.
```

Two clauses every template that dispatches `isolation:'worktree'` agents must also carry, both already CI-pinned:

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a resume re-runs agents that already succeeded and opens duplicate PRs (#1868). Re-dispatch the failed units fresh and sequentially after checking `gh pr list --head <branch> --state all --json number,state`.

> Push, PR creation, and GitHub mutations happen **only** in the single sequential finalise stage, never inside a fanned-out agent (`sandbox-guidance.md`, multi-agent push delegation).

---

## Repo-level consequences

Five concrete items. Nothing beyond what the migration requires.

**1. One new rule: `.claude/rules/workflow-vs-skill.md`.** This is the only genuinely new knowledge — the migration establishes a third authoring substrate (prose skill / shell script / workflow `.js`) and the repo currently has rules for the first two only. Content: the three gating axes (is N enumerable by something other than the model? is the barrier load-bearing? is the loop bound script-decidable?), the two shapes with **no fit here** and why, and the cost rule that killed six candidates — *if the fan-out width or the classification is already computed by a `check-*.sh`, a workflow that re-derives it in agents is `offload-to-deterministic-substrate.md` run backwards.* Per `context-engineering.md`, scope it with `paths:` (`*/skills/**/workflows/*.js`, `*/skills/**/SKILL.md`) so it is not always-loaded. It sits directly under `offload-to-deterministic-substrate.md` as a sibling of `loop-integrity.md` and `structured-script-output.md`.

**2. `CLAUDE.md`:** one row in the Rules table for the new rule, and one line in **Project Structure** adding `workflows/` to the plugin layout (`skills/<skill-name>/workflows/*.js`). Nothing else — the file is hand-curated and this is a directory-layout fact, not a new lifecycle.

**3. `.claude/rules/plugin-structure.md`:** the `workflows/*.js` location convention (bundled beside `SKILL.md`, named `<purpose>.workflow.js`) and the rule that a bundled workflow must be reachable from a `## Workflow harness (template)` section — an orphan `.js` is dead weight.

**4. `scripts/check-workflow-templates.sh` + `scripts/tests/`, wired into CI.** Required by `regression-testing.md` — several of these templates encode bug fixes, and none is currently guarded:
- every `workflows/*.js` has a `## Workflow harness (template)` reference in its sibling `SKILL.md`, and that section contains the literal string `not a script to run verbatim`;
- any template containing `isolation:'worktree'` also contains `#1868` (mirrors the existing pin at `check-agent-failure-contract.sh:124-125`);
- `cold-read-gate/SKILL.md` retains `run_in_background: false` and `#2063` (the #2063 fix currently has **no** check of its own — the batch template's verdict enum is the second fix to the same bug class);
- `execution-grounded-review/SKILL.md` retains the literal token `loop-integrity.md`, already required by `check-loop-integrity.sh:74` — note it in the delta so a later "tighten the Related section" edit does not fail the build.

**5. Two blocking conflicts to resolve before any code lands.**
- **`context: fork` vs parallel fan-out.** `plugin-compliance-check.sh:826` hard-pins `fork` on `agents-plugin/agents-analyze` and `testing-plugin/test-analyze`, while `.claude/rules/skill-fork-context.md` holds `fork` **off** for skills that fan out in parallel. `agents-analyze` is resolved by not shipping a harness (Tier C). `test-analyze` must state the resolution explicitly in its delta: fork stays, and the `parallel()` width is capped at the fixed agent-type set precisely so it does not become the wide fan-out the rule warns about. **Never a silent frontmatter edit** — changing it requires editing the rule *and* the guard list in the same commit.
- **`workflow-verify-before-filing` cannot ship until `scripts/file-wave.sh` exists** (see §1). Extracting it plus its test is a prerequisite, not a follow-up.

**No new skill in `workflow-orchestration-plugin`.** The authoring convention is about one page and belongs in the `paths:`-scoped rule, not a skill — adding a skill costs listing tokens in every session for content read once per authoring act. Instead: `workflow-wave-dispatch` gains its one Common-Scheduling-Mistakes row (*"Enforcing the wave boundary by discipline alone | Express it as a `parallel()` barrier"*), and `agent-patterns-plugin:parallel-agent-dispatch` gains a short section mapping its Return Contract onto workflow primitives (the contract becomes a JSON Schema; `parallel()` is the barrier its "every returned summary parsed" checklist already assumes) — its own triage entry identifies this as the useful adjacent move.

**Commit scoping:** each shipped `.js` is `feat(<plugin>): …` (minor bump on the published plugin); the new rule, the CLAUDE.md row, and `check-workflow-templates.sh` are `chore`/`ci`. Per `docs-currency.md`, each template lands in the **same commit** as its `SKILL.md` framing section — a `.js` with no framing is exactly the "script to run verbatim" the blog post warns against.