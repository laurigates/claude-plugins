---
name: design-pseudocode
description: Design a routine by stepwise refinement — pseudocode the intent before coding, then promote it to comments. Use when designing a complex function or non-trivial algorithm.
args: "[target or description]"
argument-hint: "a routine to design (free text), or a stub file|diff; omit for current change"
allowed-tools: Read, Grep, Glob, Bash(git diff *), TodoWrite
created: 2026-06-23
modified: 2026-06-23
reviewed: 2026-06-23
---

# Design by Pseudocode

From *Code Complete* (McConnell), the Pseudocode Programming Process: before
writing a non-trivial routine, design it in **pseudocode** — intent-level English
statements, one per step — refining top-down until each line is obvious to
translate into code. You catch the hard cases, the wrong decomposition, and the
missing error path *while editing prose*, which is an order of magnitude cheaper
than catching them while editing code. The finished pseudocode then becomes the
routine's comments, so the design survives as documentation.

This is a *pre-implementation* design technique: it decides a routine's internal
structure, names its steps, and surfaces its edge cases before a single line of
real code is committed.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| Designing a complex routine or non-trivial algorithm before coding | Verifying whole-project *premises* before a wave → `agent-patterns-plugin:verify-before-plan` |
| The decomposition isn't obvious and you want to fail cheap in prose | Choosing a structural design pattern → `software-design-plugin:design-patterns` |
| Naming steps + edge cases up front, then keeping them as comments | A multi-file refactor plan → `workflow-orchestration-plugin:workflow-checkpoint-refactor` |
| Reviewing whether a stub's intended logic is sound before it's built | Reviewing already-written code → `code-quality-plugin:code-review` |

## Core Principle

| Step | What you do | What it buys |
|---|---|---|
| **1. Intent** | State the routine's contract: inputs, output, one-line job | A clear target before mechanism |
| **2. Refine** | Decompose into intent-level steps; refine each until trivial | The decomposition is judged in prose |
| **3. Check edges** | Walk error paths, empty/boundary inputs, failure modes | Missing cases found before code |
| **4. Promote** | Each pseudocode line becomes a comment; fill code beneath | Design survives as documentation |

Pseudocode is **intent, not syntax**: "find the first overdue invoice" — not
`for (i=0; i<n; i++)`. If a line is already code-shaped, it's too low; if you
can't translate a line directly to a few statements, it's too high — refine it.

## Parameters

Parse `$ARGUMENTS`:

- **Target or description** (optional) — a free-text description of the routine to
  design, **or** a stub file/diff whose intended logic to work out. If absent,
  default to the current change (`git diff HEAD`) and design the routine it
  stubs.

## Execution

Execute this pseudocode design pass:

### Step 1: State the contract

One line each: what the routine takes, what it returns/guarantees, and its single
job. If it has more than one job, that's a decomposition signal — design the
pieces separately (pairs well with `software-design-plugin:design-by-contract`).

### Step 2: Refine top-down

Write the routine as a short list of **intent-level** steps. Refine any step that
isn't obvious-to-code into sub-steps. Stop when every line maps to a few
statements. Resist writing real syntax — the value is judging the *shape* before
committing to it.

### Step 3: Walk the edges

Against the pseudocode, walk: empty/null/boundary inputs, the failure of each
external call, and the postcondition under each path. Add the handling as
pseudocode lines. A case you can't place is a sign the decomposition is wrong —
revise the steps, not just patch the end.

### Step 4: Promote to comments and report

Emit the refined pseudocode as the routine's comment skeleton (each line a
comment, code to be filled beneath). Report: the contract, the step
decomposition, the edge cases surfaced, and any decomposition smell (a step doing
two jobs, a missing error path) found during refinement.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Writing real code and calling it pseudocode | Intent-level English; if it's syntax, raise the altitude |
| Pseudocode so vague a step hides a whole algorithm | If a line won't translate to a few statements, refine it |
| Skipping the edge-case walk | Step 3 is where pseudocode pays for itself |
| Throwing the pseudocode away after coding | Promote it to comments — the design becomes the docs |

## Quick Reference

| Altitude check | Verdict |
|---|---|
| Line reads as `for/if/while (...)` | Too low — that's code |
| Line maps to 1-5 statements of intent | Just right |
| Line hides a whole sub-algorithm | Too high — refine it |
| A step does two distinct jobs | Decompose into separate routines |

## Related

- `software-design-plugin:design-by-contract` — Step 1's contract is the
  precondition/postcondition pair, made explicit
- `software-design-plugin:design-patterns` — when refinement reveals recurring
  variation, a pattern may be the right step structure
- `code-quality-plugin:code-review` — reviews the code *after*; this designs it
  *before*
- `agent-patterns-plugin:verify-before-plan` — the project-scale sibling:
  verify premises before a multi-agent plan, as this refines a routine before code
