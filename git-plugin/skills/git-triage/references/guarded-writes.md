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
gh pr merge <n> --repo $REPO --<method> --auto
```
(`<method>` is the `METHOD=` that `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pr-merge-method.py" --repo $REPO --pr <n>` prints — rebase by default, squash when there is a reason; rule table in `github-pr-title` → `merge-strategies.md`. If the repo disallows that method, `gh repo view --json squashMergeAllowed,rebaseMergeAllowed` shows which is allowed.)
