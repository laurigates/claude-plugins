# Monorepo Troubleshooting

Moved verbatim from `SKILL.md`. Read when one package's release PR is missing, its extra file carries the wrong version, or a merged grouped release PR was never tagged and every run aborts.

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
