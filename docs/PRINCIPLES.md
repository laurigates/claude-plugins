# Design Principles

The methodology behind these plugins. Every skill, agent, rule, and hook in this
repo is an attempt to make an agent's work **more reliable than the agent alone**
— by deciding, up front, what a probabilistic model should do versus what a
deterministic substrate should do, verify, and remember.

These principles are descriptive of current practice, not aspiration: each one
names the rules, skills, and hooks that already embody it. When they conflict
(they sometimes do — independence costs tokens, determinism costs flexibility),
the trade-off is made explicitly in the governing rule, not hand-waved here.

---

## 1. The agent decides; the substrate verifies and remembers

The agent is good at judgment — reading intent, weighing trade-offs,
synthesizing. It is bad at being repeatable, and its context window is scarce and
lossy. So anything mechanical, repeatable, and verifiable belongs *outside* the
reasoning loop: in a script, hook, or structured-output contract the agent
invokes and consumes. Spend context on judgment, not on re-deriving facts a
script would produce identically every run.

This splits into three claims worth keeping separate: **context economy** (don't
burn the window recomputing), **determinism** (reliable correctness must be
repeatable), and **independent enforcement** (a hook judges from outside, with no
stake in the outcome).

**Embodied by:** the global `offload-to-deterministic-substrate` rule and its
children — `structured-script-output` (compact `STATUS=`/`KEY=VALUE` rollups),
`drift-detection-triggering` (mount the existing sweep on a trigger; don't
rewrite the logic), `bash-tool-replacements` + the `bash-antipatterns` hook,
`tool-use-patterns` (one inline `python3`/`rg` pass over an agent fan-out).

## 2. One canonical home per fact — link, don't duplicate

A fact copied into a second place is a fact that will drift; the copy goes stale
the moment the original changes and nothing flags it. Documentation points to the
single source of truth instead of restating it. A runnable artifact (a skill, a
recipe, a script) *is* its own documentation — link to it rather than maintaining
a parallel prose copy by hand.

**Embodied by:** `documentation-authoring`, `docs-currency` →
`blueprint-docs-currency` (code and its docs land in the same commit), the
"reference the source, don't transcribe the list" convention across rules. This
doc itself follows the rule: the README links here rather than embedding a copy.

## 3. Judge from outside the work

An actor asked to both do the work *and* decide whether it's done is biased
toward "done" — it optimizes for completion, not correctness. So the judgment
that ends a loop, accepts a plan, or clears a review comes from a **fresh actor**
that did not do the work and reads only the acceptance criteria and the artifact.
Cheap mechanical gates (a green suite, `tsc` exit 0) are already independent; the
requirement bites when "done" is a judgment call.

**Embodied by:** `loop-integrity` (independent stop condition + state packet),
`agent-patterns-plugin:cold-read-gate` (a low-context reader is the measurement
instrument), `adversarial-review`, `execution-grounded-review`,
`verify-before-plan`.

## 4. Verify reality before acting

Act against the authoritative source, not a proxy for it. "The PR merged" is not
"all the branch's commits are in main." "The merge reported success" is not "the
result compiles." A WebFetch summary is not the issue thread. Check the ground
truth — `origin/main`, the IaC, the full comment thread, the upstream HEAD —
before patching, branching, or publishing.

**Embodied by:** `verify-upstream-before-patching`,
`read-issue-thread-before-contributing`, `concurrent-session-pr-check`,
`shared-checkout-branch-isolation`, `squash-merge-orphans-post-merge-commits`,
`textual-merge-duplicates-identical-additions`, `tool-migration-cutover` (verify
the replacement is *operational*, not merely configured).

## 5. Codify the fix; don't promise to remember

A bug fixed without a regression check is a bug that returns silently. Durable
correctness lives in a deterministic gate — a test, a script check, a hook — not
in an agent's or a person's memory. This is principle 1 applied to time: the
substrate remembers so the agent doesn't have to.

**Embodied by:** the `regression-testing` rule (a script check for every skill
bug fixed), the `scripts/check-*.sh` suite the repo runs in pre-commit and CI,
`local-ci-parity` (the local command and the CI step run the same checks).

## 6. Fail fast and loudly

Surface failures immediately and obviously, at the boundary, with clear context —
rather than continuing silently on bad state. A loud failure is cheap to
diagnose; a silent wrong result is expensive and erodes trust in every signal
around it. Dispatch skills carry an explicit loud-failure contract for exactly
this reason.

**Embodied by:** `code-quality` (fail fast / let it crash), the
loud-failure-contract check for dispatch skills, `parallel-safe-queries` (a
query that exits non-zero silently cancels its siblings — use the exit-0 variant
so failure is visible, not swallowed).

## 7. Frame positively

Define terms and rules by what they *are* and *when they apply*, not by negation.
Positive framing is what a model follows reliably; a wall of "don't" is not.
Commit subjects state the change in the imperative; the terminology glossary
gives each term a positive definition plus a *Use when* condition.

**Embodied by:** `terminology` (positive definitions with disambiguating *Use
when*), `conventional-commits` (imperative-mood subjects), the authoring guidance
across the skill-development rules.

---

## How these relate

Principles 1 and 5 are the same law across space and time: the deterministic
substrate does the work a lossy agent shouldn't be the system of record for —
computing it now (1), remembering it later (5). Principles 3 and 4 are both
"don't trust a stake-holding or proxy signal" — 3 about the worker judging
itself, 4 about a summary standing in for ground truth. Principle 2 is why this
document links rather than copies, and why the rules reference their sources
instead of transcribing them.

## Extending this document

When a pattern recurs across multiple rules and sessions, it has earned a place
here. Add it as a numbered principle with: a one-line law, a short *why* grounded
in how agents actually fail, and an **Embodied by** list naming the concrete
rules/skills/hooks — never a principle without artifacts. If you can't name what
embodies it, it isn't a principle yet.
