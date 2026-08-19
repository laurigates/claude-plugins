---
name: git-issue-scoping
description: "Read an issue's full comment thread and re-verify its cited evidence at HEAD. Use when scoping a PR or plan from a GitHub issue, or before filing or reversing one in your own tracker."
allowed-tools: Read, Grep, Glob, Bash(gh issue *), Bash(gh pr *), Bash(gh api *), Bash(git log *), TodoWrite
created: 2026-08-19
modified: 2026-08-19
reviewed: 2026-08-19
---

# Git Issue Scoping

Invoke before building a PR, plan, or prototype off a GitHub issue — including
issues in repos you own, and before filing or reversing one in your own tracker.

Before building a PR (or even an approach) off a GitHub issue, **read every
comment in the thread** — not a fetched summary, not just the body. Issues that
look like simple feature requests are often where the maintainer has already
**converged on a specific design** with other experts. A summary compresses
exactly the part that matters: the decided mechanism, the agreed scope, and the
work someone has already volunteered to do.

**Applies to repos you own too** (§ *Your own tracker*): the deference part is
about upstream, but the load-bearing part is that a tracker records decisions
past-you made and no longer remembers.

## The trap

`WebFetch` (and any "summarize this issue" step) returns a *compressed* view. It
faithfully captures the issue **body** and headline asks, but silently drops the
back-and-forth in the comments where the real decisions live. You then design
against the body's framing, build a prototype, and discover — only if you go
back and read the comments — that:

- the maintainer picked a **different mechanism** than the obvious one,
- the **scope** (MUST / WANT / NICE / OUT) was explicitly bounded,
- a dependency was **already prototyped** by a collaborator (and may be
  unreleased, so half your plan isn't even buildable yet),
- your "open questions" were **already answered** in the thread — so asking them
  reads as not having done the homework.

> Canonical break (jnv #114 → PR #116, 2026-06): a WebFetch summary presented the
> issue as "extend completion beyond JSON paths." The actual 33-comment thread was
> a design discussion in which the maintainer and the jaq author had converged on
> **token-based segmentation** (jaq's `load::lex` token trees) plus a new `yield`
> filter (an *unmerged* jaq PR) for the in-paren case, with an explicit scope
> ladder. We built a byte-scanner PoC and a PR body that re-litigated settled
> questions — caught only when the user asked "did we check all the comments?"
> The PR had to be reframed before it was safe to surface.

## The rule

When an issue is the basis for a contribution, read the comments **first**:

```sh
gh issue view <n> --repo <owner>/<repo> --json title,body,author,comments \
  --jq '.body, (.comments[] | "--- " + .author.login + " ---\n" + .body)'
```

Specifically extract, before writing any code:

1. **Decided mechanism** — has the maintainer chosen an implementation approach?
   Build *that*, or explicitly propose an alternative knowing theirs exists.
2. **Scope ladder** — MUST / WANT / NICE / OUT. Don't attempt OUT; don't skip MUST.
3. **Dependencies in flight** — linked PRs/branches a collaborator is building.
   Check their state (`gh pr view` → merged? released?) before depending on them.
4. **Who's driving** — if the maintainer is mid-collaboration with another expert,
   a drive-by PR may duplicate their work. Ask whether a contribution is welcome
   *before* investing, and frame the PR as building on the thread, not restarting it.

If you only have a summary and a gap has passed, **re-read the live thread** before
acting — the discussion may have moved.

## Your own tracker — search before filing, read before reversing

No maintainer to defer to is exactly why this gets skipped. Two failures:

1. **Search before filing** — a well-researched duplicate is still a duplicate,
   and the better write-up makes it *harder* to spot as one.
   `gh issue list -R <o>/<r> --state all --search "<kw>" --json number,title,state`
2. **Read before reversing** — an old issue records not just a problem but a
   *decision with its reasoning*, including decisions to **defer**. Shipping the
   deferred option because it is obviously better silently overrides a choice
   made with context you no longer have.

> Observed 2026-08 (pal-mcp-server), ten minutes apart: filed a detailed issue
> duplicating a month-old one that had already diagnosed the same broken publish
> pipeline — then merged a PR doing the very migration that issue **explicitly
> deferred**. Neither was caught by review; both surfaced only from listing open
> issues afterwards.

The tell: calling something "the obvious fix" on a subsystem broken long enough
for someone to have written about it — long-broken means *investigated*. When
reversing a decision, say so on the PR and issue, quoting the old reasoning, so
the next reader sees a decision changed rather than forgotten.

## An issue's cited evidence expires — re-verify every line before acting on it

Distinct from the sections above, which are about *discussion* you failed to
read. Here you read everything, and the issue is simply **out of date**: it
cites `file.ts:230` and asserts what is there, and between filing and today
some unrelated PR fixed it. A well-written issue makes this worse — precise
line numbers and quoted snippets read as verified fact, and the better the
write-up, the less anyone re-checks it.

> Observed 2026-08-13 (thelma #1055). A security issue's central claim was
> "no `responseSchema` enforcement on the Gemini call — `gemini.ts:230` does
> not pass it." True when filed on 05-13; false by the time it was worked.
> #1060 had added it in between. The issue even listed *"`responseSchema`
> enforcement is deliberately removed (currently absent)"* as a trigger to
> re-evaluate — so writing the doc from the issue verbatim would have shipped
> a threat model asserting the absence of the control that was by then its
> primary defence, and inverted one of its own triggers.

- **Re-read every file:line the issue cites, at HEAD, before writing anything
  from it.** The issue is a *claim about the code*, and the code is the
  authority — same instinct as `diagnose-at-the-failure-point.md`.
- **Date the gap.** `gh issue view <n> --json createdAt` against
  `git log -S'<symbol>' -- <path>` finds the PR that moved it. An issue older
  than a few weeks on an active file should be assumed stale until checked.
- **Report the correction in the PR that acts on it**, so the next reader sees
  the issue's evidence was superseded rather than silently contradicted.
- Corollary for *filing*: prefer citing behaviour and symbols over line
  numbers, which rot fastest.

## When it bites

- Any external contribution scoped from an issue, especially a popular repo where
  maintainers discuss design in comments.
- **Acting on an issue filed weeks or months ago against a file that has since
  changed** — the evidence is stale even though the thread is complete.
- **Your own repo**, when the tracker is the last place you think to look.
- Resuming work on an issue days later from a cached summary.
- Letting an early `WebFetch`/research step stand in for the primary source.

## Related

- `~/.claude/rules/verify-upstream-before-patching.md` — same instinct (check
  the authoritative source before acting) for vendored code; this is the
  issue-thread analogue.
- `~/.claude/rules/tool-use-patterns.md` (WebFetch) — a summary is lossy; for a
  decision that gates real work, go to the full source, not the fetched digest.
- `git-plugin:git-issue` — the consumer: the end-to-end issue→PR workflow that
  scopes from the issue thread this skill teaches you to read in full.

## Rationale

The cost asymmetry is stark: reading the thread is one `gh issue view` and a few
minutes; skipping it costs a misaligned prototype, a PR that signals you didn't
read the discussion, and a reframe-or-close under the maintainer's eye. The full
thread is the spec; the summary is a lossy proxy for it.
