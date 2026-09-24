---
name: github-comment-content
description: Decide what a PR or issue comment says — cut every fact the GitHub page already renders, keep what it cannot show. Use when writing a PR/issue comment, or briefing a cold-read gate on one.
allowed-tools: Read, Bash(gh pr view *), Bash(gh issue view *), Bash(gh api *), TodoWrite
created: 2026-09-24
modified: 2026-09-24
reviewed: 2026-09-24
---

# A PR Comment Carries What the Page Cannot Render

Promoted from the always-loaded `pr-comment-vs-ui-affordances.md` portfolio
rule, whose stub keeps the gate line.

GitHub renders most of a pull request's *state* on the page: merge status, check
names and outcomes, review rollup, branch names, diff size, labels. A comment
that restates any of it is not merely redundant. It explains GitHub to someone
who maintains a repository on GitHub. It buries the one or two sentences that
carry new information. And it makes a short reply look long, so the reader
skims and misses the part that mattered.

> **The law: before writing a sentence into a PR or issue comment, ask whether
> the reader is looking at that fact already. If the page renders it, cut it.
> The comment's job is the part of the story the page cannot show.**

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Replying to a maintainer on a PR or issue | Register and structure once content is decided → `communication-plugin:ticket-drafting-guidelines` |
| Running a cold-read gate over a comment | The text goes to a context-free reader (an issue body, docs) → `agent-patterns-plugin:cold-read-gate` |
| Writing a PR description or a status update comment | Choosing the PR title → `git-plugin:github-pr-title` |

## What the page renders (measured, not assumed)

Captured 2026-09-02 from `Comfy-Org/ComfyUI_frontend#13280` as a signed-in
maintainer would see it. This is an inventory to check against, not a claim
that GitHub's layout is frozen — re-capture if a comment hinges on it.

| Region | Renders |
|---|---|
| **Header**, no scrolling | State (Open/Merged/Closed); author; `wants to merge N commits into <base> from <head>` with **both branch names**; tab counts for Conversation / Commits / **Checks** / Files changed; the `+N −M` diff stat |
| **Sidebar** | Each reviewer with their state (approved / pending); `At least 1 approving review is required to merge this pull request`; assignees; labels; project; milestone |
| **Merge box**, foot of the Conversation tab | Review rollup (`Changes approved`, `1 approval`, `1 pending review`); **`17 workflows awaiting approval — This workflow requires approval from a maintainer`, with a help link**; counts of pending / skipped / successful checks; **every check by name**, each badged `Required` where it is; `This branch is out-of-date with the base branch` / `Changes can be cleanly merged`, with an `Update branch` button; conflict state when conflicting |

Do not write, in a comment:

- Check names, counts, or states; whether CI passed, failed, or has not run.
- That workflows await approval, or how the fork-PR approval gate works.
- Mergeable / conflicting / out-of-date status.
- Branch names, commit counts, file counts, diff size.
- Who reviewed, who is assigned, which labels are set.
- That you lack write access — the `<fork>:<branch>` header already says so.

Write instead the things that exist nowhere on the page:

- What you **did** that leaves no diff: what you verified, on which commit, and what that verification does not cover.
- **Why** you chose one approach over another.
- A claim about code the reader would otherwise have to go find, with the path.
- A check that produced **no** change (`main` has not touched this file since your base) — absence is invisible by construction.
- A decision you need from them that no button can ask for.

## The canonical break (2026-09-02, #13280)

Replying to a maintainer who had rebased the PR, I wrote a closing paragraph
explaining that a force-push re-arms the fork-PR gate, that 17 runs sat in
`action_required`, and naming four of them. The merge box directly below the
comment said **"17 workflows awaiting approval / This workflow requires
approval from a maintainer"**, linked GitHub's own explainer, listed all four
required checks by name, and offered the button. The paragraph was a worse copy
of the box, addressed to the only person who could press it.

An earlier draft of the same comment also restated `merges clean onto current
main`; the box renders `Changes can be cleanly merged`.

## Why a cold-read gate pushes you *toward* this mistake

`agent-patterns-plugin:cold-read-gate` is the right instrument for outward-bound
text and the wrong one to apply naively here, because its reader is
**context-free by construction** while a PR reader is **surrounded by rendered
state**. The gate asks, correctly for a stranger and wrongly for a maintainer,
what the fork-PR gate is, whether the four named workflows are all of them, and
what the merge status is. Answering those inflates the comment with exactly the
duplication above.

Two consequences:

- **Brief the reader with what the surrounding UI shows.** Put it in the
  prompt's `Ignore:` list: *"the reader can see the merge box, the check names,
  the review state, and both branch names; do not ask for those."* Otherwise, its
  findings and this skill pull in opposite directions.
- **A gate verdict is about sentences, never about whether a paragraph should
  exist.** In the break above, the round-one readers returned `needs-revision`
  partly *because* of the verification hedging; the fix that followed made the
  comment longer. Both a prose linter and a cold reader score what is on the
  page. Only a human asked the question that removed 58% of it.

## Related

- `documentation-plugin:docs-single-source` — link, don't duplicate. This is
  that law with the rendered UI as the single source.
- `agent-patterns-plugin:cold-read-gate` — the instrument this skill scopes.
- `communication-plugin:ticket-drafting-guidelines` — register and structure
  once the content is decided; this skill decides the content.
- The labels, assignees, and reviewers the UI renders are set through a
  metadata-hygiene checklist at PR creation (`git-plugin:git-pr`).
