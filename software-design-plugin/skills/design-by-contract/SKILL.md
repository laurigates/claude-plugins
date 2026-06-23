---
name: design-by-contract
description: Design with explicit contracts — preconditions, postconditions, invariants, guard clauses. Use when designing a function/class, hardening a boundary, or adding assertions.
args: "[target]"
argument-hint: "function|class|module|diff to give contracts; omit for current change"
allowed-tools: Read, Grep, Glob, Bash(git diff *), Bash(git log *), TodoWrite
created: 2026-06-23
modified: 2026-06-23
reviewed: 2026-06-23
---

# Design by Contract

From *Code Complete* (McConnell) and Meyer's contract model: a routine's
correctness is a **contract** between caller and callee — the caller guarantees
the **preconditions**, the callee guarantees the **postconditions**, and the
object preserves its **invariants** across every public operation. Making that
contract explicit (guard clauses, assertions, documented expectations) is a
*proactive design* technique: it decides *where* each error is caught and *whose*
responsibility each check is, before the bug exists.

This is the design-time complement to `code-quality-plugin:code-hidden-failures`,
which *detects* error-swallowing after the fact. Here the goal is to place the
checks so failures are loud, attributable, and caught at the right layer.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| Designing a function/class and deciding what it may assume vs must check | Finding existing swallowed errors → `code-quality-plugin:code-hidden-failures` |
| Hardening a trust boundary (public API, parser, deserialization) | A full correctness/security pass → `code-quality-plugin:code-review` |
| Deciding where a validation belongs (caller vs callee) | Diagnosing a specific live bug → `code-quality-plugin:debugging-methodology` |
| Adding assertions/invariants to make assumptions executable | Writing the tests that exercise them → `testing-plugin` |

## Core Principle

| Contract element | Question it answers | Failure if omitted |
|---|---|---|
| **Precondition** | What must hold *before* the routine runs? | Garbage-in produces silent garbage-out |
| **Postcondition** | What does the routine guarantee *after*? | Callers re-check or assume wrongly |
| **Invariant** | What stays true across every public method? | Object drifts into an impossible state |
| **Guard clause** | Reject the invalid case early, at the top | Deep nesting; the happy path is buried |

**Errors vs assertions** — the load-bearing distinction. Validate **external,
expected** input (user, network, file, untrusted caller) with real error
handling at the **boundary**; assert **internal, impossible** conditions (a
violated invariant, a precondition another part of *your* code must have
guaranteed) to fail fast in development. Do not validate what an assertion
should catch, and never let an assertion guard external input.

## Parameters

Parse `$ARGUMENTS`:

- **Target** (optional, first positional) — a function, class, module, or diff
  to give contracts. If absent, default to the current change (`git diff HEAD` +
  staged) and say so.

## Execution

Execute this contract design pass:

### Step 1: Classify each input boundary

For the target, list every input and classify it **external/expected** (validate
with error handling) or **internal/impossible** (assert). State which layer owns
each check — push validation **outward** to the trust boundary so the core can
assume clean data.

### Step 2: State the contract

For each public routine, write its precondition(s), postcondition(s), and — for a
class — the invariant the constructor establishes and every method preserves.
Make them concrete and checkable ("`amount > 0` and `currency` is ISO-4217"),
not vague ("valid input").

### Step 3: Place the checks

- **Guard clauses** at the top: reject invalid/edge cases early, return or throw,
  keep the happy path flat and un-nested.
- **Boundary validation**: real errors with actionable messages for external bad
  input — never an assertion, never a swallowed exception.
- **Assertions**: internal impossibilities and preserved invariants, so a logic
  bug fails loudly in dev instead of corrupting state.

### Step 4: Report

Emit per routine: the contract (pre/post/invariant), each check's placement and
kind (validate vs assert), and any input currently checked at the wrong layer or
not at all. Flag every spot where an *external* input is only assert-guarded
(a production hole) or an *internal* impossibility is handled as a recoverable
error (noise that hides real bugs).

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Asserting on user/network input | Assertions are for impossible states; validate external input with errors |
| Re-validating clean data in every inner layer | Validate once at the boundary; inner code assumes the contract |
| Vague preconditions ("valid input") | Concrete, checkable conditions |
| Deep `if` nesting for edge cases | Guard clauses at the top, flat happy path |
| Catching an exception you can't act on | Let it propagate; a swallowed invariant violation hides the bug |

## Quick Reference

| Input kind | Mechanism | Where |
|---|---|---|
| External / expected | Error handling + actionable message | Trust boundary |
| Internal / impossible | Assertion | Where the invariant must hold |
| Invalid early-exit case | Guard clause | Top of the routine |
| Class consistency | Invariant established in ctor, preserved per method | Every public method |

## Related

- `code-quality-plugin:code-hidden-failures` — *detects* swallowed errors; this
  skill *places* checks so failures stay loud (design-time complement)
- `code-quality-plugin:code-review` — broader correctness/security review
- `code-quality-plugin:debugging-methodology` — when a contract was violated and
  you're tracing how
- `software-design-plugin:design-deep-modules` — a deep module's contract is part
  of its small, honest interface
