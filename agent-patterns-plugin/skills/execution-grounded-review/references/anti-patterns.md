# Execution-Grounded Review — Anti-patterns

Moved verbatim from [SKILL.md](../SKILL.md). Open when reviewing a verification run,
or before acting on a ledger.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Grading the diff without running anything | Execute first (Step 1) — appearance is not evidence |
| Passing a criterion because the code "looks like it does that" | No execution evidence → `UNVERIFIED`, not pass |
| Passing a round-trip/determinism claim because "a test exists and passes" | Confirm the test's operation sequence matches the production call path (Step 3a) |
| Reading a long trace end to end and naming the latest plausible cause | Locate with `grep -n`, read narrow windows, report the span — within the attribution bound (Step 3b) |
| Reporting the verdict first and caveats after — or not at all | `LIMITATIONS` block before `VERDICT`, `none` stated explicitly (Step 5) |
| Feeding the verifier the author's plan/rationale | Intent-starved inputs — criteria + diff + execution evidence only |
| Inventing requirements the spec never stated | Triage (Step 4) — FAIL only on listed criteria |
| Omitting collateral damage because it is "out of scope" | Drop it from the verdict, list it in `LIMITATIONS` (Step 4) |
| Looping until the verifier goes quiet | One revise round; persistent fail = structural problem |
