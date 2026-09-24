# Parallel Agent Dispatch — A Verifier That Shares State With the Thing It Verifies Is Not Independent

Promoted from the always-loaded `parallel-verifier-reads-shared-state.md`
portfolio rule, whose stub keeps the gate lines. Entry point:
[`../SKILL.md`](../SKILL.md); index: [`../REFERENCE.md`](../REFERENCE.md).

Adversarial verification only works if the verifier's picture of reality is its
own. Two ways a parallel workflow quietly breaks that, both observed in one
session, both producing confident and well-argued wrong output.

## 1. A judge reading the working tree sees the builder's branch, not `main`

Give a workflow a build phase and a verify phase in the same clone and the
builder will, quite reasonably, leave the checkout on its branch. Every later
agent that answers *"what does this file currently say?"* by reading the working
tree is then reading the builder's uncommitted or branch-local change and
reporting it as the pre-existing state.

> Example: an implementation agent added `retries: 0` to a cron job's Helm
> values on its branch. Two of three judges, running afterward in the same
> checkout, opened their reports with *"One correction to the shared premise,
> because it changes what the fix has to close: `retries: 0` is ALREADY set …
> (deploy/values.yaml:<line>)"* — complete with a line number.
> `git show origin/main:deploy/values.yaml` had no such key. The agent that
> wrote it was the reason it was there.

What makes this worse than an ordinary wrong answer is that the false premise
arrived **welded to a true finding**. The same paragraph correctly identified
`backoffLimit: 2` as a live re-invocation vector — a real defect, worth a commit.
Rejecting the premise and the finding together would have discarded it; accepting
both would have published a fabricated history. The two had to be separated by
hand.

- **The verifier must establish base state from the ref, never the checkout**:
  `git show origin/main:<path>`, `git diff origin/main...<branch>` (three dots —
  two dots reports unrelated drift once `main` moves).
- **Say so in the brief.** A verifier cannot infer that a peer is active. Write:
  *"the working tree may hold a concurrent agent's branch or uncommitted
  changes; establish current state from `origin/<base>`, not from the files on
  disk."*
- **Worktree-isolating the builder is not sufficient** — it stops builders
  colliding with each other, and it is what you want anyway, but the judge still
  reads whatever the shared checkout happens to be on. Both halves are needed.
- **Treat any "X is already true" claim from a shared checkout as unverified**,
  especially one that arrives as a *correction to the premise*. That framing is
  persuasive precisely because it sounds like the agent checked.

## 1b. A verifier that *writes* the tree is worse than one that merely reads it

Section 1 is the read side: a judge answers "what does this file say?" from a
checkout a peer has moved. The write side is the same law with the roles
reversed, and it is harder to catch because the corrupted party is the
**measuring** stage, not the reporting one.

Mutation testing is the usual source. A reviewer proving a test has teeth must
mutate the subject, run the suite, and restore — three writes to shared files,
on a loop. Run that concurrently with a quality gate over the same checkout and
the gate is sampling a tree that is mid-mutation. Its failures are real
observations of a state that never existed as a commit.

> Example: a workflow put a mutation-testing adversarial reviewer and a
> `test:coverage` gate in the same parallel stage. Three of the gate's runs went
> red. Each received value was the **verbatim pre-fix behaviour of code that was
> correct on disk**: an empty-body test rendering `Cannot read properties of
> null (reading 'role')`; a lockfile fixture returning the old implementation's
> Set-collapsed signature; and `<package> resolved to 2 lockfile entries` while
> the lockfile held one and was byte-identical to HEAD. Reported at face value,
> that is two fabricated regressions filed against working code — and each reads
> as *more* credible than a real finding, because the symptom it produces is
> exactly the bug the fix removed.

**The discriminator is that the failure reproduces the pre-fix bug too well.**
A genuine regression in new work rarely lands precisely on the old symptom. When
a "regression" is bit-for-bit the thing you just fixed, suspect the tree before
the diff.

- **Do not schedule a mutating verifier concurrently with a measuring one.**
  Sequence them: mutate-and-restore first, gate afterwards. In a `Workflow`
  script that means separate phases with a barrier, not two thunks in one
  `parallel()` call.
- **Guard the measurement.** Hash every relevant file before and after the run
  (the lockfile included) and discard the result if they differ. Control-test
  the hash so an empty-input digest cannot pass as a match.
- **Check for peers before believing a red.** A test-runner process you did not
  start, source mtimes falling inside your run, or several files sharing one
  bulk-restore mtime are all tells. Leftover snapshot files under `/tmp` are the
  loudest.
- **Restore from a `cp` snapshot, never `git checkout --`** — see section 2,
  which covers why that deletes an uncommitted fix. The write-side hazard makes
  it worse: a peer gate may sample the tree during the window when the fix is
  gone.

The cheap structural fix is to give the mutating agent its own worktree. It
costs one command, and it is the only arrangement where the two stages can
safely overlap at all.

## 2. "I ran the gates and they passed" is a claim, not evidence

Across one session, **three separate build agents** reported gates that did not
reproduce: a consumer-diff sweep that missed the one consumer the change
affected; a grep that matched `response.json()` but not `res.json()` and so
declared a directory clean that held eight live defects; and a published
teeth-check command (`git checkout HEAD -- …`) that is a no-op at the commit it
was published against, so a reader following it verbatim sees every test pass and
concludes they pin nothing.

None was dishonest. Each is the ordinary failure of checking your own work.

- **Have the verifier re-run every gate the builder reported**, and record what
  does not reproduce as a first-class output, ranked *above* the defects — a
  green gate that was never green invalidates more than any single finding.
- **Mutation-test the claim that a test has teeth**: revert the fix or stub the
  guard, confirm the test goes red, restore. A test that stays green pins nothing,
  and this is the only cheap way to know.
- **Restore from a snapshot, not with `git checkout --`, while the fix is
  uncommitted.** `git checkout -- <file>` restores from **HEAD**, so on
  uncommitted work it does not undo your mutation — it deletes the fix along with
  it. Every mutation after the first then runs against a tree containing no fix
  at all, goes red for that reason, and reads exactly like a test with teeth.
  Snapshot once and restore from the copy:

  ```sh
  cp main/thing.c "$SNAP"          # once, with the fix in place
  # mutate, run the suite, then between mutations:
  cp "$SNAP" main/thing.c
  ```

  Observed 2026-09 (`mcu-tinkering-lab`): a three-mutation run over an uncommitted
  guard reported all three red. Only the first was a real result; the other two
  measured the fix's absence. Re-running against a snapshot separated them.

  The tell is free if you look for it — under this bug **every** mutation fails,
  including any you expected to survive, so a clean sweep is itself suspicious.
  Committing the fix before mutating works equally well and is often simpler.
- **Control-test every negative that gates a conclusion.** The `res.json()` miss
  is the canonical shape: an empty grep result reads identically to a clean tree.
  Run the same pattern against a term you know is present first.

## When it bites

- Any `Workflow` with a build stage and a verify stage over the same repo.
- Long sessions where a peer session is active in the same clone — the peer moves
  `HEAD` with no signal to you at all.
- Judge panels specifically: they are prompted to be adversarial, which makes a
  confident wrong premise read as rigour rather than as an error.

Portfolio incident evidence is kept privately (repos-claude-config docs/rule-evidence/parallel-verifier-reads-shared-state.md).

## Related

- `git-plugin:git-coworker-check` REFERENCE.md § Shared-checkout branch isolation — the *write* side: whose branch your commit
  lands on. This file is the *read* side: whose branch your verifier reports on.
- [`worktree-hazards.md`](worktree-hazards.md) — the isolation the builder half needs.
- `agent-patterns-plugin:tool-result-traps` — control-test any negative that
  gates an action.
- `agent-patterns-plugin:probe-input-integrity` — same family: an
  extracted-vs-retyped subject, and a harness that is green while measuring the
  wrong thing.
- `agent-patterns-plugin:adversarial-review` — the judge posture these briefs serve.
