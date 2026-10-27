---
name: adversarial-review
description: Adversarial second-pass review that tries to break code, designs, plans, or ADRs. Use when stakes are high and a normal review already ran.
args: "[target] [focus directive]"
argument-hint: "path|PR|file|plan description; optional 'focus on X'"
allowed-tools: Agent, Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(gh pr view *), TodoWrite
model: opus
created: 2026-06-21
modified: 2026-10-27
compatibility: claude-code
reviewed: 2026-09-02
---

# Adversarial Review

A normal review asks *"is this right?"* and confirms intent. Adversarial
review asks *"how could this be wrong?"* and hunts for the fault the first
pass rationalised away. It is a **second pass for residual risk on
high-stakes work** — not a replacement for the first pass, and not for
low-stakes or reversible changes where it only manufactures busywork.
**Red-teaming** is the same posture aimed at a proposal rather than a
finished change: actively try to break the proposed approach before you
commit to an architecture or design.

This is a **thin posture**, not a new checklist. It layers four moves —
isolation, inverted objective, a triage gate, and a bounded loop — on top of
the domain checklists that already live in `code-review`, `security-audit`,
`verify-before-plan`, and `cold-read-gate`. It dispatches an isolated
reviewer with the matching lens and then **triages** what comes back, because
an agent told to find faults will invent them.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| Stakes are high **and** a normal review already passed, but residual risk remains | First-pass review of a diff/PR → `code-quality-plugin:code-review` |
| Red-teaming an architecture decision, ADR, or migration plan before commit | Verifying plan *facts* (counts, paths, build state) → `agent-patterns-plugin:verify-before-plan` |
| Stress-testing a design's failure modes and invariants | Pure security audit → `agents-plugin` security-audit / `/security-review` |
| Probing whether outward text survives a reader → wrap `cold-read-gate` | Legibility of outward text on its own → `agent-patterns-plugin:cold-read-gate` |
| The change is hard to reverse and a missed fault is expensive | The change is low-stakes, reversible, or throwaway — skip; it wastes tokens |

## The Four Moves

| Move | What it means | Borrowed from |
|---|---|---|
| **Isolation** | The reviewer gets the artifact with no author context — bias can't leak in | `cold-read-gate` |
| **Inverted objective** | Brief says "enumerate failure modes," never "confirm it works" | this skill |
| **Triage gate** | Separate genuine faults from manufactured objections **before** acting | `cold-read-gate` Step 3 |
| **Bounded loop** | One revise round; a third means a structural problem the gate can't fix | `cold-read-gate` Step 4 |

> **Model choice is the inverse of cold-read-gate.** That skill uses *haiku
> on purpose* — the weak reader is the measurement instrument for legibility.
> Adversarial review wants **opus**: finding subtle faults is a reasoning
> task, not a low-context-reader simulation.

## Parameters

Parse `$ARGUMENTS`:

- **Target** (first positional) — what to attack: a path, a PR ref
  (`#123` or URL), a file, or a free-text description of a plan/decision.
  If absent, default to the current diff (`git diff` + staged) and say so.
- **Focus directive** (optional, free text after the target, e.g.
  `focus on the failure path, ignore style`) — biases the lens. It
  **steers, never overrides**: it must not cancel a live user boundary
  stated earlier in the session (the `auto-mode.md` conversation-boundary
  hazard).

## Execution

Execute this adversarial review:

### Step 1: Precondition gate

Confirm both hold before spending tokens:

1. **Stakes are high** — the change is hard to reverse, or a missed fault
   is expensive. If not, stop and recommend a normal review instead.
2. **A first pass exists** — a normal review/lint/test pass already ran.
   If not, run that first (`code-review`) — adversarial review is a
   *second* pass, and leading with it skips cheap, high-yield findings.

If either fails, say so and redirect rather than proceeding.

### Step 2: Name the target and pick the lens

State in one line what is under review, then select the lens. The lens
supplies the domain attack vocabulary — **delegate to the owning skill's
checklist rather than restating it**:

| Target type | Lens / attack vocabulary | Delegate the checklist to |
|---|---|---|
| Code, diff, PR | Logic errors, edge cases, race conditions, error-swallowing | `code-quality-plugin:code-review`, `code-review-checklist` |
| Security surface | Injection, authz gaps, secret exposure, trust boundaries | `agents-plugin` security-audit, `/security-review` |
| Architecture / ADR | Coupling, failure domains, blast radius, reversibility | blueprint `adr-validate`, `adr-relationships` |
| Plan / wave premise | Premise truth, stale facts, name≠behaviour | `agent-patterns-plugin:verify-before-plan` |
| Outward text / docs | Legibility under zero context | `agent-patterns-plugin:cold-read-gate` |
| Research claims | Unverified or single-sourced claims | `.claude/skills/deep-research` |

### Step 3: Dispatch the isolated reviewer

One `Agent` per lens on `model: opus` — adversarial review is judgement-tier
work (`.claude/rules/agent-development.md` § "Model Selection for Agents"), so
not a place for `sonnet` or `haiku` — and `model: fable` is sanctioned too: it
is exactly the hardest delegated reasoning, so the reviewer must not be weaker
than the author it is attacking.
Dispatch lenses in parallel only when there are several and the session is not
on a 1M-context model (every Fable 5.1 session, or Opus with the `[1m]`
suffix) — the parallel-subagent rate-limit caveat in `skill-fork-context.md`.
Template:

```
subagent_type: general-purpose
model: opus   # judgement tier; fable also sanctioned — see agent-development.md
prompt: |
  You are an adversarial reviewer. Your ONLY objective is to find ways this
  is WRONG, fragile, or unsafe — do not confirm that it works, do not
  praise it. Assume a fault exists and locate it.

  Read ONLY the target (no scope beyond it):
  <target path / diff / pasted plan>

  Attack along this lens: <lens from Step 2, with its checklist>.
  <focus directive, if any>

  Produce:
  1. FAULTS — each as: SEVERITY=critical|high|medium  EVIDENCE=<file:line or
     quoted claim>  FAILURE=<the concrete way it breaks>.
  2. ASSUMPTIONS-ATTACKED — load-bearing assumptions you tried to falsify,
     and whether each held.
  3. VERDICT: exactly one of `sound` | `flawed`.
  Cite evidence for every fault. Your final message is the deliverable.
```

### Step 4: Triage — genuine fault vs manufactured objection

The reviewer was told to find faults, so some "faults" are noise. Triage
**before** acting (this is the load-bearing step — skipping it is how
adversarial review sends you down the wrong path):

| Genuine fault — act on it | Manufactured objection — drop it |
|---|---|
| A concrete input/state that breaks the code, with evidence | A defense against an input the contract makes impossible |
| A failure mode with real blast radius | A hypothetical with no realistic trigger |
| A violated invariant or unhandled error path | Style/preference dressed up as a fault |
| A premise that is actually false | Re-litigating a trade-off already decided with rationale |
| A missing edge case the spec implies | Scope the change didn't touch and isn't responsible for |

### Step 5: Report and bound the loop

Emit a prioritised report: target, verdict, surviving genuine faults
(severity-ordered, with evidence and a suggested fix), and explicitly note
the objections you dropped in triage and why. Apply or hand off the genuine
fixes. Re-dispatch a fresh reviewer **only if the verdict was `flawed`**;
do not loop more than twice — a third round means a structural problem the
review can't resolve.

## Workflow harness (template)

`workflows/find-verify.workflow.js` (an existing change) and
`workflows/design-review.workflow.js` (a spec drafted from recon) ship beside this
skill. **Each is a TEMPLATE to adapt, not a script to run verbatim.** Read it, then
rewrite it for the work in front of you. Step 1's gate stays in prose here; no gate
agent goes inside a harness.

**Adapt freely:** lens prompts and their skills, `context`, `decided`, `measured`,
`verifyCap` (≤ 6), `controlSample` (≤ 2), the verifier run hint and isolation, the
spec sections. A find-verify lens may be an external model (`finder: { pal: '<model>' }`).

**Agent budget:** 3 + 1 x <verifiers or architect passes> — the counted 3 are the lens agents (`lenses.slice(0, 3)` in both files); find-verify adds one verifier per ranked finding up to `verifyCap` plus the control sample (≤ 11 in all), design-review adds the drafter and the reviser (5).

**Preserve across any adaptation:** a caller-chosen lens list of 2–3, never
truncated; the Rank barrier and refute-by-default verdict; nothing dropped past the
cap, behind a dead verifier, or folded into a duplicate; a resolution row per design
issue; read-only agents; a `status` that is never `clean` over a coverage gap. The
full list is in [REFERENCE.md](REFERENCE.md#workflow-harnesses-what-to-preserve).

Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a resume
re-runs agents that already succeeded and opens duplicate PRs (#1868). Re-dispatch the
failed units fresh and sequentially after checking
`gh pr list --head <branch> --state all --json number,state`.

Push, PR creation, and GitHub mutations happen **only** in the single sequential
finalise stage, never inside a fanned-out agent. These templates have no such stage.

**Skip the harness when:** there is one lens on one target — dispatch one reviewer
(Step 3) and triage inline. The Execution steps remain the authoritative description of
*what* each stage must produce; the harness only fixes *how* the work is split.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Running it as a first pass | It's a second pass — a normal review runs first (Step 1) |
| Using it on low-stakes / reversible work | Skip it; the precondition gate exists to say no |
| Acting on every objection the reviewer raises | Triage first (Step 4); the inverted objective guarantees noise |
| Using a weak model "to be tougher" | Opus — subtle faults are a reasoning task (inverse of cold-read-gate) |
| Restating each lens's checklist inline | Delegate to the owning skill; this is a posture, not a checklist |
| Looping until the reviewer goes silent | One revise round; persistent faults = structural problem |

## Related

- [REFERENCE.md](REFERENCE.md) — audit sweeps: find, verify adversarially, then resolve settled facts before editing; apply an undecided finding only where the facts make it policy-neutral, never "TBD" or a plausible owner
- [`cold-read-gate`](../cold-read-gate/SKILL.md) — the isolation + triage +
  bounded-loop pattern this skill generalises (legibility lens; uses haiku)
- [`verify-before-plan`](../verify-before-plan/SKILL.md) — adversarial review
  of *premises*; the plan/wave lens delegates here
- [`execution-grounded-review`](../execution-grounded-review/SKILL.md) — the
  sibling verifier for *running behaviour* against acceptance criteria (this
  skill attacks a design; that one grounds each criterion in execution evidence)
- `code-quality-plugin:code-review` — the first-pass review this layers on top of
- `agents-plugin` security-audit / `/security-review` — the security lens
- `.claude/rules/skill-fork-context.md` — the `[1m]` parallel-dispatch caveat
- `.claude/rules/loop-integrity.md` — looping skills delegate their stop-condition judgement to an isolated reviewer like this one (Pillar 1)
