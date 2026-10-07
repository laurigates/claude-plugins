# Monorepo Troubleshooting

Moved verbatim from `SKILL.md`. Read when one package's release PR is missing or its extra file carries the wrong version.

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

For single-repo troubleshooting (no PR created at all, version not bumping,
CI not running on the release PR), see `configure-plugin:configure-release-please`.
