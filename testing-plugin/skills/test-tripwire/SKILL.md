---
name: test-tripwire
description: "Tripwire test for an unenforced code assumption. Use when deferring a fix until a list, limit or version changes — a failing test instead of an issue."
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(git diff *), Bash(git log *), TodoWrite
created: 2026-10-06
modified: 2026-10-06
reviewed: 2026-10-06
---

# Tripwire Tests

A tripwire test asserts an **assumption the code relies on but does not
enforce**. It passes today and checks no behaviour. It fails only when a later
change breaks the assumption, and it fails in the PR that makes that change.

The usual reason to write one is a deferred fix. An issue says "if the list ever
grows past ten, add a count beside it", and the condition is a fact about the
code. Filed as an issue, it sits open for months and nobody connects it to the
commit that finally triggers it. Written as a test, it fails in front of the one
person who needs to read it.

Related names: *fitness function* (Ford, Parsons and Kua, *Building Evolutionary
Architectures*), *executable TODO*, and `static_assert` for the compile-time
form.

## When to Use This Skill

| Use a tripwire test when... | Use something else when... |
|---|---|
| A deferred fix waits on a condition visible in the source: a list length, a constant, an enum's members, a pinned dependency version | The trigger is a date or an outside event (vendor deprecation, contract end) → an issue or a dated reminder |
| Code truncates, caps or indexes by a size it assumes, and nothing checks the assumption | The trigger is runtime data (row counts, traffic) → a runtime assertion or monitoring alert |
| Two lists or constants must stay in a relation (disjoint, equal, one within the other) and live in different files | The assumption is enforceable at the boundary → a guard clause (`software-design-plugin:design-by-contract`) |
| Grooming finds an open issue whose trigger is a code condition | You want to know whether existing tests catch regressions → `testing-plugin:test-strategy-review` / `testing-plugin:mutation-testing` |

## Writing One

1. **Assert the assumption, not the behaviour.** Compare the two facts directly:
   `expect(CODES.length).toBeLessThanOrEqual(LIST_LIMIT)`. Driving the code
   path is unnecessary; the assumption is the subject.
2. **Import the real values.** Export the constant if it is private. A copied
   literal in the test drifts silently and the tripwire stops tracking anything.
3. **Name the reason in the test name**, with the issue or PR that deferred the
   fix: `"fits within LIST_LIMIT, since the committees list has no dropped count (#123)"`.
   The failure message is the only documentation the next person is sure to see.
4. **List every resolution in a comment**, and state what each does to the
   test. Be exact: "raise the limit" makes it pass; "add a dropped count" does
   not, so that path says to retire the test. A comment claiming a fix makes the
   test pass when it does not sends the reader in a circle.
5. **Place it beside the tests of the code that relies on the assumption**, not
   in a catch-all file, so the reader lands with context.

```ts
describe("COMMITTEE_CODES", () => {
  it("fits within LIST_LIMIT, since the run row's committee list has no dropped count (#123)", () => {
    // The run row caps the per-committee list at LIST_LIMIT with no count
    // beside it, unlike errors/errorsTotal. Past the limit it would drop
    // entries silently. Either raise the limit, or add a total beside the
    // list and retire this test.
    expect(COMMITTEE_CODES.length).toBeLessThanOrEqual(LIST_LIMIT)
  })
})
```

Other shapes the same pattern takes:

| Assumption | Assertion |
|---|---|
| Retired codes must never return to the active list | every retired code is absent from the active list |
| A copy kept in another runtime (a migration image, a script) must match the source | the two lists are equal |
| An enum handled by a `switch` has exactly N members | the member count, with the `switch` named in the comment |
| A workaround is needed only below version X | the installed version is below X; the comment says to delete the workaround |

## Verify It Can Fail

A tripwire that cannot fail is an issue nobody reads in a different place. Break
the assumption on purpose and watch the test go red:

1. Snapshot the file: `cp src/limits.ts tmp/limits.ts.bak`.
2. Mutate the value so the assumption no longer holds (lower the limit below the
   list length, add a retired code to the active list).
3. Run only the tripwire. Confirm it fails **on the assertion**, with a message
   that names both values (`expected 5 to be less than or equal to 4`), not on
   an import or type error.
4. Restore from the snapshot (`cp tmp/limits.ts.bak src/limits.ts`), not with
   `git checkout --`, which also discards uncommitted work in that file. Re-run
   it green.

Report the control with the test: the mutation, the failure line, and the
restored value.

## Closing the Issue

When a tripwire replaces a deferred item, close or narrow the issue in the same
PR. Its condition now lives in CI, so the issue only adds a second copy that
can drift. Link the test from the closing comment or the PR body.

## Agentic Optimizations

| Context | Command |
|---|---|
| Run only the tripwire (Vitest) | `bunx vitest run <file> -t "<test name fragment>"` |
| Run only the tripwire (pytest) | `pytest <file> -k "<name fragment>" -q` |
| Find where the assumed size is used | `rg -n '\.slice\(0, LIST_LIMIT\)\|LIST_LIMIT' src` |
| Check the issue thread before replacing it | `gh issue view <n> --json title,body,comments` |
