---
created: 2026-07-12
modified: 2026-07-12
reviewed: 2026-07-12
allowed-tools: Task, Read, Glob, Grep, Bash(git log *), Bash(git diff *), Bash(rg *), TodoWrite
args: "[path|crate] [--models <a,b>]"
argument-hint: "[path or crate to review] [--models glm-5.2,gemini-2.5-pro]"
description: "Evaluate whether a test suite actually tests what it aims to, using an adversarial pass plus a tests-hidden cold read, then verify every finding against the code. Use when a suite is green but you doubt it would catch a real regression."
name: test-strategy-review
---

# Test Strategy Review

A green suite is not evidence that the tests test what you're aiming for. It is
evidence that the tests you wrote pass. The gap between those two is where the
expensive bugs live — and it is invisible from inside the suite, because the
suite's author and the suite share the same blind spots.

This skill attacks that gap from **two directions at once**, then makes both
directions earn their findings:

| Pass | What it sees | What it asks |
|---|---|---|
| **Adversarial** | source **+ tests** | "Where does a plausible mutant survive green?" |
| **Cold read** | source **only — tests hidden** | "What coverage would you *demand* here?" |
| **Verify** | the actual code | "Is each finding real, or did the model invent it?" |

The **cold read is the move with no other home**, and the reason this skill
exists. Everything else composes skills you already have.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| A suite is green but you doubt it would catch a real regression | You need to *write* tests → `testing-plugin:test-setup` / language test skills |
| Stakes are high: ML numerics, serialization, concurrency, config→behavior wiring | You want a mutation *tool* run → `testing-plugin:mutation-testing` |
| Before trusting a suite as the gate for a risky migration | You want test-smell/flake heuristics → `testing-plugin:test-quality-analysis` |
| A suite grew organically and nobody has audited what it *doesn't* cover | Adversarially reviewing code/a design (not a suite) → `agent-patterns-plugin:adversarial-review` |
| | The suite is small, low-stakes, or throwaway — this manufactures busywork |

## The Three Passes

### 1. Adversarial — hunt the surviving mutant

Reuse the posture from `agent-patterns-plugin:adversarial-review` (inverted
objective + triage gate); this skill only supplies the **test-suite lens**. Give
the reviewer source **and** tests, and make it hunt concretely:

1. **Mutation survivors** — a plausible one-line change to production code that
   *all* tests still pass. Name the mutant and the surviving green.
2. **Goldens that pin arithmetic, not semantics** — a reference test can lock an
   exact numeric sequence and still miss a semantically flipped-but-symmetric
   change (a sign flip on a symmetric objective trains "just as well").
3. **Self-referential assertions** — a test comparing the code against *its own
   output* (`f(x) == f(x)`, a hash pinned to what the hash currently returns)
   proves determinism, never correctness. Demand an *independent* truth.
4. **Loose tolerances** wide enough to hide a real error.
5. **Coverage holes** — error arms, `?` propagation, the render/front-end seam,
   config-precedence edges, I/O paths that every test disables via a large
   cadence value (`checkpoint_every: 10_000` over 10 steps never fires).
6. **Invariants pinned only by convention** — the project's central rule stated
   in a doc comment with no test or lint enforcing it.

Require, per finding: `file:function` → the surviving bug → severity → **the
specific test that would kill it**.

### 2. Cold read — derive the coverage, tests hidden

This is the novel pass. Give a reviewer the **source and nothing else** — no
tests, and an explicit instruction not to guess at them — and ask it to design
the suite it would *demand* before trusting this code. Then **diff its list
against what actually exists**. The delta is your hole list, produced by someone
who could not be anchored by the tests you already wrote.

- Ask for: the invariant (with `file:function`), the failure mode if it silently
  broke, a badness×likelihood rank, and **what independent truth** the assertion
  compares against.
- Push for exhaustiveness — over-listing is cheap here; the diff filters it.
- This is *not* `agent-patterns-plugin:cold-read-gate`, which cold-reads
  **outward prose** for legibility. Same instinct (a reader with no context sees
  what you can't), different object: here the cold reader reads **code** and
  emits **required coverage**.

A large fraction of what comes back will already be covered — that is the point.
It tells you the suite is strong *there*, and the residue is what it is blind to.

### 3. Verify — every finding, against the code, before you act

**Adversarial reviewers invent findings.** A model told to find faults will
produce confident, specific, wrong ones. Never open an issue or write a test off
a raw finding.

- Check each claim against the actual source. Split the output into
  **CONFIRMED** (you read the code and it holds) and **PLAUSIBLE** (not yet
  verified) — and say which is which.
- Refuting a finding often reduces to **one checkable fact about a library**.
  Read the dependency's source, not its API surface.
- A refuted finding is still worth a **regression guard** if the suite lacked a
  test for that property at all.

> **Worked example (the pass that pays for the skill).** A reviewer flagged a
> "missed-wakeup hang" in an SSE subscriber: *"`tokio::watch` is level-triggered
> and the notified `()` value never changes, so the wake is lost."* Reading
> tokio's source refuted it in two greps: `send_replace` bumps a **monotonic
> version** (the unchanging `()` is irrelevant), and `changed()`
> registers-then-checks (no lost-wake window). The bug was not real. But the
> suite had no burst test, so the outcome was still a regression guard —
> and *not* a day spent "fixing" a non-bug.

## Model Diversity Matters

Run the passes across **genuinely different models** (e.g. via
`pal`/`clink` to external providers), not N copies of the session model.
Same-model reviewers share blind spots — that is exactly what you are trying to
escape. Two models × two passes (adversarial, cold read) is a good default; give
each pass to both models and take the union, then verify.

Expect model output to be **lossy about its own certainty**: one model's "high
severity race condition" was a false positive; another's throwaway note about an
optimizer's default was a real, shipping bug.

## What It Finds (evidence)

Run against a Rust ML trainer with an unusually *good* suite (PyTorch-golden
numerics, stage-by-stage parity, byte-pinned wire schema), it still surfaced:

- **2 real shipping bugs** — two documented config knobs (`weight_decay`,
  `dropout`) were declared, deserialized, and **silently ignored**. Every test
  set them to their default (`0.0`), which makes the correct and the broken
  wiring behave *identically*. This is the archetype: **a default value that
  hides the bug from every test that uses it.**
- **9 confirmed coverage holes** — including an I/O path no test ever triggered,
  a config-precedence contract with zero tests, an argmax never asserted, a hash
  pinned only to itself, and a central architectural invariant enforced by doc
  comment alone.
- **1 refuted false positive** — the concurrency "hang" above.

## Output Contract

A single ranked table, most-dangerous-first, with CONFIRMED and PLAUSIBLE kept
apart:

| # | Hole | Surviving mutant | Sev | Killing test |
|---|---|---|---|---|

Then a prioritized plan: real bugs first (they ship), then unverified-but-scary,
then the holes — each as its own tracked issue so the batch doesn't rot.

## Related

- `agent-patterns-plugin:adversarial-review` — the adversarial posture + triage
  gate this skill's pass 1 borrows. Use it directly for code/designs/plans.
- `agent-patterns-plugin:cold-read-gate` — cold reading **outward prose** for
  legibility (a sibling instinct, a different object).
- `testing-plugin:mutation-testing` — when you want a mutation *tool* to prove
  the survivor mechanically, rather than a reviewer to reason about it.
- `testing-plugin:test-quality-analysis` — smells, overmocking, flake heuristics.
- `testing-plugin:test-consult` — strategy questions ("how should I test X?").
