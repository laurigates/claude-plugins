---
name: git-merge-hazards
description: Traps in GitHub's merge machinery. Use when merging a PR, merging a stacked PR chain, auditing whether a branch really landed, or merging over red CI.
allowed-tools: Read, Grep, Glob, Bash(gh pr *), Bash(gh issue *), Bash(gh api *), Bash(git cherry *), Bash(git merge-tree *), Bash(git rev-parse *), Bash(git log *), Bash(git reflog *), Bash(git rebase *), Bash(git push *), Bash(git fetch *), Bash(just *), Bash(bash *), TodoWrite
created: 2026-08-19
modified: 2026-08-21
reviewed: 2026-08-21
---

# Git Merge Hazards

Read before merging a PR, merging a stacked PR chain, auditing whether a branch
really landed, or merging over red CI. The body below is the verbatim text of
the promoted `~/.claude/rules/pr-merge-hazards.md` rule.

Three notes that are *not* part of that body:

- Two gates below — §1's merged-ness authority order and the whole of §4 — are
  also reproduced verbatim in the `pr-merge-hazards.md` stub, because they are
  read *while* the decision is being made. Edit both copies together.
- §1 overlaps `git-plugin:deadbranch` Step 1.5 ("Reclassify squash-merged
  branches"), which carries the same three signals scoped to branch cleanup.
- The two encoded recipes cited in §1 and §2 below are the author's own (a
  `just -g` recipe in `laurigates/dotfiles`, and a sweep script in
  `laurigates/claude-plugins`), not commands a plugin consumer already has.
  Read the authority ladder in §1 as the instruction; the recipe is a
  convenience, and its REVIEW bucket measured ~90% false positives (#2268).

Four traps in GitHub's merge machinery, one law: "PR merged" says nothing about
*content* — and a red check is not proof of failure. Each: the trap, the
5-second check, the fix. Sibling: `~/.claude/rules/git-hazards.md` (local git).

## 1. `--merged` misses squash-merged branches

A squash-merge collapses a branch into one fresh-SHA commit on `main`, so the
branch's own commits are never ancestors — `git branch --merged` (and any
ancestry check) reports it **unmerged**. "Files identical to main" also fails
once `main` drifts the same files.

- **Check**, in order of authority:
  - `gh pr list --state all --head <branch> --json state` → a MERGED PR is
    **authoritative**. Reach for this first; the git-side checks below are all
    one-way.
  - `git cherry main <branch>` → marks a commit `-` when a patch-equivalent
    commit is already upstream, `+` when it is not. Survives squash **and**
    cherry-pick, and does not care that `main` drifted.
  - `git merge-tree --write-tree main <branch>` equals `git rev-parse main^{tree}`
    → contained. **A match proves containment; a non-match proves nothing.**
- **Not immune to drift** (corrected 2026-07): once `main` moves on over the same
  files, merging an already-merged branch back would re-introduce its older
  versions, so the trees differ and merge-tree reports **not contained** for work
  that fully landed. Observed reporting three merged branches as unmerged. Same
  trap as "files identical to main". Use the PR state or `git cherry` to decide;
  keep merge-tree only as a positive-containment shortcut.
- **Fix**: use the encoded recipe rather than re-deriving: `just -g branch-audit`
  (in `private_dot_config/just/git.just`) prints MERGED vs REVIEW + a paste-ready delete.
- A non-match is "review", **not** proof of unmerged — don't force the count to zero.

## 2. Merging a stacked base auto-CLOSES the child PR

When PR B is based on PR A's branch, merging A and deleting its branch
auto-closes B (GitHub does **not** retarget it), and a closed PR whose base
branch is gone **cannot be reopened**.

- **Fix — order matters**: retarget the child **first**, while the base PR is open:
  1. `gh pr edit <child> --base main`
  2. `gh pr merge <base> --squash --delete-branch`
  3. `git rebase --onto origin/main <old-base-tip> <child-branch>` (drops the
     already-squashed base commits) + `git push --force-with-lease`
  4. merge the child.
- **If already auto-closed**: the head branch survives — rebase as above,
  `gh pr create` fresh, comment "Superseded by #new" on the closed one.
- **Nothing tells you this happened.** The auto-close is silent: no failed
  check, no notification, and the PR list just looks one shorter. claude-plugins
  #2049 sat stranded for a day; a sweep then found 26 dead branches, two carrying
  work that had **never had a PR opened at all** (so no event ever fired for
  them either). A scheduled sweep is the only thing that finds this class —
  an event handler on `pull_request: closed` is too late by construction (the
  base ref is already deleted, so the reopen window is gone) and is blind to
  never-PR'd branches. `claude-plugins scripts/check-stranded-work.sh` is the
  encoded audit; it takes `--repo`, so one run sweeps the portfolio.
- **Telling an accident from a decision**: a closed-unmerged PR whose base ref
  **404s** was auto-closed; one whose base ref is still **alive** was closed by a
  human (duplicate/superseded). That single check is the discriminator — 11 of
  those 26 branches were deliberate closes and must not be resurrected.

## 3. Stacked-chain merges: push by SHA, never `HEAD:` — and expect auto-close races

Working down a stacked-PR chain (retarget child → merge base → rebase child →
force-push → merge, per #2) has several traps of its own (observed 2026-07,
claude-plugins #1979→#1987):

- **`HEAD:` in a push refspec is a race in a shared checkout.** HEAD is
  process-global repo state; a coworker session can move it *between two of
  your Bash calls*. Observed: rebase left HEAD at the child's new tip; by the
  next call HEAD was `main`'s tip, so `git push --force-with-lease origin
  HEAD:<child-branch>` overwrote the branch with main. Resolve the tip to an
  **explicit SHA in the same command that creates it** and push
  `git push --force-with-lease origin <sha>:refs/heads/<branch>`.
- **Brace that variable — `"$sha:<branch>"` is a zsh word-modifier expansion.**
  Stock zsh (reproduces under `zsh -f`) eats the character after the colon as a
  history modifier whenever it happens to be one, silently rewriting the
  refspec the bullet above just told you to use:

  | Written | zsh actually sends | |
  |---|---|---|
  | `"$sha:refs/heads/x"` | `<sha>efs/heads/x` | `:r` |
  | `"$sha:feat/x"` | `at/x` | `:f`+`:e` |
  | `"$sha:chore/x"` | `<sha>hore/x` | `:c` |
  | `"$sha:test/x"` / `release/` / `ci/` / `hotfix/` / `refactor/` | mangled | `:t :r :c :h :r` |
  | `"$sha:style/x"` | **hard error** `bad substitution` | `:s` |
  | `"$sha:fix/x"` / `docs/` / `perf/` / `build/` / `main` | correct | not modifiers |

  Half the conventional-commit prefixes break and half don't, which is why it
  reads as a baffling one-off instead of a rule. Always
  `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`. Observed
  2026-08 pushing `feat/justfile-pr-triage`: `src refspec <sha>efs/heads/… does
  not match any` — the error names a ref you never typed, so it looks like a
  stale SHA rather than a quoting bug.
- **Spell the destination `refs/heads/<branch>`, always.** A `<sha>:<branch>`
  refspec works only when `<branch>` **already exists on the remote**: git has a
  bare commit object on the left, so there is no ref namespace to infer the
  destination from, and it refuses rather than guessing — `error: The
  destination you provided is not a full refname (i.e., starting with
  "refs/")`. git wraps that message right after `(i.e.,`, so triage by grepping
  the `not a full refname` fragment, not the whole sentence. The full refname
  is accepted whether or not the branch exists, so there is no branch state to
  reason about. It compounds with the brace rule immediately above rather than
  replacing it: `"$sha:refs/heads/x"` is the `:r` word-modifier row in that
  table — unbraced, zsh silently sends `<sha>efs/heads/x`.
- **An empty-diff force-push auto-closes the PR — and a closed PR whose *head*
  moved after closing cannot be reopened.** Sibling of #2's
  base-branch-deleted variant. GitHub saw the branch == main, closed the PR,
  and refused `gh pr reopen` because the head ref had moved since closing.
- **A single mergeability read after a force-push is a race.** GitHub
  recomputes `mergeable` asynchronously; `gh pr merge` right after a push
  fails with "not mergeable" on a perfectly clean PR. Poll
  `gh pr view <n> --json mergeable` until it leaves `UNKNOWN`.
- **Waiting for CI races check *registration*, not just completion.** A loop on
  "zero pending checks" can exit **immediately** after a push/`update-branch`:
  zero pending is trivially true before the jobs are registered. Observed
  2026-07: `state=CLEAN` on a **single** check while three CI jobs had not yet
  appeared — merging there merges untested. Gate on **both** nothing-pending
  **and** `--jq 'length'` ≥ the expected check count. Same root cause as the
  mergeability race above: an async field read once, too early.

- **Check** before every force-push: `git log --oneline origin/main..<sha>` —
  expect *exactly* the child's commits, nothing more, never empty.
- **Recovery** when auto-closed: the rebased commits survive in local objects
  (`git reflog`) — `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`,
  open a fresh PR from the branch, comment "Superseded by #new" on the closed
  one. The full refname matters most here: the branch may not exist on the
  remote yet, and the short form cannot create it.

## 4. A red PR may still be mergeable — `UNSTABLE` is not `BLOCKED`

`mergeStateStatus` separates **required** failing checks (`BLOCKED` — merge
refused) from merely-present ones (`UNSTABLE` — plain `gh pr merge` works), so
`--admin` on an `UNSTABLE` PR takes a privilege you didn't need. Read it first.

Merging over red needs **two** checks: `--json files` (config/docs can't break
a compile) **and** the same check already failing on `main`. Either alone is a
guess — and a stale-green `main` lies, so check `createdAt` (2026-07: a "green"
run was 21 days old; main hadn't compiled for three weeks).


## 5. A **negated** closing keyword still closes the issue

GitHub matches `close|fixes|resolves|…` + an issue reference without parsing the
sentence around it, so the natural way to *disclaim* closure closes the issue.
Markdown emphasis between verb and number doesn't break the match either:

```
Does **not** close #162   →   GitHub reads `close #162`, and closes it
```

- **Check**: `gh issue view <n> --json closedByPullRequestsReferences` names the
  closer; a `closedAt` one second after a merge is automation, not a decision.
- **Fix**: never let a closing verb precede an issue number you don't mean to
  close — `Related: #162`, `Unblocks #162`, or `#162 stays open — it needs …`.
- **Recovery**: `gh issue reopen` works (nothing was deleted, unlike #2), then
  comment so the next reader doesn't re-derive it.

### It is not only negation — plain past tense in a follow-ups section does it

The rule above reads as "watch out for the word *not*". The trap is wider: **any**
closing verb adjacent to a reference matches, including one merely *describing*
what already happened, and including a reference wrapped in a **markdown link**.

> Observed 2026-08-16 (comfyui-nodes fleet). A PR body's follow-ups section
> asked for an issue to be re-opened, describing it as one this bug had
> **closed** on a false premise. GitHub matched the closing verb against the
> bracketed cross-repo link that followed it and closed the issue on merge — a
> line whose entire purpose was to request a re-open. The author had cited this
> very rule earlier in the same session.

Three amplifiers:

- **A bracketed cross-repo link still matches.** A closing verb followed by a
  markdown-linked `owner/repo#N` is a match, and a naive audit regex like
  `keyword\s+[\w./-]*#\d+` misses it on the `[` — then reports the body clean.
- **A shared fleet body multiplies it.** The same text went into 13 sweep PRs, so
  13 merges each targeted the same issue.
- **The actor is *you*, not a bot** — the timeline reads `closed by <you>` seconds
  after the merge. Don't rule out a closing keyword because no bot appears.

### And not only assertion — a keyword you are *quoting* still fires

The two forms above are sentences that *mean* something about an issue. The
third means nothing about it at all: the keyword appears inside an **example, a
fixture, or a regex you are documenting**. GitHub does not care that the line is
inside backticks, a code fence, or a sentence whose subject is the audit itself.

> Observed 2026-08-17 (FVH `infrastructure` #2213). A PR body's verification
> section reported that a closing-keyword scan returned zero hits, and quoted
> its two control fixtures inline as evidence. The scan it was reporting on had
> genuinely passed — on the *ADR file*. Run against the PR body, the same regex
> matched the body's own worked examples, which would have closed an unrelated
> issue on merge. Caught only because the scan was re-run against the artefact
> about to be published, rather than the one it was describing.

Two things generalise:

- **Scan the artefact you are about to publish, not the one you were auditing.**
  A PR body, an issue comment, and a rules file each need their own pass; a clean
  result on one says nothing about the others.
- **Do not reproduce the fixture in prose that ships.** Describe it — "control-
  tested against a bare reference and a bracketed cross-repo link, both found" —
  and keep the literal strings in the throwaway file. Documenting the trap is
  the one context where you are *guaranteed* to type the trap.

**Audit the body before merging, with a control.** Scan every PR you are about to
merge for a closing verb adjacent to an issue reference, allowing an optional
`[` and an optional `owner/repo` between them, and prove the scan works by
confirming it finds a reference you *know* is there. A negative from an
unvalidated regex is worth nothing — the first audit run in the case above
reported the fleet clean.

The damage is a **false status report**: 2026-08-05, a PR body written to
disclaim closure closed loractl #162 at merge, and the session reported it open
for two turns afterward. Like #2, GitHub does this silently — only re-reading
issue state from the API catches it.
