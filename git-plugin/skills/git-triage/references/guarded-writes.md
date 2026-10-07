# Step 7: Optional Writes (guarded)

Moved verbatim from `SKILL.md`. Read only when `--auto-close` or `--auto-merge` was passed.

### Step 7: Optional writes (guarded)

If `--auto-close` was set and any issue is `implemented` or `stale`, ask before acting:

```
AskUserQuestion("Close N issues?", options=[
  "Yes — close all implemented + stale",
  "Implemented only",
  "Stale only",
  "No, report only"
])
```

For each selected issue:
```bash
gh issue close <n> --repo $REPO --comment "Closing as <category>.

Evidence: <short summary + cross-link PR>

Triaged by /git:triage on <date>."
```

If `--auto-merge` was set and any PR is `ready-to-merge`, ask similarly. Merge with:
```bash
gh pr merge <n> --repo $REPO --squash --auto
```
(`--squash` is the repo default for this project; for other repos, read `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` and pick the first allowed strategy.)
