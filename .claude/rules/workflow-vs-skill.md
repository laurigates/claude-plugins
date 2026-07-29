---
created: 2026-07-29
modified: 2026-07-29
reviewed: 2026-07-29
paths:
  - "*/skills/**/workflows/*.js"
  - "*/skills/**/SKILL.md"
---

# Workflow vs Skill — when a bundled `.js` harness earns its tokens

This repo now has **three** authoring substrates, not two:

| Substrate | Good at | Cost |
|---|---|---|
| A `check-*.sh` / `*.py` script | mechanical, repeatable, byte-stable work | ~free per run |
| A prose `SKILL.md` | judgement, ordering, "what each stage must produce" | one skill listing entry; body loads on invoke |
| A **dynamic-workflow `.js`** | *splitting* judgement work across agents with a real barrier and a schema-forced verdict | **one opus agent per fan-out unit, every invocation** |

The third is the new one, and it is the expensive one. This rule is the gate.
It sits directly under [`offload-to-deterministic-substrate.md`](offload-to-deterministic-substrate.md)
as a sibling of [`loop-integrity.md`](loop-integrity.md) and
[`structured-script-output.md`](structured-script-output.md): those three say
*push mechanical work out of the agent loop*; this one says **a workflow harness
is not that push — it is more agents, and it must be paid for.**

Evidence base: [`docs/plans/dynamic-workflow-migration.md`](../../docs/plans/dynamic-workflow-migration.md)
— 47 skills evaluated, 18 nominated, 21 refutations raised, **6 killed on cost**,
5 shipped. Read its §"Rejected, and why" before proposing a harness for anything
not already listed there.

## The three gating axes

Answer all three **before** writing any `.js`. A "no" on any one of them means
the harness is overhead.

| Axis | The question | A "no" looks like |
|---|---|---|
| **1. Enumerable N** | Is the fan-out width already enumerable by something *other than the model*? | The design invents its own N ("6 clusters × 3 lenses", "40 plugin agents") |
| **2. Load-bearing barrier** | Does a stage genuinely need *all* of the previous stage's output before it can start? | The "barrier" is a summary the last agent could have written inline |
| **3. Script-decidable bound** | Is the loop bound decidable by a script, and does it live somewhere that survives a `--continue`? | The bound is a JS local (`stuck[p.n]`, `maxPhases`) that silently resets on resume |

## The separating criterion

> **The fan-out width must already be enumerable by something other than the model.**

This is the single pattern that separated the five movers from the 42 stayers.
Every mover reads its N from a source that already exists:

| Mover | Where N comes from |
|---|---|
| `configure-all` | `list-components.sh`'s `COMPONENT=` rows |
| `workflow-verify-before-filing` | the candidate manifest passed in as `args` |
| `evaluate-skill` | `len(evals) × runs × configs` — a cartesian product |
| `evaluate-plugin-batch` | the plugin's `skills/*/SKILL.md` glob |
| `blueprint-story-audit` | the per-PRD and per-test-root split |

Every rejection failed one of two ways: it **invented** its N, or the "loop
bound" the workflow would own was **already enforced** by a shell script or a CI
compliance pin.

## The cost rule that killed 6 of 18

> If the fan-out width, the classification, or the gate is **already computed by
> a `check-*.sh` / `.py` or pinned by a compliance check**, then a workflow that
> re-derives it in agents is `offload-to-deterministic-substrate.md` **run
> backwards** — it moves byte-stable work back into a non-deterministic loop and
> bills it at opus rates.

Worked instances, all from the migration eval:

- **`code-review`** — 1 agent today → up to 69, on the flagship many-times-daily
  skill. 24 of those 69 apply a 4-row severity rubric.
- **`evaluate-improve`** — the proposed tournament reproduces `sorted[0]`;
  `grade_deterministic.py` already resolved the ranking, and the delta-verify
  gate it claimed to add is *already compliance-pinned*.
- **`blueprint-autopilot`** — the design calls `recordManifest()` as plain JS,
  but the workflow API has **no filesystem**, and `blueprint-autorun.sh` already
  performs that exact `jq` write.
- **`evaluate-matrix`** — self-refuting: its own sketch says "deliberately NO
  `parallel()`". A strictly sequential `for … await` is a loop, not a harness.
- **`workflow-checkpoint-refactor`** — see the loop section below.
- **`adversarial-review`** — a skill whose stated precondition is "stakes are
  high, spend deliberately" would pay an opus gate agent on every invocation,
  *including the ones it refuses*.

## The two shapes with no fit here

Of the six shapes in the source taxonomy, two have **no** instance in this repo.
That is a finding, not a gap to close later — do not go looking for one.

**Tournament — no fit.** This repo's ranking signals are **deterministic scores**
(`grade_deterministic.py`), not judgements. A comparator agent asked to rank an
already-sorted list can only change the order on an exact tie, so the bracket
launders a coin-flip into a decision that looks researched. The one skill whose
thesis sounds tournament-shaped, `multi-model-delegation`, is the *inverse* of a
judge: its value is the **disagreement**, resolved against the codebase, never by
picking the more confident model.

**Loop-until-done — no fit.** Every loop here is bounded by an **enumerable set
before it starts** — that is a fan-out with a ceiling, not unknown-size work. The
one genuine loop, `workflow-checkpoint-refactor`, was rejected for a structural
reason worth internalising: **a workflow script runs inside one invocation**, and
that loop's state packet must survive **session** boundaries. Its ceiling in JS
locals would reset on every `--continue`, defeating the exact runaway the ceiling
exists to prevent. Where this repo needs loop discipline it uses
`loop-integrity.md` plus a plan file, correctly.

## The `context: fork` corollary

`context: fork` **already spends the context-pressure argument.** A skill that
holds `fork` cannot use *"the harness keeps the output out of the main window"*
as its justification — `fork` bought that isolation, for free, with zero extra
agents.

Eight skills are CI-pinned to `context: fork` in `plugin-compliance-check.sh`
(the guard list, currently around lines 899–913): `code-quality-plugin/code-review`,
`agents-plugin/agents-analyze`, `testing-plugin/test-analyze`,
`testing-plugin/test-full`, `documentation-plugin/claude-blog-sources`,
`documentation-plugin/docs-generate`, `evaluate-plugin/evaluate-skill`,
`code-quality-plugin/dry-consolidation`. For any of these, a harness proposal
must argue **splitting**, never context relief.

Two further constraints on that list:

- The pin and [`skill-fork-context.md`](skill-fork-context.md) must agree.
  Changing `context:` on a pinned skill is **never a silent frontmatter edit** —
  it requires editing the rule *and* the guard list in the **same commit**.
- The parallel-fan-out skills (`git-plugin/git-pr-feedback`,
  `evaluate-plugin/evaluate-plugin-batch`, `code-quality-plugin/code-antipatterns`)
  deliberately keep `fork` **off** and are intentionally absent from the pin.
  A harness that turns a pinned skill into a *wide* fan-out changes which side of
  that line it belongs on.

## Layout convention

A workflow ships **bundled beside its `SKILL.md`**, never in `~/.claude/workflows`
alone:

```
<plugin>/skills/<skill-name>/
├── SKILL.md
└── workflows/
    └── <purpose>.workflow.js
```

A file in `~/.claude/workflows/` reads as *runnable*, and these templates are
deliberately incomplete — invoking one against empty `args` spends real worktree
agents (some capable of opening PRs) to discover it was a template. Register a
name in `~/.claude/workflows` **only** when another harness must call it by name
via `workflow('<name>', …)`.

**A bundled workflow must be reachable from a `## Workflow harness (template)`
section in its sibling `SKILL.md`.** An orphan `.js` is dead weight — nothing
tells a reader it exists, and nothing tells an adapter what may be rewritten.

## The framing snippet (copy verbatim)

Fill the three bracketed slots. Slot 3 is what makes it a template rather than a
script: naming what an adapter is *allowed to rewrite* implies everything else is
structure.

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

Two clauses every template that dispatches `isolation:'worktree'` agents must
**also** carry:

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a
> resume re-runs agents that already succeeded and opens duplicate PRs (#1868).
> Re-dispatch the failed units fresh and sequentially after checking
> `gh pr list --head <branch> --state all --json number,state`.

> Push, PR creation, and GitHub mutations happen **only** in the single sequential
> finalise stage, never inside a fanned-out agent.

## Landing discipline

- **Each template lands in the same commit as its `SKILL.md` framing section**
  (`docs-currency.md`). A `.js` with no framing is exactly the "script to run
  verbatim" the source guidance warns against.
- Shipped `.js` is `feat(<plugin>): …` (minor bump on the published plugin); the
  rule, the `CLAUDE.md` row, and any guard script are `chore` / `ci`.
- A harness that encodes a bug fix needs a script check like any other
  (`regression-testing.md`) — the template is not the guard.
- **Enforced by `scripts/check-workflow-js-model.sh --strict`** (+
  `scripts/tests/test-check-workflow-js-model.sh`), wired into
  `.pre-commit-config.yaml` and `plugin-pr-checks.yml`. It is the only gate that
  sees a bundled `.js` at all, and it asserts the mechanically checkable half of
  this rule: every `agent()` call pins an opus model (or inherits — never
  `sonnet`/`haiku`) and an explicit valid `effort`; the file is named
  `<purpose>.workflow.js`; it is reachable from a sibling
  `## Workflow harness (template)` section that names it; and a template
  dispatching `isolation:'worktree'` agents carries the two clauses above.
  The three gating axes stay a judgement call — no script can decide them.

## Related

- `.claude/rules/offload-to-deterministic-substrate.md` — the parent law this rule guards against being run backwards
- `.claude/rules/loop-integrity.md` — independent stop conditions and the state packet; why loop-until-done has no fit here
- `.claude/rules/structured-script-output.md` — the `STATUS=` / `KEY=VALUE` contract a script-enumerated N usually arrives in
- `.claude/rules/skill-fork-context.md` — the `context: fork` rule the compliance pin must agree with
- `.claude/rules/plugin-structure.md` — the `workflows/` directory in the plugin layout
- `.claude/rules/regression-testing.md` — a template encoding a bug fix still needs a script check
- `docs/plans/dynamic-workflow-migration.md` — the 47-skill evaluation this rule distils
- `agent-patterns-plugin:parallel-agent-dispatch` — the prose dispatch contract a harness makes enforceable
