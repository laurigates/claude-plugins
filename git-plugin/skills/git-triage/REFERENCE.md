# git-triage: Reference

Supplementary patterns for `/git:triage`, loaded on demand. The workflow itself
is in [SKILL.md](SKILL.md).

## Bot dependency PRs

### Re-read CI by head SHA after a bot rebase

Renovate and Dependabot rebase by force-pushing. The PR's check list can keep
showing the run from the **pre-rebase** SHA, so a PR reads red (or green) for a
commit that is no longer its head. Before categorizing a bot PR as `needs-fix`,
confirm the run belongs to the current tip:

```bash
gh pr view <n> --repo $REPO --json headRefOid,headRefName --jq '"\(.headRefOid) \(.headRefName)"'
gh run list --repo $REPO --branch <headRefName> --json headSha,workflowName,conclusion,createdAt --jq '.[] | select(.headSha == "<headRefOid>")'
```

If no run exists for the current head SHA, CI has not run on it yet. Trigger it
(for example with an empty commit, if the repo allows pushes to bot branches)
instead of reporting the stale result.

### A pin PR can smuggle a minor bump

With Renovate `rangeStrategy: "pin"` plus `group:allNonMajor`, a
"chore(deps): pin dependencies" PR pins each package to whatever the registry
resolves today. That can be a **newer minor** than `main` currently locks, so a
PR titled as a no-op pin carries a real upgrade.

The tell is the failure mode. A pin PR that fails the frozen-lockfile install
is the lockfile trap described in SKILL.md Step 4. A pin PR that installs
cleanly and then fails type checking or tests has probably pulled in a breaking
minor (observed: a React flow library's 12.10 to 12.11 bump changed a callback's
generic signature).

Split it rather than fixing the upgrade inside the pin PR:

1. In the pin PR, pin the offending package back to the version `main` resolves.
2. Add a `renovate.json` guard that holds it there, referencing a tracking issue:

   ```json
   {
     "packageRules": [
       {
         "matchPackageNames": ["<pkg>"],
         "allowedVersions": "<x.y.z",
         "description": "Hold until #<issue>: <why the upgrade breaks>"
       }
     ]
   }
   ```

3. Open the tracking issue for the upgrade. When the guard is removed, Renovate
   proposes the bump as its own PR, where the breakage can be reviewed on its own.
