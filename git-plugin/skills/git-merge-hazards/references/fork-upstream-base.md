# A fork PR whose base is an open upstream PR's head

Skill-only (§2 pointer in [SKILL.md](../SKILL.md)). §2 covers a stacked child
whose base branch gets deleted. This file covers the reverse: a PR in your fork
whose base branch is also the head branch of an open PR against the upstream
repository.

## What goes wrong

Merging the fork PR advances its base branch, and that branch is the upstream
PR's head, so the upstream PR gains the merged commits. Nothing in your fork
marks that branch as shared: the merge reads as a local change, and the
outward-facing one, new commits on a third-party maintainer's review, happens as
a side effect.

> Observed (#3445): laurigates/dust#2 had base `feat/shared-blocks`, which was
> the head of both fork PR laurigates/dust#1 and the upstream draft
> bootandy/dust#645. Squash-merging #2 added commit 6e21b87 to bootandy/dust#645;
> the upstream PR's `updatedAt` matched the merge to the minute. Its description
> went stale until it was rewritten by hand.

A same-repo stack, where the base is another PR's head in the same repository,
is the ordinary case and not this hazard: everyone reviewing it is in that
repository.

## Check before merging

For any PR whose base is not the default branch, in a repository that is a fork:

```bash
gh api "repos/OWNER/REPO" --jq '{fork, parent: .parent.full_name, default_branch}'
gh pr list -R PARENT_OWNER/PARENT_REPO --head "OWNER:BASE_BRANCH" --state open --json number,title,url
```

Any row means the merge also updates that upstream PR. Say so before merging,
and merge only when updating it is intended. The parent is the one repository
this check reads; a PR against some other repository with the same head branch
is not covered, so search for one when the branch has been offered elsewhere
(`gh search prs --author @me --state open --json repository,number,headRefName`,
filtered on `headRefName`).

## What merge-chain.sh does

`scripts/merge-chain.sh` applies the same check to every PR before
`update-branch`. In a fork, a PR whose base is not the default branch and is the
head of an open PR in the parent is `SKIPPED` with
`REASON=base_is_upstream_pr_head`, naming the upstream PR, and the chain
continues. A failed read of the repository or of the parent's open PRs is
`ERROR`, never a pass. Outside a fork the check does not run.

## When updating the upstream PR is intended

Merge by hand with `gh pr merge`, then update the upstream PR's description to
cover the new commits, or tell its reviewers that they arrived.
