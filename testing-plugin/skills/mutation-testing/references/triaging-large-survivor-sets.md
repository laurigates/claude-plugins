# Mutation Testing — Triaging a Large Survivor Set

Detail for [SKILL.md](../SKILL.md). Use it when a scan returns more survivors than anyone can read one by one, which is normal on a first scan. One source run: ~640 source files across 8 Stryker scans gave ~4,900 `Survived` and ~3,800 `NoCoverage` mutants.

**The survivor count is not the finding.** Most survivors in one area share a handful of causes, and one missing assertion can leave dozens of mutants alive. Triage by the *behaviour* left unasserted, then verify the high-stakes claims, then let a Stryker re-run decide whether the new tests worked.

| Stage | Who | Output | Gate |
|---|---|---|---|
| 1. Triage by unasserted behaviour | One read-only agent per cluster of 3–10 files | One finding per behaviour, classified | — |
| 2. Adversarial verification | One skeptic agent per claimed source bug | Held / refuted / downgraded | A reproduction, or the claim is refuted |
| 3. Test writing | Writer agents, with reviewers re-running a sample | New tests | A final Stryker run over the same mutant set |

## Stage 1 — Triage by unasserted behaviour

Split each scan's files into clusters of 3–10 related files and give each cluster to one **read-only** agent. Each agent reads three things:

1. The surviving mutants for its files, straight from the JSON report:

   ```bash
   jq --arg f "src/orders/service.ts" \
     '.files[$f].mutants[] | select(.status=="Survived" or .status=="NoCoverage")
      | {id, mutatorName, replacement, status, line: .location.start.line}' \
     reports/mutation/mutation.json
   ```

2. The source file.
3. The tests that cover it (`coveredBy` / `killedBy` in the report name them).

It reports **one finding per behaviour left unasserted, not one per mutant**, and puts each finding in one class:

| Class | Meaning | Action |
|---|---|---|
| Test gap | The code is right; no test asserts this behaviour | Stage 3 writes the test |
| Source bug | The mutant survives because the code is already wrong, or the mutation is indistinguishable from intended behaviour that is itself a bug | Stage 2 verifies it first |
| Untested function | A whole function (usually `NoCoverage`) has no test reaching it | Stage 3, or decide it is dead |
| Dead code | Unreachable or unused code | Delete it rather than test it |

### Dismiss these as noise

| Noise | Why it survives | Why it is not a finding |
|---|---|---|
| `select` / projection booleans under a mocked ORM | The mock returns a fixed object whatever columns were selected | Only an integration test against a real database can see it |
| Log and message strings | No test asserts log text | Asserting log text makes tests brittle for no behavioural gain |
| Equivalent mutants | The mutation does not change observable behaviour (`i < n` vs `i != n` on a loop that only steps by one) | No test can kill it |

**Check `NoCoverage` against the integration suites first.** Code a unit run marks as uncovered is often exercised by integration or end-to-end suites that skip in that run (missing database, missing service, an env-gated `describe.skip`). Record it as covered-elsewhere, not as an untested function.

### The first thing to look for: mocked-ORM payloads

In a codebase that mocks its database client, this was the most common finding by a wide margin. The test stubs the client, calls the code, and asserts the **mock's return value**, never what the code **passed in**:

```ts
// Weak: passes whatever `where` or `data` the code builds
db.order.update.mockResolvedValue(order);
expect(await markShipped(id)).toEqual(order);

// Strong: asserts the payload the code sent to the client
expect(db.order.update).toHaveBeenCalledWith({
  where: { id, status: "PAID" },
  data: { status: "SHIPPED", shippedAt: expect.any(Date) },
});
```

Every mutant in the `where` filter or the `data` payload survives the weak form. It is usually one finding per call site, covering many mutants.

## Stage 2 — Adversarial verification of every claimed source bug

A triage agent claiming "source bug" is making a claim about production behaviour, and false positives cost more here than anywhere else. Give **each** claim to its own skeptic agent that did not do the triage, with the brief:

- Refute the claim. Default to **refuted** unless you can produce a concrete reproduction: an input, the observed output and the expected output.
- Scratch runs are allowed: a throwaway test, a script, a REPL session. Do not edit the source or the real test files.
- Return one of *held*, *refuted* or *downgraded* (real but lower impact, or a test gap rather than a bug), with the reproduction.

In the source run 31 claims went through this stage: 30 held, 1 was refuted, several were downgraded, and one headline example was corrected. The correction matters as much as the refutation, because a wrong headline example is the one everyone repeats.

For the skeptic pattern itself — isolation, the refute-by-default brief, when the stakes justify the cost — use `agent-patterns-plugin:adversarial-review`.

## Stage 3 — Stryker re-run as the gate for test writers

Writer agents turn the held findings into tests. A writer's report that the tests "kill the mutants" is a claim, not evidence, so:

1. **Writers prove each kill by hand.** For every targeted mutant, apply the mutation to the source, show the new test failing with a message that names the behaviour, then revert. This is the hand-rolled harness discipline; the ways it misreports are in [hand-rolled-harness-failures.md](hand-rolled-harness-failures.md).
2. **Reviewers re-run a sample** of those hand mutations rather than reading the writer's table.
3. **A final Stryker run over the same mutant set** is the gate. Scope it to the targeted files (`npx stryker run --mutate "<files>"`) so the score compares like with like. In the source run the targeted files went from 67.7% to 88.2%.

The final run catches what hand proofs miss: a test that kills the hand-applied mutation but not Stryker's actual replacement, and mutants that a writer's change to shared fixtures quietly resurrected.
