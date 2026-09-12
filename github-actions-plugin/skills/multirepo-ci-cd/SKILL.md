---
name: multirepo-ci-cd
description: "Diagnose a CI failure or roll a workflow out across many repos. Use when debugging a red check in a multi-repo org, promoting a shared reusable-*.yml, or re-triggering a PR after a @main fix."
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-08-06
modified: 2026-09-12
reviewed: 2026-09-12
---

# Multi-Repo CI/CD Discipline

Org-agnostic lessons for working across a portfolio of repos that share
reusable workflows. The org-specific workflow catalogs live in the child rules
(`*/.claude/rules/ci-cd-workflows.md`).

## Diagnosing a CI Failure — Fetch First

Before investigating why a workflow failed, `git fetch` and compare local
`HEAD` against `origin/main`. In a multi-repo portfolio, local checkouts go
stale, and **the failing workflow file (or its config —
`release-please-config.json`, the manifest, a new `.yml`) may have been added
in commits you haven't pulled.** It won't exist in your local tree, so you'll
search for a "missing" file that CI is actively running. One `git fetch` +
`git log --oneline HEAD..origin/main` shows the gap; `git pull --ff-only`
syncs it. Diagnose against what CI actually ran, not a stale snapshot.

## Rolling a Workflow Out to a Repo Class

When promoting a self-contained workflow into a shared `reusable-*.yml` and
adding a thin caller to every repo of a class, three things bite if missed:

1. **IaC feature flags are the source of truth for the repo set.** Don't
   hand-list repos — derive the class from the gitops/Terraform definitions
   (e.g. `release_please = true` entries in `repositories.tf` *are* the
   membership list). Extract them rather than guessing which repos qualify:
   ```
   awk '/^    "[^"]+" = \{/ { match($0, /"[^"]+"/); name=substr($0, RSTART+1, RLENGTH-2) } /release_please[ ]*=[ ]*true/ { print name }' repositories.tf
   ```
2. **Land the reusable workflow on the `.github` repo's `main` first.**
   Callers pin `uses: <owner>/.github/...@main`, which resolves at dispatch
   time — a caller merged or dispatched before the reusable workflow exists on
   `main` fails. Merge the `.github` PR before opening (or at least before
   merging) the callers. `workflow_dispatch`-only callers are harmless until
   triggered, so they can be opened in parallel, but the `.github` change is
   the prerequisite.
3. **Bulk-create callers via the GitHub API, not local clones.** The caller
   body is identical across repos, and some repos may not be checked out
   locally. Creating the branch + file + PR through the API is uniform and
   immune to local working-tree state (stale checkouts, wrong branch,
   uncommitted changes):
   ```
   sha=$(gh api repos/<owner>/$r/git/ref/heads/main --jq .object.sha)
   gh api -X POST repos/<owner>/$r/git/refs -f ref=refs/heads/$BRANCH -f sha=$sha
   gh api -X PUT repos/<owner>/$r/contents/$PATH -f message=$MSG -f content=$B64 -f branch=$BRANCH
   gh pr create -R <owner>/$r --base main --head $BRANCH -a laurigates --title "$MSG" --body "$BODY"
   ```
   Loop sequentially (not a parallel batch — siblings cancel on the first
   non-zero exit), and skip a repo if the file already exists on `main`. Title
   the caller PR `ci:` so release-please does not cut a version bump for a
   CI-only change. When the running gh user is the repo owner, omit
   `--add-reviewer` (self-review is rejected 422).

## Bulk-*Read* Through the API Too — a Stale Checkout Produces Wrong Findings

The API-not-clones rule above is usually framed as a *write* discipline. It is
equally a **read** discipline: a portfolio-wide `rg`/`grep` over local
checkouts answers a question about *whatever each clone last fetched*, not
about the repos. In a side-by-side layout where most clones are touched rarely,
that answer is confidently wrong — and wrong in the direction of "this pattern
isn't used anywhere," because a checkout predating an adoption simply lacks it.

> Evidence (2026-07, ubuntu-slim runner sweep): a local `grep -rl` concluded
> **0 repos** called `reusable-release-please.yml` and all 29 inlined
> `googleapis/release-please-action` directly. That statement was made to the
> user as fact. `pal-mcp-server` had migrated to the reusable on the remote
> *weeks earlier*; the local clone was stale. Nothing about the grep output
> looked suspicious.

- **Read each file from origin in the same pass that patches it**:
  `gh api repos/<owner>/<repo>/contents/<path> --jq .content | base64 -d`.
  One fetch per repo is cheap and makes the finding and the edit agree.
- **Use the local checkouts only to *generate candidates*, never to state
  conclusions.** Enumerate broadly locally (it's fast), then confirm every
  claim against the remote before reporting or acting on it.
- **Make the patch function assert its precondition and raise.** The stale
  `pal-mcp-server` clone was caught only because the sweep's patcher demanded a
  `runs-on:` inside the named job and raised *"no runs-on found inside
  release-please job"* rather than falling through to a no-op or a mangled
  file. A silent `if found: patch` would have skipped it invisibly — and the
  wrong finding would have stood. Same instinct as
  `git-hazards.md`: a green run is not proof the content is right.
- Cross-check the repo set itself against the remote as well
  (`gh repo list <owner> --json name,isArchived,isFork`) — a local directory
  can be a fork, an archived repo, or have no remote at all.

## Landing a `@main` Reusable-Workflow Fix on an Existing PR — Re-Trigger, Don't Re-Run

After you merge a fix to a `reusable-*.yml` on the `.github` repo's `main`,
the open PRs whose callers pin `@main` do **not** pick it up by re-running the
failed check. **A GitHub re-run replays the original run against the workflow
resolution it was first dispatched with** — including the exact commit the
`@main` reusable workflow resolved to at that time. So `gh run rerun` /
"Re-run failed jobs" / the `rerun-failed-jobs` API all replay the *stale*
reusable workflow and fail identically, even though `main` is now fixed.

The tell: you read the re-run's log and it shows the *old* behaviour (the
command you just replaced still running), not your fix.

**Fix: force a fresh `pull_request` event**, which re-resolves `@main` at
dispatch time and picks up the merged fix. Cheapest first:

```
gh pr update-branch <n> -R <owner>/<repo>   # fires `synchronize`; no-op-safe if already current
```

If the branch is already current (update-branch reports "already up to date"),
close-then-reopen fires `reopened` instead:

```
gh pr close <n> -R <owner>/<repo> && gh pr reopen <n> -R <owner>/<repo>
```

For a **release-please** PR, prefer `update-branch` — closing the release PR is
safe (release-please acts on push-to-`main`/schedule, not PR-close events) but
reopening is noisier than a branch update. Avoid pushing to a release-please
branch by hand.

There is a second replay trap with the same shape: a `pull_request` re-run also
replays the original event payload, so its `sender` is whoever opened the PR —
a **bot** for Renovate/release-please PRs. Actions with a human-actor guard
(e.g. `anthropics/claude-code-action` without `allowed_bots`) therefore fail
with "Workflow initiated by non-human actor" on re-run **regardless of who
clicked re-run**. A fresh event doesn't change the sender (still the bot), so
the real fix is `allowed_bots` on the action, not re-triggering — but the same
"re-run replays the original payload" mechanic is why clicking re-run yourself
doesn't help. Both traps are the same root cause: a re-run is a replay, not a
new dispatch.
