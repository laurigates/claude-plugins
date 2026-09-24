---
name: debugging-methodology
description: Systematic debugging for memory, performance, and system-level issues. Use when diagnosing memory leaks, tracing syscalls with strace/eBPF, profiling, or reasoning about races.
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob
model: opus
created: 2025-12-27
modified: 2026-09-24
reviewed: 2026-04-25
---

# Debugging Methodology

Systematic approach to finding and fixing bugs.

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|------------------------|------------------------------------|
| Diagnosing a live bug, memory leak, race, or perf regression | Bug is hidden by a swallowed error → `code-hidden-failures --track errors` |
| Reasoning about reproduction, isolation, and root cause | Bug is hidden by silent success-on-empty → `code-hidden-failures --track degradation` |
| Choosing strace/eBPF/perf for system-level investigation | Reviewing surrounding code quality once root cause is known → `code-review` |
| Documenting hypotheses and binary-searching the failure | Refactoring the buggy module after the fix → `code-refactor` |

## Core Principles

1. **Occam's Razor** - Start with the simplest explanation
2. **Binary Search** - Isolate the problem area systematically
3. **Preserve Evidence** - Understand state before making changes
4. **Document Hypotheses** - Track what was tried and didn't work

## Debugging Workflow

```
1. Understand → What is expected vs actual behavior?
2. Reproduce → Can you trigger the bug reliably?
3. Locate → Where in the code does it happen?
4. Diagnose → Why does it happen? (root cause)
5. Fix → Minimal change to resolve
6. Verify → Confirm fix works, no regressions
```

## Common Bug Patterns

| Symptom | Likely Cause | Check First |
|---------|--------------|-------------|
| TypeError/null | Missing null check | Input validation |
| Off-by-one | Loop bounds, array index | Boundary conditions |
| Race condition | Async timing | Await/promise handling |
| Import error | Path/module resolution | File paths, exports |
| Type mismatch | Wrong type passed | Function signatures |
| Flaky test | Timing, shared state | Test isolation |

## Diagnose at the Failure Point — Sentinel Values and the Resource Reading

Promoted from `~/.claude/rules/diagnose-at-the-failure-point.md`, whose stub
keeps the two gate lines. When a tool or library reports a failure, two surface
features routinely misdirect the diagnosis: the **named entity** in the error,
and the **framing** you inherited going in. Both are cheap to check against
reality at the exact point of failure.

### 1. A named entity in an error may be a sentinel/default, not a real object

An error that names something by a **low / zero / default identifier** —
`Memory page 0 doesn't exist`, `id 0`, an empty-string name, `index -1`,
`0.0.0.0`, a null UUID — is often reporting an **uninitialized or sentinel
default**, not a real entity that misbehaved. **Before theorizing on the
entity, verify its identifier came from a real success** (a completed
allocation / lookup / registration), not a fallback path.

> Canonical break (2026-07, cubecl CUDA): `couldn't find resource for that
> handle: Memory page 0 doesn't exist` was read — by a handoff issue, the
> upstream tracker, and me for many iterations — as a memory-pool *reclaim
> race* corrupting "page 0". It was `MemoryLocation::uninit() = {pool:0,page:0}`:
> a **failed allocation** left its handle unbound at the zero default, and every
> downstream lookup of an unbound handle reported "page 0." **Zero** pool
> reclaims had fired. The tell was mechanical: the count of distinct "missing"
> handles equalled the count of allocation failures **exactly**.

The tell is usually a **count or ratio that matches something upstream**
(missing-entity count == failure count) — look for it before accepting the
entity as real.

### 2. For any exhaustion symptom, read the actual resource at the failure point

`OOM` / `out of memory` / `can't allocate` / `ENOSPC` / `too many open files` /
`pool exhausted` are **symptoms with three different fixes** — genuine
exhaustion, fragmentation, or a manager/allocator bug — and one measurement at
the failure point discriminates them:

| Symptom | Read at the failure point | Genuine exhaustion iff |
|---|---|---|
| CUDA/GPU OOM | `cuMemGetInfo` (free, total) | free ≪ requested |
| `ENOSPC` | `df` on the target fs | free ≈ 0 |
| `EMFILE` / too many files | fd count vs `ulimit -n` | count ≈ limit |
| allocator/pool "full" | pool `in_use` vs `reserved` vs device total | in_use ≈ device total |

Instrument the *failing call site* to print this; don't infer it from a sampler
taken seconds earlier (peak may be between samples). In the same case,
`cuMemGetInfo` at the failing `malloc` showed **0.58 GB free of 25.2 GB** —
genuinely full, not fragmented, not a pool bug. That one reading ended the
allocator hunt: the working set simply exceeded the card. Every competing theory
(reclaim race, cursor guard, sync-before-reclaim, a resolution "lever") had
already died to a measurement, not an argument.

**Evidence at the failure point > the framing you were handed > a plausible
mechanism.** A confidently-written issue, a maintainer's stated root cause, and
an error's own wording are all *inputs to verify*, not conclusions. When a
theory and a measurement disagree, the measurement wins — re-diagnose, don't
patch the theory. It bites when an error names an entity by a suspicious
round/zero/default value, when the fix for a "resource exhausted" failure
depends on *why*, and when an inherited handoff or upstream tracker already
asserts a root cause. Skipping the one cheap reading trades a five-second
`cuMemGetInfo`/`df`/count for a multi-iteration hunt down a mechanism that never
occurred. Siblings: `agent-patterns-plugin:probe-input-integrity` (an id *you*
invent), `git-plugin:git-issue-scoping` and `git-plugin:git-upstream-fix-check`
(don't trust the inherited framing), `agent-patterns-plugin:tool-result-traps`
(a well-formed output that silently doesn't match reality).

## Debugging Questions

When stuck, ask:
1. What changed recently that could cause this?
2. Does it happen in all environments or just one?
3. Is the bug in my code or a dependency?
4. What assumptions am I making that might be wrong?
5. Can I write a minimal reproduction?

## Effective Debugging Practices

- **Targeted changes**: Form a hypothesis, change one thing at a time
- **Use proper debuggers**: Step through code with breakpoints when possible
- **Find root causes**: Trace issues to their origin, fix the source
- **Reproduce first**: Create a minimal reproduction before attempting a fix
- **Verify the fix**: Confirm the fix resolves the issue and passes tests

For system-level tools (memory analysis, profiling, strace/eBPF tracing, network debugging) and language-specific debugger commands, see [REFERENCE.md](REFERENCE.md).
