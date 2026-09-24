# AI Review — Runaway Loops: a `synchronize`-Triggered Review Has No Round Counter

Promoted from the always-loaded `ai-review-loop-has-no-brake.md` portfolio rule,
whose stub keeps the gate lines. [SKILL.md](SKILL.md) covers what a **red**
AI-review check means; this file covers the **green** ones that keep arriving.

A PR-review workflow that fires on `pull_request: synchronize` re-arms itself on
every push. An LLM reviewer re-run cold on a changed diff will find *something*.
An agent told to "address the review" pushes a fix. That is a closed loop, and
nothing in GitHub Actions counts the trips around it: `concurrency` supersedes an
in-flight run, it does not budget the series. The loop ends when a human decides
to stop pushing — **the only brake is a human**.

> Example (2026-09-07, one PR in a private repo): 25 commits, **24 review
> rounds**, over seven hours open-to-merge. Three Claude-powered checks — a code
> review, a "Security - Secret Scanning" check and a code-smell check — fired on
> every push, 25 runs each. 13 of the 24 post-initial commits touched no runtime
> code and no test. Rounds 14–21 were eight consecutive rounds correcting a
> source comment that enumerates which CLI flags are bounds-checked,
> culminating in a paragraph headed `NO COUNTS BELOW` that contained a wrong
> count. The authoring session's own 24 rounds are spend nothing measures.

## Three facts that break the obvious diagnoses

**1. `github.actor` is blind to an agent-authored branch.** A reusable review
workflow gating on `github.actor != 'github-actions[bot]'` fired on every run of
that PR, because the `triggering_actor` was the human's account — a cloud
session pushing under the human's credentials — while every commit was authored
`Claude <noreply@anthropic.com>`. Any control keyed on the actor is a no-op
against this class. The commit's own author trailer is the only reliable signal,
and it is a *condition to branch on*, never a skip: see fact 3.

**2. Converting the PR to draft does not stop it.** None of the five workflow
files on that PR referenced `github.event.pull_request.draft`. It is the
intuitive move and it is inert. The kill switches that work are in the table
below.

**3. Defect density did not decay with round count.** Two of the findings were
real user-visible bugs in the shipped code path — a positive offset wrongly
rescaled, and a test tolerance that could not distinguish the right answer from
one grid step low. They landed at **rounds 22 and 24**, after sixteen
near-worthless rounds, because no arm of the 41-test suite had ever exercised
that path. Replayed against the real timeline, a cap of 5 rounds trips exactly
when rounds 1–5's genuine arithmetic fixes are exhausted, and a modest
cumulative-cost ceiling trips between rounds 6 and 7 — each saving most of the
spend and losing both real bugs.

So the round count was never the signal. **Nobody was watching, and nothing could
stop it.** Fix the watching and the stopping; do not reach first for a cap.

## Kill switches, once a loop is recognised mid-flight

| Move | Stops | Blast radius |
|---|---|---|
| Stop pushing | everything | none — and this is what actually ended the loop above |
| `gh run cancel <id>` | one in-flight run | none; the next push re-arms it |
| `gh workflow disable <file> -R <o>/<r>` | the whole class, immediately | **every other open PR in that repo**, and it stays off silently — a disabled workflow produces no runs and no red X, so open a re-enable issue in the same action |
| `gh pr close <n>` | `synchronize` on that PR | reopening re-fires `reopened` |
| Convert to draft | **nothing** | no `.draft` reference exists in the workflows |

## Where the cost number actually lives

Not in a step output. `anthropics/claude-code-action`'s only documented output is
`structured_output`; `total_cost_usd` and `num_turns` appear in the **run log**,
as part of the SDK's final JSON. Reading them means parsing logs:

```
gh run view <id> -R <o>/<r> --log | grep -oE '"(num_turns|total_cost_usd)": ?[^,]*'
```

Anything that claims to surface per-run cost from `steps.<id>.outputs.total_cost_usd`
is reading a field that does not exist, and will report empty rather than fail.

Per-round cost also **compounds**: on the PR above it roughly doubled from the
first round to the last while `num_turns` stayed flat at 19–31.
`track_progress: true` feeds the whole PR comment thread back into each review,
so round N pays for rounds 1..N−1's prose. Bounding that context is a cost lever
orthogonal to capping rounds, and `claude_args`' default
`--model opus --max-turns 50` is the per-run ceiling nobody tunes.

## When it bites

- Any repo whose `claude-review.yml` (or sibling Claude-powered caller) fires on
  `synchronize` — the default shape for these workflows.
- Hardest where the authoring session is **unattended**: on the PR above the
  reply latency from the human's account to each review was 10–90 seconds for
  four continuous hours, several at 0.00 minutes. No wall-clock gap is
  consistent with anyone reading a review.
- Repos with several Claude-powered callers, where one push buys three LLM runs.
  Read which they are from the caller files — `Security - Secret Scanning` is
  LLM-backed despite the name.

Portfolio incident evidence is kept privately (repos-claude-config docs/rule-evidence/ai-review-loop-has-no-brake.md).

## Related

- [SKILL.md](SKILL.md) — what a red AI-review check means
- `github-actions-plugin:actions-billing-usage` — measure the cost before
  optimizing it. Actions *minutes* are not the cost here; the OAuth-token spend
  is, and the billing API does not see it
- `github-actions-plugin:claude-code-github-workflows` REFERENCE.md — why a
  "no code change" commit message is not a skip signal CI may parse (agent-emitted
  markers)
- `~/.claude/rules/front-load-executive-decisions.md` — an unattended loop is
  precisely where a mid-run decision should have been a `telegram-ask`
- A nightly detector for this shape runs from the portfolio's private routines
