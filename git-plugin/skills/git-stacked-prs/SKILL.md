---
name: git-stacked-prs
description: "GitHub native stacked PRs via gh stack. Use when creating, syncing, rebasing or merging a PR stack, or choosing stacks vs manual PR chains."
user-invocable: false
allowed-tools: Bash, Read
created: 2026-09-04
modified: 2026-09-04
reviewed: 2026-09-04
---

# GitHub Native Stacked PRs (`gh stack`)

GitHub has a first-party stacked-PR model: a chain of PRs registered *with
GitHub*, driven by the `github/gh-stack` CLI extension. A registered stack
behaves differently from the ad-hoc chain this plugin's other skills describe —
GitHub retargets, runs CI, and merges the stack itself.

> **Public preview.** The feature and its CLI surface are subject to change.
> No repository or organization setting enables it; it is on by default.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Building a change as a registered `gh stack` | Rebasing a plain feature branch → `git-rebase-patterns` |
| Deciding stack vs. ad-hoc PR chain | Merging one PR safely → `git-merge-hazards` |
| Merging or syncing a registered stack | Creating a single PR → `git-pr` |
| A repo's PRs show GitHub stack UI | Cross-fork contribution → `git-upstream-pr` (stacks are same-repo only) |

## Registered stack vs. ad-hoc chain

Three hazards this plugin documents at length apply to **ad-hoc** chains (you
opened PR B with `--base` pointing at PR A's branch). A stack registered with
GitHub removes all three:

| Behaviour | Ad-hoc chain | Registered stack |
|-----------|--------------|------------------|
| Parent merges | Child **auto-closes** if the parent's branch is deleted (`git-merge-hazards` §2) | PRs above stay open and **auto-retarget** to the stack's base |
| CI on `pull_request: branches: [main]` | Child gets **no checks** until retargeted (`git-pr` § Stacked PRs) | Runs for **every** PR in the stack |
| Rebasing after a parent lands | Manual `git rebase --onto <old-parent-tip>` per child | `gh stack sync` cascades it |

Required reviews, required status checks, and CODEOWNERS are enforced against
the **stack's base branch** for every PR in the stack — a stack is not a way to
route around branch protection.

Ad-hoc chains remain the right tool where a stack cannot go: cross-fork work,
and any repo where the merge tooling has not been updated (see Limits).

## Setup

```bash
gh --version                                # need 2.90.0+ (git 2.20+)
gh extension install github/gh-stack
gh stack alias                              # optional; creates `gs`
```

## Lifecycle

```bash
gh stack init                               # start a stack; -b <branch> to set trunk
git add . && git commit -m "feat(a): first layer"

gh stack add feat/layer-b                   # next branch on top
git add . && git commit -m "feat(b): second layer"
# or in one step:
gh stack add -Am "feat(b): second layer"    # -A stages all incl. untracked; -u tracked only

gh stack push                               # push every branch in the stack
gh stack submit                             # create/update the linked PRs
gh stack view                               # ordering + PR links (-s short, --json)
```

`gh stack submit` opens an editor and creates **drafts** by default. For
non-interactive agent use:

```bash
gh stack submit --auto --open               # auto-generated titles, ready for review
```

Because `--auto` generates titles from commits, the commit subjects must already
be conventional (`.claude/rules/conventional-commits.md`) — a PR title is what
lands on squash-merge.

## Keeping the stack current

```bash
gh stack sync                               # fetch + rebase + push + refresh PR state
gh stack sync --prune                       # also delete branches of merged PRs
gh stack rebase                             # cascading rebase only
gh stack rebase --downstack                 # trunk → current branch only
gh stack rebase --upstack                   # current branch → top only
gh stack rebase --continue | --abort        # after resolving conflicts
```

Conflicts exit **3**; resolve, then `--continue`. `--abort` restores the
pre-rebase state.

## Navigating and restructuring

| Command | Effect |
|---------|--------|
| `gh stack checkout <stack-no \| pr-no \| pr-url \| branch>` | Check out a stack |
| `gh stack up [n]` / `gh stack down [n]` | Move away from / toward trunk |
| `gh stack top` / `gh stack bottom` / `gh stack trunk` | Jump |
| `gh stack switch` | Interactive branch picker (needs a TTY) |
| `gh stack modify` | Interactive restructure — `x` drop, `d`/`u` fold, `i`/`I` insert, `Shift+↑/↓` move, `r` rename, `z` undo, `Ctrl+S` apply |
| `gh stack link <branch-or-pr> <branch-or-pr>…` | Register **existing** PRs as a stack, no local tracking |
| `gh stack unstack [<n>]` | Unregister (`--local` keeps the GitHub stack) |

`gh stack modify` and `gh stack switch` are TTY-interactive — unusable from an
agent's Bash tool. Reach for `gh stack rebase`/`link`/`view --json` instead.

`gh stack link` is the migration path for an ad-hoc chain that already exists:
it converts the manual chain into a registered stack, which is what buys the
auto-retarget and CI behaviour above.

## Merging

```bash
gh stack merge <stack-no | pr-no> --squash -y
```

Merge methods: `--merge`, `--squash`, `--rebase` (or `--merge-method <m>`).
`-y` skips the confirmation prompt. PRs merge **bottom-to-top**; merging a
mid-stack PR leaves the ones above open and retargeted.

## Limits

| Limit | Consequence |
|-------|-------------|
| Same repository only | Cross-fork stacks are unsupported — use `git-upstream-pr` |
| Async merge API required | The legacy PR-merge REST endpoints **cannot** merge a stack; automation calling `PUT /repos/{o}/{r}/pulls/{n}/merge` breaks on stacked PRs |
| Not in GitHub Desktop | CLI or web only |
| Public preview | Commands and behaviour may change |

The merge-API limit is the one that bites automation: audit any bot, `just`
recipe, or workflow that merges PRs programmatically **before** adopting stacks
in a repo, or those merges will start failing on stacked PRs only.

## Exit codes

`gh stack` exits with specific codes — branch on them rather than parsing text.

| Code | Meaning | Code | Meaning |
|------|---------|------|---------|
| 0 | Success | 6 | Disambiguation required (branch in several stacks) |
| 1 | Generic error | 7 | Rebase already in progress |
| 2 | Not in a stack / stack not found | 8 | Stack locked by another process |
| 3 | Rebase conflict | 9 | Stacked PRs not enabled for repository |
| 4 | GitHub API failure | 10 | Modify session interrupted; recovery needed |
| 5 | Invalid arguments or flags | | |

Code **8** (locked by another process) is the stack-level analogue of
`.claude/rules/agent-coworker-detection.md`: another agent or session is
operating on the same stack. Back off; do not force.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Machine-readable stack state | `gh stack view --json` |
| One line per branch | `gh stack view -s` |
| Non-interactive PR creation | `gh stack submit --auto --open` |
| Disable hyperlink escapes in captured output | `GH_STACK_HYPERLINKS=0 gh stack view` |
| Deterministic colours in logs | `GH_STACK_THEME=light` (or `dark`) |
| Merge without prompting | `gh stack merge <n> --squash -y` |
| Sync and clean merged branches | `gh stack sync --prune` |

`gh stack view --json` exits 0 with valid JSON on an empty result, so it is
parallel-safe (`.claude/rules/parallel-safe-queries.md`); the bare `gh stack
view` exits 2 outside a stack and would cancel sibling calls in a batch.

## Quick Reference

| Task | Command |
|------|---------|
| Install | `gh extension install github/gh-stack` |
| Start a stack | `gh stack init` |
| Add a layer | `gh stack add -Am "feat(x): …"` |
| Publish | `gh stack push && gh stack submit --auto --open` |
| Refresh after trunk moves | `gh stack sync` |
| Adopt an existing chain | `gh stack link <pr-a> <pr-b>` |
| Merge the stack | `gh stack merge <n> --squash -y` |
| Tear down | `gh stack unstack` |

## Related

- `git-plugin:git-merge-hazards` — auto-close, push-by-SHA races on **ad-hoc** chains
- `git-plugin:git-rebase-patterns` — `git rebase --update-refs`, the local-only equivalent of `gh stack rebase`
- `git-plugin:git-pr` — single-PR creation and the manual retarget/rebase dance
- `.claude/rules/gh-json-fields.md` — `state`/`mergedAt` when auditing a stack's PRs
- `.claude/rules/conventional-commits.md` — why `--auto` titles depend on commit subjects
