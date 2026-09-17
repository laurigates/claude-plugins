# Plugin Registry Reference

Detail for [`plugin-registry`](SKILL.md). Loaded on demand.

## Which install loads, and why a project can run an old version

When a plugin has both a project entry for the current directory and a user
entry, **the project entry decides which cached version loads there**. It does
not follow the user install's updates, so a project can quietly run a version
behind the rest of the machine.

Measured 2026-09-13 in one project, from `--debug plugins`:

```
Attempting to load skills from plugin git-plugin default skillsPath: …/git-plugin/2.54.2/skills
Attempting to load skills from plugin github-actions-plugin default skillsPath: …/github-actions-plugin/1.9.6/skills
Loaded 8 skills from plugin github-actions-plugin default directory
```

The user entries were on 2.55.0 and 1.10.0, and 1.10.0 carries 10 skills — so
two skills added in the newer version were unreachable in that project. In a
sibling project with no project entry, 2.55.0 loaded.

### `claude plugin details` cannot detect this

Run from that same directory it reported `github-actions-plugin 1.10.0` and
listed all 10 skills — the user version, not the one loading. `claude plugin
list` reports enablement, and `claude plugin list --json` reports `scope` per
row but does not say which row wins. The debug log is the reliable read:

```bash
CLAUDECODE= claude -p "reply ok" --debug plugins --debug-file /tmp/p.log
```

Then read the `skillsPath:` lines for the version actually loaded.

## Find rows that lag their user install

```bash
jq -r '.plugins | to_entries[]
  | ([.value[] | select(.scope == "user") | .version] | first) as $u
  | select($u != null)
  | .key as $k | .value[]
  | select(.scope != "user" and .version != $u)
  | [$k, .version, $u, .projectPath] | @tsv' ~/.claude/plugins/installed_plugins.json
```

An empty result is the healthy state. Rows whose version equals the user
install's are harmless — they are re-created every session and load the same
files.

## Removing a lagging row rewrites the project's committed settings

`claude plugin uninstall <plugin>@<marketplace> --scope project`, run from that
project, removes the row — after which the user-scope version loads there. It
**also edits that project's `.claude/settings.json`**: the documented
interactive behaviour is that uninstalling a plugin a project enables removes it
from the shared settings file, and a run observed 2026-09-13 in `gh-board`
dropped the plugin's `enabledPlugins` key and reordered the file's keys.

So treat the settings file as an output of the command:

1. Copy `.claude/settings.json` (and `settings.local.json`, if present) aside.
2. Run the uninstall from the project directory.
3. Restore both files byte-for-byte.
4. Confirm the row is gone by re-reading the registry — the command's exit code
   does not prove it.

For a row whose `projectPath` no longer exists (a deleted worktree), there is no
directory to run the command from; drop the entry from the registry with `jq`
after backing the file up.

### Removal is a repair, not a fix

The next session in that project re-creates the entry at the then-current
version, so the lag returns after the next plugin release. Measured on one
machine: a sweep on 2026-09-13 removed 462 project entries and left zero
lagging; by 2026-09-17 there were **19** lagging rows again (`feedback-plugin`
project entries at 1.12.1 against a user install on 1.12.2), because a release
landed in between.

The durable remedies are an upstream change — project entries following the user
install's updates, or not being created when a user install exists — and a
recurring check that reports the lag rather than a one-off cleanup.

## Upstream

- [anthropics/claude-code#87667](https://github.com/anthropics/claude-code/issues/87667)
  — a project entry pinned to an older version loads in preference to the user
  install, and the plugin list renders both rows identically. Carries the
  session-start sync mechanism, the `claude plugin details` blind spot, and the
  uninstall-rewrites-settings behaviour described above.
