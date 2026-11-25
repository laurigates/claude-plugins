# Monorepo Troubleshooting

Moved from `SKILL.md`; the Recovery section opens with a new two-line pointer to the cause, and the rest is unchanged. Read when one package's release PR is missing, its extra file carries the wrong version, or a merged grouped release PR was never tagged and every run aborts.

## Monorepo Troubleshooting

### One Package's PR Not Created (others fine)

Check:
1. Are there releasable commits scoped to that package path since its last
   component tag?
2. Does the commit scope match the package path?
3. Is the package's `component` set and unique?

### Wrong Version in a Package's Extra File

Ensure the package's `extra-files` paths are relative to the **package
directory**, not the repo root (release-please prepends the package path):
```json
// Correct (package path is "my-package")
"extra-files": [{"type": "json", "path": ".claude-plugin/plugin.json", "jsonpath": "$.version"}]
```

### Recovery: Unwedge an Already-Merged Untagged PR

The cause, a custom title pattern on a grouped release PR, is in `SKILL.md`
§ Common Failure: Merged Release PR Never Tagged.

Once a grouped release PR has merged with a bare title, dropping the config fixes
future runs but the **already-merged** PR is still stuck at `autorelease: pending`,
so runs keep aborting. Relabel it to `autorelease: tagged` so release-please stops
treating it as outstanding, then dispatch a fresh run to cut the releases:

```bash
# Create the label first if the repo lacks it — release-please only
# auto-creates `autorelease: tagged` when it successfully tags a PR.
gh label create "autorelease: tagged" --color 2A7A2A --description "release-please tagged"

# Relabel the stuck merged PR
gh pr edit $PR_NUMBER --add-label "autorelease: tagged" --remove-label "autorelease: pending"

# Dispatch a fresh run — with no tags cut, it recomputes the same releases
# into a new, parseable release PR (or tags directly on the next merge).
gh workflow run release-please.yml
```

No tags were cut for the wedged PR, so release-please recomputes the identical set
of releases on the next run; the relabel only removes the "outstanding" blocker.

For single-repo troubleshooting (no PR created at all, version not bumping,
CI not running on the release PR), see `configure-plugin:configure-release-please`.

### Single-Package: `separate-pull-requests: false` Cuts No Release

Don't set `separate-pull-requests: false` at all in a single-package repo. The
"CORRECT" example in the SKILL.md section
[Common Failure: Merged Release PR Never Tagged](../SKILL.md#common-failure-merged-release-pr-never-tagged)
is for monorepos. With exactly one package, the code
defaults `separate-pull-requests` to `true` (`src/manifest.ts`; the manifest docs
say "absence defaults to false", which does not match). Setting it to `false`
forces the Merge plugin anyway: the PR is titled `chore: release main` (the
group default `chore: release ${branch}`) on a branch named
`release-please--branches--main` with **no component**. A `node` package takes
its component from `package.json`'s `name`, so the tagging pass logs
`PR component: undefined does not match configured component: <name>` and cuts
no release, even with no custom title pattern. The workflow job still reports
success, and the missed-release guard counts only feat/fix/perf/revert commits,
so it misses this too. Fix: delete `separate-pull-requests` (and any custom
title pattern) so release PRs are standalone (`chore(main): release X.Y.Z`).
Recovery for the stuck PR: run `release-please github-release --release-type
simple --target-branch main`. The simple strategy has no package name, so its
empty component matches the merged PR's branch, and it tags the release and
relabels the PR `autorelease: tagged`. Then attach any release assets by hand,
because the workflow's `release_created` jobs did not run. (Seen 2026-11-24 in
laurigates/foundryvtt-local-rest-api#18, fixed in #19, recovered as v2.1.0.)
