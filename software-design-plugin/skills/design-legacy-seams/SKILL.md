---
name: design-legacy-seams
description: Get legacy code under test before changing it — find seams, write characterization tests. Use when changing untested code, breaking dependencies, or taming legacy.
args: "[target]"
argument-hint: "file|class|function|diff to bring under test; omit for current change"
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git log *), TodoWrite
created: 2026-06-23
modified: 2026-06-23
reviewed: 2026-06-23
---

# Design: Legacy Code Seams

From *Working Effectively with Legacy Code* (Feathers): **legacy code is code
without tests.** The dilemma is circular — to change it safely you need tests,
but to test it you often need to change it. The way out is to find a **seam** (a
place where behaviour can be altered without editing in-line) to break the
dependency that makes the code untestable, then pin the *current* behaviour with
**characterization tests** before you touch logic.

The sequence is non-negotiable: **get it under test first, change it second.**
Characterization tests document what the code *does* (not what it *should* do),
so a refactor that preserves behaviour stays green and a behaviour change shows
up as a deliberate, reviewed diff.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| About to modify untested code and want a safety net first | The code already has good tests → `code-quality-plugin:code-review` |
| A dependency (DB, clock, network, global) blocks unit testing | Judging *test* quality of existing tests → `code-quality-plugin:code-test-quality` |
| Pinning current behaviour before a risky refactor | A large multi-phase refactor → `workflow-orchestration-plugin:workflow-checkpoint-refactor` |
| Breaking a hidden dependency to inject a fake | Diagnosing a live bug → `code-quality-plugin:debugging-methodology` |

## Core Principle

| Seam type | Where you alter behaviour | Typical use |
|---|---|---|
| **Object seam** | Override a method / inject a collaborator | Replace a real dependency with a fake (most common) |
| **Link seam** | Swap a library/module at build/link time | Stub a third-party at the boundary |
| **Preprocessing seam** | Macro/build substitution before compile | Last resort in C/C++-style builds |

Two enabling moves when no seam exists yet: **Extract & Override** (pull the
hard-to-test work into a method, subclass in the test to override it) and
**Parameterize Constructor/Method** (pass the dependency in instead of
constructing it inside). Both are tiny, behaviour-preserving, and create the
seam the test needs.

## Parameters

Parse `$ARGUMENTS`:

- **Target** (optional, first positional) — a file, class, function, or diff to
  bring under test. If absent, default to the current change (`git diff HEAD` +
  staged) and say so.

## Execution

Execute this get-under-test workflow:

### Step 1: Find the change point and its dependencies

Locate where the behaviour change is needed. List the dependencies that make it
hard to test now — constructed-inside collaborators, global/singleton state,
clocks, randomness, I/O, network, static calls.

### Step 2: Find or create a seam

For each blocking dependency, identify the cheapest seam:

- An existing **object seam** (already-injectable collaborator, overridable method)
- **Parameterize Constructor/Method** — pass the dependency in
- **Extract & Override** — move the hard call into an overridable method
- A **link seam** when you genuinely can't touch the callee

Make only the smallest behaviour-preserving edit needed to open the seam. Note
that the seam you introduce is often an **Adapter** (see
`software-design-plugin:design-patterns`).

### Step 3: Write characterization tests

Pin the **current** behaviour, not the intended behaviour:

1. Write a test that calls the code and asserts whatever it *currently* returns.
2. Run it; if it fails, **change the assertion to match actual output** (you are
   documenting reality, not judging it).
3. Add cases until the branches you're about to touch are covered. A surprising
   characterized behaviour is a *finding* — flag it, don't silently "fix" it yet.

### Step 4: Now change, then report

With the net in place, make the intended change; the characterization tests that
*should* still hold stay green, and the ones that intentionally change become a
reviewed diff. Report: the change point, the seam(s) opened (type + the minimal
edit), the characterization tests added, and any surprising current behaviour the
characterization surfaced.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Refactoring untested code "carefully" by hand | Get it under test first — careful is not a safety net |
| Writing tests for what the code *should* do | Characterize what it *does*; behaviour change comes after |
| A giant rewrite to make one method testable | Smallest seam-opening edit (Extract & Override / Parameterize) |
| "Fixing" a surprising behaviour mid-characterization | Flag it; change behaviour as a separate, deliberate step |

## Quick Reference

| Blocker | Seam move |
|---|---|
| Collaborator constructed inside | Parameterize Constructor |
| Hard call buried in a method | Extract & Override |
| Global / singleton / clock | Inject via an object seam |
| Untouchable third-party | Link seam / Adapter at the boundary |
| Need to pin behaviour | Characterization test asserting current output |

## Related

- `code-quality-plugin:code-test-quality` — once under test, judge whether those
  tests are *good* (this skill only gets them *present*)
- `software-design-plugin:design-patterns` — the seam you open is often an
  Adapter; Extract & Override leans on subclassing
- `workflow-orchestration-plugin:workflow-checkpoint-refactor` — the multi-phase
  refactor this safety net unblocks
- `code-quality-plugin:debugging-methodology` — a characterization test is also a
  reproduction harness for a legacy bug
