# A Release PR Stuck `CONFLICTING` After a Non-Releasable Commit

Read this when a release-please PR shows `CONFLICTING` and the next
release-please run does not update it.

A release PR can go `CONFLICTING` and stay there when a non-releasable commit
(`chore:`, `docs:`, `ci:`) lands on the base and changes a file the PR also
changes. That commit gives release-please no new release to compute, so the
next run does not update the PR branch. Close the PR with its branch and re-run
the workflow, which opens a clean PR:

```bash
gh pr close <N> --delete-branch --comment "Closing for recreation: conflicted with a non-releasable commit on main"
gh run rerun <release-please-run-id>   # or: gh workflow run release-please.yml
```
