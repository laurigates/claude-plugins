---
created: 2025-12-16
modified: 2026-09-03
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

### 1. An earlier check masks the one under test

```
run(mutate_frame_count, "check P: off-grid length")
  -> CAUGHT: "beat 'x' asks for 20 words in 5.42 s (3.69 words/s, ceiling 3.0)"
```

Reported as caught; the message is from **check N**, a words-per-second rule that
fires before the grid check ever runs. Check P was never exercised. The mutation
tripped a different assertion on the way past.

**Always print and read the failure message, never just the pass/fail.** If the
message does not name the check you are testing, the mutation did not reach it.

### 2. The mutation has to be one ONLY the target check can see

Fixing the above is not "mutate harder" — it is choosing a mutation that no
earlier check can intercept:

| Testing | Bad mutation | Works |
|---|---|---|
| an off-grid frame count | any beat (a talky one trips the words/sec check first) | a **wordless** beat |
| a cast-shrink rule | a beat whose prose also names the removed character (trips the alias check) | a beat where only the count changes |

This is the same discipline as isolating a variable in an A/B: the mutation is
the independent variable, and anything else it perturbs is a confound.

### 3. Mutating a table leaves import-time derived state stale

The subtlest one, and it caused two of the three maskings. Modules commonly build
lookup dicts from a table **at import**:

```python
SEGMENTS = (...)
_SEG_OF = {beat: name for name, beats, _ in SEGMENTS for beat in beats}
```

Monkeypatching `SEGMENTS` in the harness leaves `_SEG_OF` describing the *old*
table, so the first check that consults it fails with a stale-lookup error —
masking everything downstream:

```python
mod.SEGMENTS = new_table
mod._SEG_OF = {b: n for n, ids, _ in mod.SEGMENTS for b in ids}   # REQUIRED
```

**Rebuild every derived structure you can find, or reload the module.** Grep for
comprehensions over the table you mutated.

### 4. The mutated file was never imported

The mirror of the three above. Those are all **false CAUGHT** — a mutation
reported killed by an assertion other than the intended one. This one is
**false MISSED**: the harness edits a file the run never loads, and reports a
coverage hole that does not exist.

A 25-row harness over a builder + loader pair staged six named files into a temp
directory, wrote the mutated copy over one of them, and put the real source
directory on `PYTHONPATH` so the remaining imports would resolve. First run:
`25 mutations, 15 mismatches`. Twelve of the fifteen were every row mutating
*one* of the two files, each `expect=CAUGHT got=MISSED 0 red`. The natural
reading — "those twelve assertions are vacuous, go strengthen the tests" — is
wrong. They were running the pristine source.

**The tell is the control row.** A `META reject-all` mutation inserts a
hard-wired `err.add()` at the top of the function under test, and it reported
`MISSED` with `0 red`. A suite that does not go red against a hard-wired failure
is not a weak suite — it is proof the harness is not running the file it edited.

The mechanism was an ordinary, otherwise harmless idiom in a *sibling* module,
staged from the real directory:

```python
sys.path.insert(0, str(Path(__file__).resolve().parent))
```

`__file__` there is the **real** directory, so importing that sibling re-inserts
the real directory at `sys.path[0]`, ahead of the temp directory. The builder
imports the sibling before it imports the loader, so the loader — the mutated
file — resolved to the unmutated copy for every later import. Printing resolved
paths inside the run confirms it:

```
PATH0: ['/tmp/tmp.GcJ4RTwCg7', '/tmp/tmp.GcJ4RTwCg7', '/mnt/.../lab/scripts', ...]
B: /tmp/tmp.GcJ4RTwCg7/build_...py        <- staged copy, mutated rows worked
C-in-modules: /mnt/.../lab/scripts/dataputki_content.py   <- REAL file
```

The four rows mutating the *other* file worked correctly, because that file was
staged and imported directly. That mix is what made the report look plausible
rather than broken.

**Stage the whole directory and pass no search path at all.** With no second
copy anywhere on the path there is nothing for an import to bind to:

```python
shutil.copytree(SRC, td, dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"))
env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
```

After that change: 25 mutations, 0 mismatches, every row caught by its intended
test and the CONTROL correctly missed. A per-file copy list also encodes an
import graph that nothing checks — it stops being correct the moment someone
adds an import.

**This is not Python-specific.** Any runtime that resolves by search path has
the same shape — a second copy of the unmutated code reachable ahead of the one
you edited:

| Runtime | The second copy binds via |
|---|---|
| Python | `PYTHONPATH`, or a `sys.path.insert` inside any imported module |
| Node | `NODE_PATH`, or `node_modules` resolution walking up from the real file |
| Go | `GOPATH` |
| Ruby | `RUBYLIB` |
| Perl | `PERL5LIB` |
| A binary under test | `PATH` — a stub shadowed by a real command of the same name |

The `PATH` row is issue #2451 in this repo: the `bash-antipatterns` probe for
`sg` matched shadow-utils' `sg` instead of ast-grep.

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

- `vitest-testing` - Unit testing framework
- `python-testing` - Python pytest testing
- `test-quality-analysis` - Detecting test smells
- `api-testing` - HTTP API testing
- `agent-patterns-plugin:tool-result-traps` - Control-testing any negative that gates an action (§4's hard-wired `raise` is exactly that control)

## References

- Stryker: https://stryker-mutator.io/
- mutmut: https://github.com/boxed/mutmut
- Mutation Testing Intro: https://en.wikipedia.org/wiki/Mutation_testing
