---
name: actions-billing-usage
description: Measure GitHub Actions cost with the billing-usage API — per repo, month and SKU; net vs gross; per-job rounding. Use when optimizing CI cost or speed, or before removing a workflow as expensive.
allowed-tools: Bash(gh api *), Bash(gh run list *), Bash(jq *), Read, TodoWrite
created: 2026-09-24
modified: 2026-09-25
reviewed: 2026-09-24
---

# Before Optimizing CI Cost, Read the Billing-Usage API

Promoted from the always-loaded `ci-cost-read-the-billing-api.md` portfolio
rule, whose stub keeps the gate line.

Any "make CI cheaper / faster" task starts with a guess about *where the cost
is*, and across a portfolio that guess is reliably wrong. The intuition follows
**where the interesting work is** (the private repos, the big builds); the
actual minutes follow **how often a workflow fires**, which is dominated by
automation nobody thinks of as expensive. GitHub will tell you exactly, per
repo, per month, per SKU — ask it first, then optimize.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| A runner-tier, concurrency, caching, or scheduling change is pitched as a cost or speed win | The target is a single known-slow workflow you are already measuring directly |
| About to *remove* a workflow "because it must be expensive" | |
| A bill moved and the cause isn't obvious — the per-repo × per-month breakdown localizes it in one call | |
| Adding automation, to decide whether it gets its own job | |

## The endpoint (the obvious one is gone)

```
gh api "/users/<user>/settings/billing/usage"
```

> `/users/<user>/settings/billing/actions` — the endpoint most examples and most
> recall still name — now returns **HTTP 410** *"This endpoint has been moved."*
> That 410 is easy to misread as "no billing data available on this plan" and
> skip the measurement entirely.

Org equivalent of the working endpoint: `/orgs/<org>/settings/billing/usage`.

Aggregate before reading; the raw response is one row per repo × month × SKU:

```
gh api "/users/<u>/settings/billing/usage" --jq '[.usageItems[] | select(.product=="actions" and .unitType=="Minutes")] | group_by(.repositoryName) | map({repo:.[0].repositoryName, minutes:(map(.quantity)|add), net:(map(.netAmount)|add)}) | sort_by(-.minutes)'
```

## Reading it correctly

- **The filter takes the *bare* repo name, not `owner/repo`.**
  `select(.repositoryName == "<owner>/<repo>")` returns `[]`, which is
  indistinguishable from "this repo bills nothing"; `"<repo>"` returns the rows.
  The owner-qualified filter has reported nothing for a repo billing thousands
  of minutes that month, and a cost argument was nearly built on that empty
  result. Control-test an empty billing filter against a repo you know is
  active before believing it.
- **`netAmount`, not `grossAmount`, is the spend.** Public-repo minutes are free
  and unlimited, so their rows read `grossAmount == discountAmount` and
  `netAmount == 0`. A repo showing a large gross may be costing nothing — but
  it's still where a runner-tier change would pay off *once* charges begin, so
  read both: gross for **exposure**, net for **current spend**.
- **Group by SKU too** (`Actions Linux` vs `Actions Linux Slim` vs
  `Actions macOS 3-core`) — it reveals which tiers are already in use and their
  `pricePerUnit`, so the cheaper-runner arithmetic needs no lookup.
- **Read the monthly trend, not just the total.** A flat annual figure hides an
  exponential; the decision usually turns on the slope.
- **The default response is windowed — the obvious call will not give you the
  trend.** A bare `/orgs/<org>/settings/billing/usage` returns only a slice
  (observed 2026-08: Jan–Feb only, for a repo with a full year of activity), and
  nothing in the payload says it was truncated. Build the trend from explicit
  per-month calls and let the months you asked for be the months you got:

  ```
  for m in $(seq 1 12); do gh api "/orgs/<org>/settings/billing/usage?year=2026&month=$m" --jq "[.usageItems[] | select(.product==\"actions\" and .repositoryName==\"<repo>\")] | map(.quantity) | add // 0" ; done
  ```
- **Read the outcome distribution, not just the minutes.** Minutes tell you
  something is expensive; outcomes tell you whether you are buying anything.
  An E2E suite billing close to an hour per run while `cancel-in-progress`
  killed it about halfway through succeeded a few percent of the time.
  "Expensive" argues for a cheaper runner; "expensive and almost never
  succeeding" argues for deleting or fixing the workflow. Same bill, different
  decision. Pull conclusions alongside cost:

  ```
  gh run list -R <owner>/<repo> --workflow <name> -L 400 --json conclusion --jq 'group_by(.conclusion) | map({(.[0].conclusion // "null"): length}) | add'
  ```
- **`/actions/workflows/<id>/timing` is empty for public repos** — billable ms
  is only populated where minutes are billed. Approximate per-workflow cost
  instead:

  ```
  gh run list -R <owner>/<repo> -L 400 --json workflowName,startedAt,updatedAt
  ```

  then group durations by `workflowName`. Good enough to rank; don't quote it as
  billing truth — run wall-clock includes queue and finalisation time that is not
  billed, so it **over-counts** (measured ~16% above the billing API for the
  same repo and period). Rank with wall-clock; quote the API.

## Minutes are billed per job, rounded up

> "GitHub rounds the minutes and partial minutes **each job** uses up to the
> nearest whole minute" — [Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing).

Per *job*, not per run: a workflow with three four-second jobs bills three
minutes. Linux 2-core is $0.006/min, Linux Slim $0.002/min. The billing rows
show the rounding directly — the `quantity` for `Actions Linux` and
`Actions Linux Slim` is always a whole number.

Two consequences when adding automation rather than optimizing it:

- **Fold trivial work into a job that already runs.** A seconds-long check (for
  example, renumbering a docs file) belongs in an existing docs job rather than
  a workflow of its own, which would bill a whole minute per trigger.
- **A job skipped by an `if:` bills nothing; a job that starts and exits early
  still bills its rounded minute.** When the point is to *not* pay, put the
  condition on the job — or on the expensive step, which also skips the model
  spend of an LLM-backed check.

## Why it changes the answer

In a portfolio runner audit, the plan was to move cheap jobs to a 1-CPU runner,
and the expected win sat in the private repos with real pipelines. The billing
API said **one** repo — a *public* plugin collection with no build step worth
mentioning — was the large majority of standard-Linux minutes, driven purely by
scheduled audits and PR automation. Every private repo that would have been
optimized first was ≈0 minutes. The month-over-month trend (roughly tripling
over a quarter, with the first net charges arriving) was what justified acting
at all. Without that one query the work would have landed almost entirely in
the wrong repos.

## Agentic Optimizations

| Context | Command |
|---|---|
| Minutes and net spend per repo | the aggregate query under *The endpoint* |
| Which runner tiers bill | that query with `group_by(.sku)` and `sku:.[0].sku` in place of the repo grouping |
| One month, one repo (bare name) | `gh api "/orgs/<org>/settings/billing/usage?year=2026&month=9" --jq '[.usageItems[] \| select(.product=="actions" and .repositoryName=="<repo>")] \| map(.quantity) \| add // 0'` |
| Outcomes per workflow | `gh run list -R <o>/<r> --workflow <name> -L 400 --json conclusion --jq 'group_by(.conclusion) \| map({(.[0].conclusion // "null"): length}) \| add'` |

## Related

- `finops-plugin:github-actions-finops` — the org/repo waste sweep (skipped
  runs, bot triggers, missing concurrency) that reads this same endpoint; this
  skill owns reading the endpoint itself

- `offload-to-deterministic-substrate.md` (in `~/.claude/rules/`) — one API call
  beats re-deriving cost from run logs by hand, every time.
- `code-quality-plugin:debugging-methodology` § failure point — same law applied
  to runtime: measure the thing, don't reason about it. Here the "failure point"
  is the invoice.
- `github-actions-plugin:multirepo-ci-cd` — the portfolio-sweep mechanics you'll
  use once the billing data has told you which repos to sweep.
