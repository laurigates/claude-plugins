---
name: plugin-registry
description: "Claude Code plugin registry structure, install scopes, and version lag. Use when troubleshooting plugin problems, a stale plugin version in one project, or fixing registry entries."
user-invocable: false
allowed-tools: Bash(jq *), Bash(cp ~/.claude/plugins/installed_plugins.json *), Bash(claude plugin list *), Bash(bash ${CLAUDE_SKILL_DIR}/../health-plugins/scripts/check-registry.sh *), Bash(bash ${CLAUDE_SKILL_DIR}/../health-plugins/scripts/fix-registry.sh *), Read, Edit, Glob, Grep, TodoWrite
created: 2026-02-04
modified: 2026-11-12
compatibility: claude-code
reviewed: 2026-11-12
---

# Claude Code Plugin Registry

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Plugin shows "installed" but isn't working | Setting up new plugins (`configure-plugin:configure-claude-plugins`) |
| Need to understand plugin scopes | Configuring plugin permissions (`health-plugin:settings-configuration`) |
| Fixing orphaned registry entries | Running the registry diagnostic and fix (`health-plugin:health-plugins`; for the user, `/health:check --scope=registry`) |
| Debugging installation failures | |
| A declared capability (LSP server, hook, command) silently never loads — see [REFERENCE.md](REFERENCE.md) § A capability declared in a registry is not proof it reached the installed copy | |

## Registry Location

`~/.claude/plugins/installed_plugins.json` (the root moves with `CLAUDE_CODE_PLUGIN_CACHE_DIR`) records every install across all projects; plugin files live under `cache/`. Official reference: [plugin loading](https://code.claude.com/docs/en/plugins/loading), "Find plugins on disk".

## Registry Structure (v2)

```json
{
  "version": 2,
  "plugins": {
    "plugin-name@marketplace-name": [
      {
        "scope": "project",
        "projectPath": "/path/to/project",
        "installPath": "~/.claude/plugins/cache/marketplace/plugin-name/1.0.0",
        "version": "1.0.0",
        "installedAt": "2024-01-15T10:30:00Z",
        "lastUpdated": "2024-01-15T10:30:00Z",
        "gitCommitSha": "abc123"
      }
    ]
  }
}
```

Each plugin key maps to an **array** of installations (supporting multiple scopes). Entries are version pointers into the shared cache, not plugin copies ([REFERENCE.md](REFERENCE.md) § The registry holds version pointers, not plugin copies).

`scope` is `user`, `project` or `local`; `project` and `local` entries also carry `projectPath`. The per-field table, re-read from a live registry, is in [REFERENCE.md](REFERENCE.md) § Field reference.

## Installation Scopes

`--scope` names the settings file whose `enabledPlugins` the command writes:

| Scope | Command | Settings file | Reaches |
|-------|---------|---------------|---------|
| `user` (default) | `claude plugin install my-plugin@marketplace` | `~/.claude/settings.json` | You, in every project |
| `project` | `claude plugin install my-plugin@marketplace --scope project` | `.claude/settings.json` | Everyone who clones the repo; each person also installs in their own clone |
| `local` | `claude plugin install my-plugin@marketplace --scope local` | `.claude/settings.local.json` | You, in this repo only |

When scopes disagree, `local` overrides `project`, which overrides `user`, and managed settings override everything (official plugin loading reference, "Find where a plugin is enabled").

A project entry can also appear with no install command run: a session-start sync adds one per plugin the committed `.claude/settings.json` enables that is installed at user scope, recorded at the then-current version ([REFERENCE.md](REFERENCE.md) § Session-start sync creates project entries).

## Known Issue: #14202

[anthropics/claude-code#14202](https://github.com/anthropics/claude-code/issues/14202) is **open** as of 2026-10-30: after a `--scope project` install in one project, other projects were reported (on 2.0.70) to show the plugin as "(installed)" and refuse to install it, while it does not load there. The refusal did not reproduce on 2.1.322; details in [REFERENCE.md](REFERENCE.md) § Known issue #14202.

An "already installed (scope: project)" message exits `0`, so check `claude plugin list --json` for a row with your `projectPath`. Try `--scope local` (it installed cleanly on 2.1.322) before § Last resort: edit the registry by hand.

## Which Install Loads, and Why a Project Can Run an Old Version

When a plugin has both a project entry for the current directory and a user
entry, **the project entry decides which cached version loads there**, and it
does not follow the user install's updates, so a project can run a version
behind the rest of the machine. `claude plugin details` reports the **user**
version from inside such a project; `claude plugin list --json` reports each
row's `scope` but not which row wins. The reliable read is the debug log:

```bash
CLAUDECODE= claude -p "reply ok" --debug plugins --debug-file /tmp/p.log
```

Then read its `skillsPath:` lines for the version actually loaded.

`/health:check` runs `check-plugin-scope-lag.sh`, which lists every project-scope
entry below its user-scope version as a `scope_lag` WARN.

Removing a lagging row is a **repair, not a fix**: the next session in that project re-creates it. The measured evidence, the lag query, and the uninstall-rewrites-committed-settings hazard are in [REFERENCE.md](REFERENCE.md).

## Fixing Registry Issues

Find orphaned entries (a `projectPath` whose directory is gone) with the diagnostic, not by testing each path by hand:

```bash
bash ${CLAUDE_SKILL_DIR}/../health-plugins/scripts/check-registry.sh --verbose
```

Prefer the CLI and the bundled fix script, and confirm with the user before any write.

| Task | Use |
|------|-----|
| Remove orphaned entries | `bash ${CLAUDE_SKILL_DIR}/../health-plugins/scripts/fix-registry.sh [--plugin <name>] [--dry-run]` (timestamped backup, JSON validation, aborts on error) |
| Plugin needed in this project | `claude plugin install <plugin>@<marketplace> --scope project` (or `--scope local`), run from the project |
| Make a project-only plugin global | `claude plugin install <plugin>@<marketplace>`, then `claude plugin uninstall <plugin>@<marketplace> --scope project` from the project |
| Remove a lagging project row | `claude plugin uninstall <plugin>@<marketplace> --scope project`, with the snapshot-restore steps in [REFERENCE.md](REFERENCE.md) § Removing a lagging row rewrites the project's committed settings |

A project-scope uninstall also rewrites the committed `.claude/settings.json`. Install and uninstall are not pre-approved here, so each goes through the normal permission flow. Verify by re-reading the registry or `claude plugin list --json`; an exit code alone does not prove the row changed.

### Last resort: edit the registry by hand

Only when neither the CLI nor `fix-registry.sh` can make the change, such as a row whose `projectPath` no longer exists for a case the script does not cover, or the #14202 refusal with no other scope working:

1. Back up first, every time:

   ```bash
   cp ~/.claude/plugins/installed_plugins.json ~/.claude/plugins/installed_plugins.json.backup
   ```

2. Read the file, then make the smallest change with the Edit tool: drop one array element, or add one element copied from an existing entry with `scope` and `projectPath` changed.
3. Validate: `jq empty ~/.claude/plugins/installed_plugins.json` must exit 0. If it does not, restore the backup.
4. Run `/reload-plugins` or start a new session, then re-run the diagnostic.

## Project Settings Integration

Project-scoped plugins also need a key in `.claude/settings.json`: `enabledPlugins` is an **object** mapping `plugin@marketplace` to a boolean (`{"enabledPlugins": {"plugin-name@marketplace": true}}`), not an array of names. `claude plugin install --scope project` writes this key itself. Without it, even a correctly registered project-scoped plugin won't load.

## Troubleshooting Checklist

1. **Plugin shows installed but doesn't work**: check that `projectPath` matches the current directory and `.claude/settings.json` has the `enabledPlugins` key, then run the registry diagnostic (`health-plugin:health-plugins`; for the user, `/health:check --scope=registry`)

2. **Can't install plugin (already installed)**: look for an existing entry with a different `projectPath`; try `--scope local`, then § Last resort: edit the registry by hand

3. **Plugin works in one project but not another**: likely project-scoped; install it in the other project, or at user scope

4. **A skill or command is missing in one project only, or behaves as an older version**
   - Suspect a project entry lagging the user install — run the lag query in [REFERENCE.md](REFERENCE.md) § Find rows that lag their user install
   - Confirm with `--debug plugins` and read the `skillsPath:` version
   - `claude plugin details` reports the user version here and will mislead you

5. **Registry file is corrupted**: Claude Code keeps a dated `installed_plugins.unreadable.*.kept` copy when it rebuilds an unreadable registry; restore a backup, or reinstall with `claude plugin install`

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View registry | `jq -c . ~/.claude/plugins/installed_plugins.json` |
| List plugins | `jq -r '.plugins \| keys[]' ~/.claude/plugins/installed_plugins.json` |
| Check specific | `jq '.plugins."name@market"' ~/.claude/plugins/installed_plugins.json` |
| Project-scoped rows | `jq '.plugins \| to_entries[] \| .value[] \| select(.scope=="project") \| {projectPath, version}' ~/.claude/plugins/installed_plugins.json` |
| Installs per scope | `claude plugin list --json` |
| Orphan diagnostic | `bash ${CLAUDE_SKILL_DIR}/../health-plugins/scripts/check-registry.sh` |

Keys are `{plugin-name}@{marketplace-name}`. After any registry change, run `/reload-plugins` or start a new session for it to load.
