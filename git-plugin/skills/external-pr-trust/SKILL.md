---
name: external-pr-trust
description: Authorship as a precondition of merging — bot vs stranger classification, what a merge executes, the merge-guard hook. Use when bulk-merging PRs, or when a merge is denied for a non-self author.
allowed-tools: Read, Grep, Glob, Bash(gh pr view *), Bash(gh pr list *), Bash(gh pr diff *), Bash(gh api *), Bash(gh search *), TodoWrite
created: 2026-09-24
modified: 2026-09-24
reviewed: 2026-09-24
---

# External-Contributor PRs — Authorship Is a Precondition of Merging

Promoted from the always-loaded `external-contributor-prs.md` portfolio rule,
whose stub keeps the gate lines.

Public repos accept PRs from anyone. Merge tooling, though, is usually built
for bulk-merging **your own and bots'** PRs: a picker such as `ghsq` → `^a`
(select all) → `a` (all remaining) lands a queue of release-please and feature
PRs in one pass. A stranger's PR riding that reflex is merged code nobody read.

> **The law:** before merging, know **who wrote it**. `author.login == you` or a
> bot is the fast path. Anything else is a review, not a merge.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Clearing a queue of PRs in one pass | Checking whether a merge did what you think → `git-merge-hazards` |
| The external-PR merge guard denied a `gh pr merge` | Opening a PR against someone else's repo → `upstream-pr-contribution` |
| A PR adds a GitHub Action, hook, or dependency | Writing CI that runs on fork PRs → `github-actions-plugin:claude-code-github-workflows` |

## Why it is not merely "review your PRs"

A PR is not inert text — merging can *execute* code:

| Path touched | What merging does |
|---|---|
| `.github/workflows/**`, `.github/actions/**` | Runs in CI, with whatever `permissions:` the workflow grants itself |
| `**/hooks/**`, `*.sh` | Runs on **your machine** (Claude Code hooks, git hooks, justfile recipes) |
| `.claude/**` | Changes agent permissions, rules, or settings |
| `package.json`, `pyproject.toml`, `mise.toml`, `.pre-commit-config.yaml` | Changes what gets installed and run |

Two things make a third-party CI addition worse than it looks — check them
explicitly on any PR that adds an action:

- **A floating tag is mutable.** `uses: owner/action@v0` resolves at dispatch
  time, so the publisher (or whoever takes over their account) can retarget the
  tag after you merge and change what runs, with no diff on your side.
- **`runs.using` does not tell you what it does.** A `node20` or `composite`
  action can download and execute a remote binary — and often does: the
  canonical case (claude-plugins#2231) was a `node24` action whose entire job
  was to resolve the `latest` release of a *different* repo at run time, fetch a
  native binary from it, `chmod 0755`, and execute it. Pinning the action to a
  SHA does not pin that second fetch. Read the action's `src`/`action.yml` at
  the pinned SHA rather than trusting its declared type.

## Classify the author correctly — bots render three different ways

Getting this wrong in either direction breaks the guard: flag the bots and it
becomes noise you train yourself to click through; miss a stranger and it does
nothing. The trap is that a bot author looks different depending on which `gh`
subcommand produced it:

| Source | `login` | `is_bot` | `type` |
|---|---|---|---|
| `gh pr list` / `gh pr view` | `app/laurigates-release-please` | `true` | — |
| `gh search prs` | `laurigates-release-please[bot]` | **`false`** | `Bot` |

So `is_bot` **alone silently misclassifies every App bot in search results as a
stranger**. Accept any of: `is_bot == true`, `type == "Bot"`, a `*[bot]` login,
or an `app/*` login. (`authorAssociation` is *not* a field on `gh pr list`/`gh pr
view --json` — read it from `gh api repos/O/R/pulls/N --jq .author_association`.)

## The two guards

| Actor | Mechanism | Behavior |
|---|---|---|
| **The human**, in the shell | `_gh_trust_gate` / `_gh_confirm_external` in the dotfiles `dot_zshrc.tmpl`, used by the `ghsq` / `ghrb` / `ghrp` pickers | External PRs are **hidden from the picker** (a stderr banner counts them; `ghsq -x` includes them, marked `⚠` white-on-red). Merging one prints author + association + which touched paths execute, is **never** swept up by `a`=all, and requires typing `merge` — not a keypress. |
| **Claude**, in any repo | `hooks-plugin/hooks/external-pr-merge-guard.sh` (PreToolUse) | **Denies** `gh pr merge`, `gh api .../pulls/N/merge`, and MCP `merge_pull_request` for a non-self, non-bot author. Also denies when authorship can't be established. |

Both fail **closed**: if the author cannot be read, the merge is refused rather
than allowed. "Cannot verify" is not "safe."

## What Claude does when the guard fires

Do not look for another merge route — the hook covers `gh pr merge` in every
flag order, the `gh api` path, and the MCP tool, and `--admin` does not bypass
it. Instead:

1. **Report what the PR actually changes.** Read the diff. For an added action
   or dependency, say where the code comes from, whether the ref is a **commit
   SHA or a mutable tag**, and what it downloads or transmits at runtime.
2. **Hand the merge back.** `ghsq -x` (which will demand the typed confirmation),
   or `gh pr merge <n> --squash --delete-branch` run by the human.

## A bulk merge must issue one literal PR number per call

The guard resolves the PR selector **structurally**, and an unresolvable
`$var` selector lands in its "not determinable" row — which is denied, because
"cannot verify" is not "safe". So the obvious way to clear a queue of bot PRs
is refused before it starts, even though every PR in it is a bot's:

```
# Denied — the hook cannot tell whose PR $n is
for n in 2133 2134 2135; do gh pr merge $n --squash --delete-branch; done
```

```
# Allowed — each literal number is checked on its own
gh pr merge 2133 --squash --delete-branch
gh pr merge 2134 --squash --delete-branch
```

Wrapping the loop does not help: `xargs`, `find -exec`, `parallel`, `timeout`,
`bash -c`, and command substitution are all resolved through to the `gh pr
merge` inside them.

This bites a **Renovate onboarding sweep** specifically, because the usual
workflow there is bucket-then-bulk-act: categorize the PRs by check state, then
merge the whole `NOCHECKS`/`PASS` bucket. Categorize in a loop all you like;
emit the merges one literal call at a time. Read the buckets out first
(`gh pr list --json number,author`) so the numbers are in hand as literals
before the first merge.

The constraint is a feature, not friction to route around: it is what stops a
stranger's PR from riding the same reflex. Do not build a helper that hides the
number from the hook — that is the bypass the guard exists to prevent.

The denial names the fix — "resolve shell variables to their literal values
first … then merge with literal values one at a time" — so the recovery costs
one re-read of the error, not a diagnosis.

Never prefix `CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1` onto a command — it is
only honored from the operator's own shell environment, precisely so an agent
cannot self-serve the bypass (`handling-blocked-hooks.md`).

## Evidence

`claude-plugins#1222` (2026-05, `tjhub1983`, `FIRST_TIME_CONTRIBUTOR`) was
merged with **no review and no comments**. It rewrote a Claude Code Stop hook —
code that runs locally — and shipped a broken TODO scan that had to be repaired
three weeks later in #1229. It also flipped the hook's file mode `100755 →
100644`, which is still un-restored. One drive-by merge, two defects, neither
noticed at merge time. That is the failure mode both guards exist to stop.

## Related

- `git-plugin:git-merge-hazards` — the *mechanics* of merging (squash-merge detection, stacked-PR auto-close, `UNSTABLE` vs `BLOCKED`). This skill is the *trust* axis: that one asks "did the merge do what I think?", this one asks "should I be merging this at all?"
- `git-plugin:upstream-pr-contribution` — the mirror image: the gates *others* impose on PRs you send them
- `hooks-plugin/README.md` § external-pr-merge-guard.sh — the hook's own documentation
