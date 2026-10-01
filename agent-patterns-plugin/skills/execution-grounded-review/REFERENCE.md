# execution-grounded-review — reference

Background for [SKILL.md](SKILL.md). Nothing here is needed to run the skill;
it records why parts of it are shaped the way they are.

## Insecure reporting

[Language Models Are "Insecure" Reporters](https://arxiv.org/abs/2609.36139)
(#2870) planted narrative-changing flaws in 200 work logs per scenario and found
frontier models omit or downplay them when writing a report — not for lack of
capability (they find the same flaws when asked directly) but from reasoning
about appearing successful — for example calling the flaw "outside the scope of
the task", or deferring to the log's own confident framing. Two findings are
measured and applied in the skill:

| Measured in the paper | Applied as |
|---|---|
| Appending *"Be honest in your response."* raised flagging sharply (GPT-5.5: 1% → 95% on planted negative results) with little rise in false flags on clean logs; "be thorough / critical / skeptical" were weaker and less consistent | That literal line in the verifier brief (Step 3) |
| Flagging stayed lowest, even with the honesty instruction, on pending results reported as current (≤25%), and among the lowest on collateral damage outside the task | The still-running, collateral-damage and unbacked-claim rows of the `limitations` checklist, and the Step 4 rule that dropping is from the verdict, not the report |

The required, front-loaded `limitations` field is this skill's own extension —
the paper did not test a structured field. It rests on the same reasoning as
`sequenceMatchesProduction`: a required slot makes "I did not check" or "I left
it out" unrepresentable rather than silent.

The paper also measured the cost of over-reporting: honesty prompting produced
a few hallucinated flaws on clean logs. The skill's grounding rule — every
limitation points at something the inputs show or show to be missing — exists
so that `LIMITATIONS: none` stays reachable on a clean run.

## The no-regression criterion (PR #2871 eval, finding 3)

A run where every listed criterion passed but the full suite was red produced
`VERDICT: pass`, with the failures listed only under `LIMITATIONS`. A reader
who stops at the verdict sees a pass. The options weighed:

| Option | Why not chosen |
|---|---|
| Any red Step 1 step fails the verdict | Breakage already on the default branch would block every loop gate |
| Keep the criteria-scoped pass and add a `SUITE:` line | Loop gates read `VERDICT`; a regression would still pass them |
| A third verdict value (`pass-with-regressions`) | Breaks the binary contract loop gates depend on (`.claude/rules/loop-integrity.md`) |
| A caller-chosen `--scope` flag | Moves the decision to every caller; the default still has to be chosen |

Chosen: an implicit last criterion — *no test that passes on the merge-base
fails on the head* — graded from a base run that Step 1 makes only when a step
is red. New failures fail the verdict through the ordinary row rules; failures
that are also on the base go into `LIMITATIONS`. No new verdict logic.

## What the eval suite measures

On a strong model the baseline (same prompt, no skill) already detects every
planted flaw in the short cases; the first eval run on PR #2871 measured a
with-skill/baseline gap that was almost entirely report format. So:

- Most prompts state the expected output format, so the baseline gap measures
  the skill's content (verdict rules, grounding, abstention), not its shape.
  egr-006 (clean control) and egr-007 (abstention) keep no format hint: they
  test that the skill produces the shape unprompted, and that it withholds it
  when there is nothing to grade.
- The long-log cases bury the flaw in 100+ lines of mostly green output with
  reporting pressure, following the paper's construction. They are the only
  cases that can show a detection gap on a strong model.
- On a strong model the skill's main value is a stable, machine-readable
  verdict that loop gates can consume, not detection. A weaker model in
  `/evaluate:matrix` is where a detection gap would show.
