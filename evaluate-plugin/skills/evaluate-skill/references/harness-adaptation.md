# evaluate-skill: adapting the workflow harness

Read this before adapting `workflows/evaluate-skill.workflow.js`. The full framing
(template notice, what may change, what must survive, agent budget, when to skip)
is in [SKILL.md](../SKILL.md) under `## Workflow harness (template)`.

## Consequences for any adaptation

Four consequences worth stating inline:

- **This is the only template in the marketplace that also registers a name.** The
  bundled copy is the source of truth, but `evaluate-plugin:evaluate-plugin-batch`
  resolves it as `workflow('evaluate-skill', ...)`, so a copy must also live in
  `~/.claude/workflows/` and `meta.name` must be exactly `evaluate-skill`. Both
  children have to agree on that literal. Registration, the one-level nesting limit,
  and what to do when the name does not resolve are in
  [`docs/dynamic-workflow-registration.md`](../../../../docs/dynamic-workflow-registration.md).
  Register this one and nothing else.

- **No agent in this harness is worktree-isolated, and that is deliberate.** Every
  rollout agent writes its run dir into the shared checkout (`prepare_run.sh`
  stages it under `tmp/eval-runs/`), and Aggregate has to read what all of
  them wrote; a worktree-isolated agent's writes are invisible to its siblings, so
  isolating them would silently empty the benchmark. Nothing here pushes, opens a PR,
  or mutates a forge either - so the two clauses
  `.claude/rules/workflow-vs-skill.md` requires of a worktree-dispatching template
  (the `resumeFromRunId` / #1868 warning and the sequential-finalise rule) do not
  apply, and adding worktree isolation to an adaptation would pull both of them in
  along with the bug.

- **The harness cannot vary the model across cells.** Every `agent()` call pins
  `model: 'opus'` because `scripts/check-workflow-js-model.sh` requires it, so the
  `config` axis here is `with-skill` / `baseline` and nothing else. A genuine
  cross-model or cross-effort sweep is `evaluate-plugin:evaluate-matrix`'s job and
  stays on its own deliberately sequential path.

- **`context: fork` stays, and it is not what justifies the harness.** The pin lives in
  `scripts/plugin-compliance-check.sh` (the `for fork_skill in` loop inside
  `check_skill_body()` - cited by name, because a line number in that file drifts
  every time a regression guard is inserted) and is unchanged by this template. Per
  `.claude/rules/workflow-vs-skill.md` "The `context: fork` corollary", fork already
  bought context isolation for free - so this harness has to earn its tokens by
  **splitting** rollout from grading behind a real barrier, which it does. Keeping
  `fork` beside a `pipeline()` is sanctioned because the width is **statically
  bounded**: `cellCap` (30 by default, and passed explicitly by the batch caller) is a
  script-decidable ceiling that aborts rather than growing, which is exactly the line
  `.claude/rules/skill-fork-context.md` now draws between a bounded fan-out and the
  unbounded, caller-chosen one the `[1m]` cascade hazard is about.

## Framing detail

The full rationale behind the condensed framing in SKILL.md.

**Preserve across any adaptation:** (a) the fan-out width is the cartesian product
`evalIds.length x runs x configs.length`, computed in JS from the eval-case list the
Preflight agent read off disk with `inspect_eval.sh --print-evals` - never a prose "for
each eval case, for each run"; (b) `GRADE_SCHEMA`'s closed `PASS|PARTIAL|FAIL|ERROR`
status enum plus the split `deterministic*` / `judge*` counters, so a vague verdict is
structurally impossible and a dead agent becomes an explicit `ERROR` row that stays in
the denominator instead of reading as a pass; (c) Aggregate is a real barrier - the
standard deviation and the baseline delta are cross-cell facts no single cell can
compute, and `benchmark.json` has to be written exactly once. Three further things are
structure, not preference: **the grader is never the agent that produced the
transcript** (`.claude/rules/loop-integrity.md` Pillar 1 - an author asked to judge its
own output optimises for done, not for correct), `grade_deterministic.py` grades first
and its verdicts are never re-judged, and the `cellCap` ceiling **aborts** rather than
truncating.

**Agent budget:** 2 + 2 x cells — preflight and aggregate, plus one rollout and one
independent grader per cell (at most `cellCap` cells). The scale guard asks before
every run, because the cell list is built at runtime. `args.harness: 'headless'`
does not change it: the rollout agent becomes a thin runner that calls
`rollout_headless.sh` (and never performs the task itself), still one per cell.

**Skip the harness when:** the run is fewer than three cells - a one- or two-case spot
check, or a single re-run of one eval id - which is a linear pass where the harness is
pure overhead; the script returns `{mode:'inline'}` at that floor. The floor is
deliberately far lower than `configure-all`'s 15, because this harness's marginal cost
is a constant two agents: Steps 4 and 6 already spawn one rollout subagent and
one grader subagent per cell, so the harness redistributes those agents rather than
adding to them.
