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
