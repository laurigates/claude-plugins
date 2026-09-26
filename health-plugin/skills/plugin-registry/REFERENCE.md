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

## A capability declared in a registry is not proof it reached the installed copy

Promoted from the always-loaded `registry-declared-capability-not-installed.md`
portfolio rule, whose stub keeps the gate line.

When a capability is declared in an upstream **registry** (a marketplace index,
a catalog, a manifest you did not author) but the runtime reads it from the
**installed artifact**, the install step is a silent lossy boundary. The
registry entry is complete and correct, the installed copy is missing the block,
and the runtime — reading only the installed copy — reports nothing at all.

**The failure mode is absence, not error.** A missing capability looks exactly
like a product that never had the feature: no warning, no failed check, no
string to search for. The first hypothesis is "this build doesn't support it",
which is unfalsifiable from the surface and sends the diagnosis to the wrong
layer.

> Canonical break (2026-08, Claude Code 2.1.246). Every official `*-lsp` plugin
> declares its server **only** in the marketplace's `marketplace.json`:
> ```json
> "rust-analyzer": { "command": "rust-analyzer", "extensionToLanguage": { ".rs": "rust" } }
> ```
> The LSP manager reads `lspServers` from the **installed** plugin's
> `.claude-plugin/plugin.json`, which ships with only name/description/version/
> author. So the manager starts, finds nothing, and logs
> `getAllLspServers returned 0 server(s)`. No server spawns, no `LSP` tool is
> registered, and 5 of 6 installed plugins were affected. Open upstream since
> **2025-12** (anthropics/claude-code#15148, anthropics/claude-plugins-official#379);
> the fix PR was closed **unmerged**. Diagnosed only by asking what the runtime
> reads, after the binary's own strings had already sent the diagnosis down a
> false path.

### The check

**Read what the runtime reads, not what the catalog declares**, and diff them.
Two moves, in order:

1. **Find the loader's own count.** Most runtimes have a debug category that
   prints it. That single number separates "not supported" from "supported,
   loaded nothing":

   ```sh
   claude -p "hi" --debug lsp --debug-file /tmp/d.log   # then grep the log
   ```

   `returned 0` with the feature enabled is the whole diagnosis.

2. **Compare the two descriptions.** The registry entry and the installed
   artifact are different files; open both.

   ```sh
   jq '.plugins[] | select(.name=="<p>") | .lspServers' ~/.claude/plugins/marketplaces/<mp>/.claude-plugin/marketplace.json
   jq '.lspServers' ~/.claude/plugins/cache/<mp>/<p>/<ver>/.claude-plugin/plugin.json
   ```

**Do not diagnose from the runtime's binary.** Grepping the executable for the
declared value (a command name, a key) finds nothing when the value legitimately
comes from config — which reads as "this build has no such feature" and is
wrong. That inference cost a wrong verdict in the canonical break above.

`returned 0` is a negative that gates an action — control-test it
(`agent-patterns-plugin:tool-result-traps`).

### The repair has two halves

1. **Write the block into the artifact the runtime reads**, and
2. **make it self-healing**, because the installer re-wipes the installed copy on
   every update — the fix has a lifetime of one `update` command otherwise.

**Derive the payload from the registry at repair time; never hand-copy it.** A
transcribed block drifts from upstream silently and re-creates the same class of
bug one layer down. Read it out of the registry file on each run, so a changed
command or an added entry propagates on its own.

### When it bites

- A plugin/extension capability that "isn't supported" — check whether it is
  declared upstream and simply never installed.
- Any two-file arrangement where **you author neither file**: catalog + install,
  lockfile + vendored tree, image manifest + running container.
- Reasoning about a capability from **documentation or source** rather than from
  the installed copy. Both describe intent; only the installed copy runs.

Relatives of the same law: an MCP server whose handler implements a parameter
its declared `inputSchema` omits (there both files are yours and the fix is to
declare it); a GitHub Actions workflow whose declared triggers say nothing about
whether it is disabled; and a tool migration, where removal is gated on a
positive *operational* signal rather than config presence
(`migration-patterns-plugin:tool-migration-cutover`).

## Upstream

- [anthropics/claude-code#87667](https://github.com/anthropics/claude-code/issues/87667)
  — a project entry pinned to an older version loads in preference to the user
  install, and the plugin list renders both rows identically. Carries the
  session-start sync mechanism, the `claude plugin details` blind spot, and the
  uninstall-rewrites-settings behaviour described above.
