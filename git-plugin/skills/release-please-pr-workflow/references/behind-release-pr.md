# Merging a Release PR That Is `BEHIND`

Read this when a release-please PR shows `mergeStateStatus: BEHIND`, or when
`gh pr merge` fails with *"the head branch is not up to date with the base
branch"*.

`BEHIND` means the PR has no conflicts but its branch lacks commits that landed
on the base, and branch protection requires an up-to-date branch. Bring the
branch up to date, let its checks run on the new head, and merge pinned to that
head:

```bash
gh pr update-branch <N>
sha=$(gh pr view <N> --json headRefOid --jq .headRefOid)   # the new head
gh pr checks <N> --watch                                    # checks on the new head
gh pr merge <N> --squash --delete-branch --match-head-commit "$sha"
```

`--match-head-commit` refuses the merge if the head moved after the checks ran,
for example when a release-please run rewrote the branch in the meantime.
`gh pr checks --watch` can exit early before the new head's checks register;
`github-actions-plugin:gh-workflow-monitoring` has the wait-for-registration guard.

A `DIRTY` / `CONFLICTING` release PR does not take this path: close it and let
release-please recreate it (SKILL.md § Handle Conflicts,
[stuck-conflicting.md](stuck-conflicting.md)).

**Not verified:** whether `--match-head-commit` after `update-branch` is the
right guard for every release-please configuration. The flow was observed once
(laurigates/foundryvtt-mcp#328, 2026-11-24).
