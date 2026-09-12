---
name: upstream-pr-contribution
description: "Opening a pull request against a repository you do not own. Use when about to open one, to read CONTRIBUTING.md and the PR template in full and meet the contribution gates bots enforce."
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-08-06
modified: 2026-09-12
reviewed: 2026-09-12
---

# Read CONTRIBUTING.md in Full Before an Upstream PR — the Gates Live Below the Fold

Before opening a PR against a repo you don't own, read **all** of
`CONTRIBUTING.md` and the **PR template**, not the first screenful. The
welcoming "here's what we merge" list is at the top; the *gates* — the
requirements that get a PR auto-closed by a bot — are typically 150+ lines
down, past the local-dev setup. A `head -60` read looks like due diligence and
misses them entirely.

## The two gate classes a truncated read misses

| Gate | What it demands | Failure mode |
|---|---|---|
| **Issue-first policy** | An issue must exist *before* the PR, linked via `Fixes #N` / `Closes #N` in the description | A bot comments "no linked issue"; PR blocked or closed without review |
| **Prose-style rules** | Short, plain-voiced descriptions written in your own words | *"If you paste a large clearly AI generated description here your PR may be IGNORED or CLOSED"* — no bot catches this; a human just stops reading |

The second is the one that doesn't announce itself. Compliance bots check for
a linked issue and for template sections; **nothing** flags an
AI-shaped wall of text. It costs you the maintainer's attention silently, and
green checks give false reassurance that the PR is in good shape.

## The check — two API calls, before writing anything

```sh
gh api repos/<owner>/<repo>/contents/CONTRIBUTING.md --jq .content | base64 -d
gh api repos/<owner>/<repo>/contents/.github/pull_request_template.md --jq .content | base64 -d
```

Read both **to the end**. Grep is not a substitute — you don't know the
section names in advance (`Issue First Policy`, `No AI-Generated Walls of
Text`, `General Requirements` are not terms you'd think to search for).

Also check for enforcement automation, which sets the clock you're working
against:

```sh
gh pr view <n> -R <owner>/<repo> --json comments --jq '.comments[]|"\(.author.login): \(.body[0:200])"'
gh pr checks <n> -R <owner>/<repo>
```

## Writing the description

- **Fill the template verbatim** — same headings, same order, checkboxes
  ticked. Several repos auto-reject on missing sections.
- **Halve it, then halve the framing.** Keep: what broke, the change, the
  non-obvious implementation details, and the verification output. Cut:
  restated context the maintainer already has, bolded lead-ins on every
  paragraph, exhaustive rationale sections, "Scope"/"Notes" appendices.
- **Verification is not optional prose** — most templates ask *how you
  verified it works* and *how a reviewer reproduces it*. Paste the actual
  output (a runner log excerpt, a before/after command), not a claim.
- The house style for a portfolio-internal PR body (detailed, sectioned,
  evidence-heavy) is **wrong** for an upstream one. Different audience,
  different budget for your words.

## Bots enforce on a deadline

Compliance bots comment within ~60s of opening and frequently carry a hard
timer (*"address the above within 2 hours, or it will be automatically
closed"*). So **check the PR's comments shortly after opening it** rather than
walking away — an upstream PR is not done when `gh pr create` returns.

Fixing compliance re-runs the checks; the original bot comments **stay on the
thread** and are not retracted. The checks, not the comments, are the live
signal — read `gh pr checks`, and note the newer run id.

> Evidence (2026-07, `anomalyco/opencode#39147`): I read the first 60 lines of
> CONTRIBUTING.md, concluded the PR "fits their bug-fixes category", and opened
> it. Two bots fired in 60 seconds — missing linked issue, missing template
> sections, 2-hour auto-close. Line 180 held an Issue First Policy; line 204
> held "No AI-Generated Walls of Text", which the original description was a
> textbook instance of. Recovered by opening issue #39163 and rewriting to the
> template at roughly half the length, but the *style* violation would have
> cost the PR its reading regardless of the green checks.

## Relationship to sibling rules

- `~/.claude/rules/read-issue-thread-before-contributing.md` — read the issue
  *thread* before scoping the work. This rule is the next step: read the
  *contribution gates* before opening the PR. Both are "go to the primary
  source, and don't stop at the summary."
- `~/.claude/rules/tool-use-patterns.md` (Read refuses >25 000 tokens; page
  with offset/limit) — the mechanical habit that causes this: truncating a
  long doc and treating the excerpt as the whole.
- `github-metadata-hygiene.md` — the metadata checklist for repos *we* own;
  upstream repos impose their own, stricter, and enforced by bot.

## Rationale

The asymmetry is stark: reading two files to the end costs one minute, and
skipping it costs a bot-blocked PR on a countdown, a scramble to open a
retroactive issue, and — worse, because nothing reports it — a description
written in exactly the register the maintainers said they ignore. The top of
CONTRIBUTING.md is marketing; the bottom is the contract.
