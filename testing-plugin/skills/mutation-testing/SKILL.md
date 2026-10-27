---
created: 2025-12-16
modified: 2026-10-27
reviewed: 2025-12-16
name: mutation-testing
description: "Mutation testing with Stryker (TS/JS) and mutmut (Python). Use when finding weak tests that pass on mutated code, or improving test quality through mutation analysis."
user-invocable: false
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, TodoWrite
---

# Mutation Testing

Expert knowledge for mutation testing - validating that your tests actually catch bugs by introducing deliberate code mutations.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Validating test effectiveness | Writing unit tests (use vitest-testing) |
| Finding weak/insufficient tests | Analyzing test smells (use test-quality-analysis) |
| Setting up Stryker or mutmut | Writing E2E tests (use playwright-testing) |
| Improving mutation score | Generating test data (use property-based-testing) |
| Checking if tests catch real bugs | Setting up code coverage only |

## Core Expertise

**Mutation Testing Concept**
- **Mutants**: Small code changes (mutations) introduced automatically
- **Killed**: Test fails with mutation (good - test caught the bug)
- **Survived**: Test passes with mutation (bad - weak test)
- **Coverage**: Tests execute mutated code but don't catch it
- **Score**: Percentage of mutants killed (aim for 80%+)

**What Mutation Testing Reveals**
- Tests that don't actually verify behavior
- Missing assertions or edge cases
- Overly permissive assertions
- Dead code or unnecessary logic
- Areas needing stronger tests

## TypeScript/JavaScript (Stryker)

### Installation

```bash
# Using Bun
bun add -d @stryker-mutator/core

# For Vitest
bun add -d @stryker-mutator/vitest-runner

# For Jest
bun add -d @stryker-mutator/jest-runner
```

### Running Stryker

```bash
npx stryker run                                    # Run mutation testing
npx stryker run --incremental                      # Only changed files
npx stryker run --mutate "src/utils/**/*.ts"       # Specific files
npx stryker run --reporters html,clear-text        # HTML report
open reports/mutation/html/index.html              # View report
```

### Understanding Results

```
Mutation score: 82.5%
- Killed: 66 (tests caught the mutation)
- Survived: 14 (tests passed despite mutation - weak tests!)
- No Coverage: 0 (mutated code not executed)
- Timeout: 0 (tests took too long)
```

### Example: Weak vs Strong Test

```typescript
// Source code
function calculateDiscount(price: number, percentage: number): number {
  return price - (price * percentage / 100)
}

// WEAK: Test passes even if we mutate the calculation
test('applies discount', () => {
  const result = calculateDiscount(100, 10)
  expect(result).toBeDefined() // Too weak!
})

// STRONG: Test catches mutation
test('applies discount correctly', () => {
  expect(calculateDiscount(100, 10)).toBe(90)
  expect(calculateDiscount(100, 20)).toBe(80)
  expect(calculateDiscount(50, 10)).toBe(45)
})
```

### Static survivors under the Vitest runner are often false

A **static** mutant mutates code that runs at module load (constant maps, Zod
schemas). Observed with `@stryker-mutator/vitest-runner` 10.0.0 on Vitest 4.1:

| `ignoreStatic: true` | Effect |
|----------------------|--------|
| Skips | Static mutants that **no** test covers |
| Does not skip | Static mutants some test covers — these run only against the 1-2 tests Stryker attributes coverage to, often unrelated files that imported the module first |

So a static mutant can report Survived although the test that really asserts on
that code would kill it. One Next.js app: 384 of 766 survivors were `static: true`
with `testsCompleted` <= 5; excluding them moved the score from 68% to ~79%. A
static survivor that ran against **many** tests is real (dropping `.trim()` from
a Zod schema survived 195 tests, and stayed green across all 96 related tests
when applied by hand). Count the survivors worth reading:

```bash
jq '[.files[].mutants[] | select(.status=="Survived" and ((.static|not) or .testsCompleted > 5))] | length' reports/mutation/mutation.json
```

The threshold `5` is a heuristic from that one codebase, not a Stryker-defined
value. Tie-breaker for a suspicious static survivor: apply the mutation by hand
and run the related tests — a red suite means the survivor was false.

## Python (mutmut)

### Installation

```bash
uv add --dev mutmut                    # Using uv
pip install mutmut                     # Using pip
```

### Running mutmut

```bash
uv run mutmut run                                          # Run mutation testing
uv run mutmut run --paths-to-mutate=src/calculator.py      # Specific files
uv run mutmut results                                      # Show results
uv run mutmut summary                                      # Summary
uv run mutmut show 1                                       # Show specific mutant
uv run mutmut apply 1                                      # Apply mutant manually
uv run mutmut html                                         # HTML report
```

### Understanding Results

```
Status: 45/50 mutants killed (90%)
- Killed: 45 (tests caught the mutation)
- Survived: 5 (tests passed despite mutation)
```

## Hand-rolled harnesses report LESS than Stryker and mutmut do

Everything above assumes a framework. Plenty of real mutation testing is a
hand-rolled loop instead — apply a mutation, run one assertion, catch the
failure — typically because the thing under test is a **build-time check in a
generator or builder** rather than a unit test suite.

That loop is worth writing. But it drops the one piece of bookkeeping the
frameworks give you for free: **Stryker and mutmut tell you *which test* killed
each mutant.** A hand-rolled harness usually reports only *that something*
failed, and "something failed" is indistinguishable from "the check I am testing
failed". Four ways that goes wrong — the first three observed in one session,
the fourth in another:

Before trusting a hand-rolled harness's table, open [references/hand-rolled-harness-failures.md](references/hand-rolled-harness-failures.md): §1 an earlier check masks the one under test, §2 choosing a mutation only the target check can see, §3 import-time derived state left stale after mutating a table, §4 the mutated file was never imported (false MISSED, with the per-runtime search-path table).

### The consequence for a green table

A harness that prints CAUGHT for every mutation is often quoted as proof the
suite is sound. It proves something weaker:

> An all-CAUGHT table proves each **mutation** was caught by **some** assertion.
> It never proves the assertion you meant was the one that caught it — nor that
> any individual assertion is capable of failing.

Two cheap additions close most of the gap:

- **A deliberate no-op mutation** the harness *should* miss. A table where
  everything is CAUGHT is indistinguishable from a broken harness; one expected
  MISS tells them apart. The symmetry holds and the control does not cover it:
  an **all**-MISSED table is equally indistinguishable from a broken harness,
  and a no-op reporting MISSED as designed looks identical beside real mutations
  reporting MISSED because nothing loaded them. **Read the META/accept-all row
  first** — a hard-wired `raise` or accept-all that fails to turn the suite red
  is not a weak assertion, it is proof the harness is not running the file it
  edited (§4).
- **Assert on the message, not just the exception.** Match the mutation to an
  expected substring of the failure, so a masked result is a harness failure
  rather than a silent pass.

## Workflow harness (template)

`workflows/survivor-triage.workflow.js` ships beside this skill. **It is a TEMPLATE to adapt,
not a script to run verbatim.** Read it, then rewrite it for the work in front of you. It runs
Stages 1 and 2 of [references/triaging-large-survivor-sets.md](references/triaging-large-survivor-sets.md).

**Adapt freely:** the agent prompts, `project`, the severity rubric and noise list,
`staticMinTests` (default 5, per § "Static survivors under the Vitest runner are often false"), `integrationGlob`,
`verifyKinds`, and the `MAX_CLUSTERS` / `VERIFY_MAX` caps.

**Agent budget:** 14 — up to 8 read-only triage agents (one per caller cluster) and up to 6 skeptics (`verifyCap`, default 4, clamped to 6).

**Preserve across any adaptation:** (a) the loop bound is the caller's `clusters`, cut by
`CLUSTERS.slice(0, 8)` after an explicit over-cap abort, and the skeptics by a literal
`slice(0, 6)`, never a prose "for each"; (b) the closed `kind` and `held | downgraded | refuted`
enums, with a `held` that lacks a reproduction recorded as refuted and a dead skeptic returned
unverified, never held; (c) the Rank barrier: every cluster's claims are sorted by severity
before any skeptic starts, so the cap goes to the worst claims in the scan, not to the cluster
that finished first; (d) whatever the cap or a dead skeptic leaves comes back in `unverified`
in the claim shape, so `{ worktree, project, claims: <unverified> }` re-runs the same template
as verify-only. `scripts/tests/test-survivor-triage.sh` pins (b)–(d).

**Skip the harness when:** the scan is one cluster, or few enough survivors to read in one
pass — that is a linear pass and the harness is pure overhead. The reference's stages remain
the authoritative description of *what* each stage must produce; the harness only fixes *how*
the work is split.

## Mutation Score Targets

| Score | Quality | Action |
|-------|---------|--------|
| 90%+ | Excellent | Maintain quality |
| 80-89% | Good | Small improvements |
| 70-79% | Acceptable | Focus on weak areas |
| 60-69% | Needs work | Add missing tests |
| < 60% | Poor | Major test improvements needed |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick TS mutation | `npx stryker run --incremental --reporters clear-text` |
| Targeted TS mutation | `npx stryker run --mutate "src/core/**/*.ts"` |
| Quick Python mutation | `uv run mutmut run --paths-to-mutate=src/core/` |
| View survived | `uv run mutmut results \| grep Survived` |
| CI mode | `npx stryker run --reporters json` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## See Also

- [references/triaging-large-survivor-sets.md](references/triaging-large-survivor-sets.md) - Triaging thousands of survivors: cluster by unasserted behaviour, verify claimed source bugs adversarially, gate test writers on a Stryker re-run
- `vitest-testing` - Unit testing framework
- `python-testing` - Python pytest testing
- `test-quality-analysis` - Detecting test smells
- `api-testing` - HTTP API testing
- `agent-patterns-plugin:tool-result-traps` - Control-testing any negative that gates an action (§4's hard-wired `raise` is exactly that control)

## References

- Stryker: https://stryker-mutator.io/
- mutmut: https://github.com/boxed/mutmut
- Mutation Testing Intro: https://en.wikipedia.org/wiki/Mutation_testing
