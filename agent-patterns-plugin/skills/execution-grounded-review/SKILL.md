---
name: execution-grounded-review
description: "Execution-grounded review: run tests first, trace each acceptance criterion to execution evidence. Use when verifying an implementation meets spec."
args: "[target] [--criteria <file>]"
argument-hint: "diff|PR|files to verify; optional --criteria <file> of acceptance criteria"
allowed-tools: Agent, Read, Glob, Grep, Bash(git diff *), Bash(git log *), Bash(gh pr view *), Bash(npm *), Bash(npx *), Bash(uv run *), Bash(pytest *), Bash(cargo *), Bash(go test *), TodoWrite
model: opus
created: 2026-06-22
modified: 2026-06-22
reviewed: 2026-06-22
---

# Execution-Grounded Review

A normal review reads the diff and asks *"does this look right?"* — and an
implementation can *look* complete while a criterion silently fails. This skill
refuses to grade an implementation on appearance: it **runs the suite first**,
then traces each acceptance criterion to **execution evidence** — a test that
actually exercised it, or observed behaviour — and marks anything it cannot
back with execution as `UNVERIFIED` rather than passing it on faith.

It is the **execution-grounded verifier** in the agent-patterns review family:
where `adversarial-review` attacks a *design* for faults and `cold-read-gate`
measures whether *text* survives a reader, this skill verifies that *running
code* meets its *stated acceptance criteria*. It is the reusable independent
verifier a judgement-based loop gate delegates to (`.claude/rules/loop-integrity.md`, Pillar 1).

## When to Use This Skill

| Use this skill when... | Use something else instead when... |
|---|---|
| Verifying an implementation meets explicit acceptance criteria, proven by running it | First-pass review of a diff → `code-quality-plugin:code-review` |
| Gating a loop/phase `done` on an independent check of *behaviour* | Red-teaming a *design* or ADR for faults → `agent-patterns-plugin:adversarial-review` |
| Confirming a fix actually fixes the reported failure (not just compiles) | Checking *premises/facts* before work starts → `agent-patterns-plugin:verify-before-plan` |
| Closing the loop on "is every requirement actually covered by a test?" | Legibility of outward text → `agent-patterns-plugin:cold-read-gate` |

## The Stance

| Move | What it means |
|---|---|
| **Execute first** | Run the full suite + typecheck + lint *before* any verdict. A criterion is `PASS` only with execution evidence — never "the code looks like it does this". |
| **Trace each criterion** | One ledger row per acceptance criterion: premise → evidence (file:line / test name / observed output) → verdict. |
| **No silent pass** | A criterion with no execution backing is `UNVERIFIED` (a coverage gap to surface), not an assumed pass. |
| **Intent-starved verifier** | The isolated verifier reads the criteria, the diff, and the captured execution evidence — *not* the author's plan narrative or rationale, which would let it rationalise a pass. |
| **Bounded loop** | One revise round on `fail`; a third means a structural problem the gate can't resolve. |

> **Model is opus** — like `adversarial-review`, the inverse of `cold-read-gate`:
> building an accurate requirement→evidence ledger is a reasoning task.

## Parameters

Parse `$ARGUMENTS`:

- **Target** (first positional) — what to verify: a path, a PR ref (`#123` or
  URL), explicit files, or absent. If absent, default to the current change
  (`git diff HEAD` + staged) and say so.
- **`--criteria <file>`** (optional) — a file of acceptance criteria. If absent,
  gather criteria from the task/plan in context (the acceptance criteria stated
  for this change) and **echo them back** before verifying, so the user can
  correct the list the skill is grading against.

## Execution

Execute this execution-grounded verification:

### Step 1: Run the suite first

Before reading the diff for "correctness", establish ground truth by execution.
Detect and run the project's full suite + typecheck + lint, capturing output to
a scratch file (this is the **execution evidence** the verifier grades against):

| Stack | Suite | Typecheck | Lint |
|---|---|---|---|
| Node/TS | `npm test` (or `npx vitest run`) | `npx tsc --noEmit` | `npx biome check` |
| Python | `uv run pytest -q` | `uv run ty check` | `uv run ruff check` |
| Rust | `cargo test` | `cargo check` | `cargo clippy` |
| Go | `go test ./...` | `go vet ./...` | — |

Record the exit codes and failing-test names. A red suite is itself an
*independent* signal — a failing test does not care how hard the author worked
(`.claude/rules/loop-integrity.md`).

### Step 2: Name the criteria

State, in one numbered list, the acceptance criteria under verification (from
`--criteria` or context). If the list is empty, stop and ask for it — there is
nothing to ground a verdict in. Each criterion is one ledger row in Step 3.

### Step 3: Dispatch the intent-starved verifier

One `Agent`, `model: opus`, reading **only** the criteria, the diff, and the
captured execution-evidence file — not the author's reasoning. Template:

```
subagent_type: general-purpose
model: opus
prompt: |
  You verify whether an implementation meets its acceptance criteria, grounded
  in EXECUTION EVIDENCE. Read ONLY these inputs (no other files, no repo
  exploration beyond resolving evidence cited below):
    - Acceptance criteria: <numbered list from Step 2>
    - The change under review: <diff / file paths>
    - Execution evidence (suite/typecheck/lint output): <scratch file path>

  Do NOT read the author's plan, commit narrative, or rationale — grade the
  behaviour, not the intent.

  Build a ledger with ONE row per criterion:
    CRITERION=<n: the criterion text>
    EVIDENCE=<the test name / file:line / observed output that demonstrates it,
              drawn from the execution evidence — or "none">
    VERDICT=PASS|FAIL|PARTIAL|UNVERIFIED
      PASS        — execution evidence demonstrates the criterion holds
      FAIL        — execution evidence demonstrates it is violated (name the
                    concrete failing input/test)
      PARTIAL     — covered for some inputs, a stated edge case is unhandled
      UNVERIFIED  — no execution exercises this criterion (a COVERAGE GAP; do
                    NOT pass it on the basis that the code "looks right")

  Then:
    COVERAGE=<#criteria with PASS/FAIL evidence> / <total criteria>
    VERDICT: exactly one of `pass` | `fail`.
      `pass` requires every criterion PASS with execution evidence.
      Any FAIL, or any UNVERIFIED criterion, makes the overall verdict `fail`.
  Cite evidence for every row. Your final message is the deliverable.
```

For several independent targets, dispatch one verifier per target in a
single-message parallel `Agent` batch — except on a `[1m]` model, where the
concurrent-subagent rate-limit caveat applies (`skill-fork-context.md`); run
those sequentially. Do **not** set `context: fork` — the caller needs the ledger
in the main context to act on it.

### Step 4: Triage against over-correction

The verifier grades strictly, so guard **both** failure modes before acting —
neither talk yourself into passing broken code, nor into failing correct code:

| Act on it | Drop it |
|---|---|
| A `FAIL` with a named failing test/input | A `FAIL` on a requirement the spec never stated |
| An `UNVERIFIED` criterion → write/run the missing test, then re-grade | An `UNVERIFIED` on behaviour outside the change's responsibility |
| A `PARTIAL` where a *stated* edge case is unhandled | Style/preference dressed up as a criterion failure |
| A coverage gap on a load-bearing criterion | A hypothetical input the contract makes impossible |

### Step 5: Report and bound the loop

Emit the ledger: target, per-criterion rows with evidence, `COVERAGE`, and the
overall verdict. Apply or hand off the genuine fixes (closing `UNVERIFIED` rows
by adding the missing test counts as a fix). Re-run from Step 1 **only if the
verdict was `fail`**; do not loop more than twice — a third round means a
structural problem the gate can't resolve, which is the signal to surface to a
human, not to keep grinding.

## Anti-patterns

| Mistake | Correct approach |
|---|---|
| Grading the diff without running anything | Execute first (Step 1) — appearance is not evidence |
| Passing a criterion because the code "looks like it does that" | No execution evidence → `UNVERIFIED`, not pass |
| Feeding the verifier the author's plan/rationale | Intent-starved inputs — criteria + diff + execution evidence only |
| Inventing requirements the spec never stated | Triage (Step 4) — FAIL only on listed criteria |
| Looping until the verifier goes quiet | One revise round; persistent fail = structural problem |

## Agentic Optimizations

| Context | Command |
|---|---|
| Verify current change, no target given | `git diff HEAD` as the target; state the default |
| Verify a PR | `gh pr view <N> --json title,body,files` then diff |
| Capture execution evidence | `npm test -- --bail=1 2>&1 \| tee /tmp/evidence.txt` (or `uv run pytest -q`) |
| Single target, isolated verifier | One `Agent(subagent_type: general-purpose, model: opus)` |

## Related

- [`adversarial-review`](../adversarial-review/SKILL.md) — attacks a *design*
  for faults; this skill verifies *running behaviour* against criteria
- [`verify-before-plan`](../verify-before-plan/SKILL.md) — verifies *premises*
  before work; this verifies *outcomes* after
- [`cold-read-gate`](../cold-read-gate/SKILL.md) — the isolation + triage +
  bounded-loop pattern this skill reuses (legibility lens; uses haiku)
- `code-quality-plugin:code-review` — the first-pass review this layers on top of
- `workflow-orchestration-plugin:workflow-checkpoint-refactor` — a loop whose
  phase gate delegates its independent verdict here
- `.claude/rules/loop-integrity.md` — Pillar 1: a loop's stop condition is judged
  by an independent verifier like this one, not the worker
