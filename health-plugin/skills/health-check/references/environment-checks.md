# health-check: environment checks (Step 1)

## Interpreting the 1a script output

If `check-settings.sh` emits `PROJECT_DIR_RESOLVED=<path>`, the workspace root had no `.claude/` but a single nested `*/.claude/settings.json` was found one level down (parent-workspace / monorepo layout). Note the resolved path in the report so the user knows which config was checked. If it emits `PROJECT_DIR_HINT=<msg>`, surface the hint — multiple nested configs were found and the user should re-run with `--project-dir` to target one.

`check-mcp.sh` walks `.mcp.json` from `--project-dir` up through its ancestors, stopping after `--home-dir` or the filesystem root, because Claude Code also loads `.mcp.json` from parent directories (issue #2666). It emits `MCP_SOURCE_COUNT=<n>` as the denominator for the `MCP_SOURCES:` block and one `SERVER: name=<n> file=<path>` line per server, so the report can name the file each server came from. A server name defined at more than one level is counted once against the nearest file; the outer copy is reported as `SERVER_SHADOWED: name=<n> file=<outer> shadowed_by=<nearer>`. Surface the source file (and any shadowing) in the report — parent-provided servers still need per-project approval via `enabledMcpjsonServers`.

`check-plugin-scope-lag.sh` compares every project-scope entry in `installed_plugins.json` with the user-scope entry of the same plugin, using a semver-aware sort (`sort -V`, so 2.9.0 < 2.10.0). Each project-scope install below the user-scope version is one `SEVERITY=WARN TYPE=scope_lag` row naming `PLUGIN=`, `PROJECT=`, `PROJECT_VERSION=` and `USER_VERSION=` (issue #3220). There is no allowlist: a deliberate pin also warns. Equal versions, a project pin newer than user scope, and a plugin with no user-scope entry are not findings; a missing registry or missing `jq` yields `STATUS=OK`. A lagging project keeps loading the old build after a user-scope update, so a fix that has shipped does not reach it. Report each row with the project path and both versions, and point to the `plugin-registry` skill (§ Which Install Loads, and Why a Project Can Run an Old Version) for confirming which version loads and repairing the entry. The check is read-only.

`check-hooks.sh` inventories settings hooks (`~/.claude/settings.json`, `<project>/.claude/settings.json` and `<project>/.claude/settings.local.json`; `~/.claude/settings.local.json` is local scope for the home directory, so it counts only when the project is the home directory) and the hooks of every enabled plugin. Every plugin in `installed_plugins.json` is a candidate: `enabledPlugins` merges local over project over user, a plugin set to `false` is dropped, and a plugin with no entry at any scope falls back to its manifest `defaultEnabled` (default `true`), the same rule the usage scope applies. Each plugin is read from the one install that loads in this project: the project/local-scope entry in `installed_plugins.json` for this project if there is one, otherwise the user-scope entry. Its `<installPath>/hooks/hooks.json` is read, plus the `plugin.json` `hooks` field (a path, an inline event map, or an array of either). `HOOK_COUNT=` is the total, split into `SETTINGS_HOOK_COUNT=` and `PLUGIN_HOOK_COUNT=`. `PLUGINS_ENABLED=` counts enabled plugins with an install on disk, which is what `check-usage.sh` reports under the same key. `PLUGINS_UNRESOLVED=` counts plugins set to `true` with no install for this project (`--verbose` names them as `PLUGIN_UNRESOLVED:`); the registry scope reports those, not this check. Every `ISSUES:` row carries `SOURCE=settings` or `SOURCE=plugin:<name@marketplace>` plus `FILE=`. Finding types: `unknown_event` (not in the documented event list; Claude Code skips it, so its hooks never fire), `unknown_hook_type` (not `command`/`http`/`mcp_tool`/`prompt`/`agent`, or missing), `missing_command` (the first word is neither on PATH nor a file; for `bash`/`sh`/`zsh <script>`, the absolute script path does not exist), `missing_hooks_file`, `invalid_hooks_file` (not JSON, or no top-level `"hooks"` key), `ms_timeout` (1000 or more), and `high_timeout` (above `LIMIT=`: 300 s for `SessionStart`/`Setup`, 60 s otherwise). Report each finding with its `SOURCE` and `FILE`.

### 1d. Permissions coverage (`check-permissions-coverage.sh`)

The script compares the commands a project's task files run with the Bash allow rules Claude Code would apply, so the report shows which recipe commands will prompt.

| Input | What is read |
|---|---|
| Allow rules | `permissions.allow` in `~/.claude/settings.json`, `<project>/.claude/settings.json` and `<project>/.claude/settings.local.json` (each reported as `<KEY>=OK\|MISSING\|INVALID`). `~/.claude/settings.local.json` is local scope for the home directory: Claude Code reads it only in a session started there, so it counts only when `--project-dir` is the home directory, as that project's local file |
| Rule forms | `Bash(<prefix> *)`, the legacy `Bash(<prefix>:*)`, any rule with `*` elsewhere, and bare `Bash` / `Bash(*)` (`BASH_ALLOW_ALL=true`). A trailing ` *` that is the only wildcard also matches the bare command |
| Commands | `justfile` / `Justfile` recipe lines, `Makefile` TAB-led recipe lines, `.pre-commit-config.yaml` `entry:` values (`SCANNED_FILES=`) |

Each line is split on `&&`, `||`, `;` and `|` outside quotes. A quoted string that continues onto later lines, a here-document body, a `#` comment and an `x=$(...)` substitution are skipped. The wrappers Claude Code strips before matching (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`) are dropped. Claude Code also strips a leading assignment of "certain known-safe environment variables" but does not publish the list; the docs name only `NODE_ENV`, so the script drops `NODE_ENV=…` and keeps any other assignment in the matched text (`FOO=1 npm test` is missing under `Bash(npm test *)`, because an allow rule does not match past it). Commands in Claude Code's built-in read-only set (`ls`, `cat`, `echo`, `pwd`, `head`, `tail`, `grep`, `find`, `wc`, `which`, `diff`, `stat`, `du`, `cd`) and shell keywords are not counted. A rule for one subcommand does not cover another: `Bash(npm run *)` leaves `npm install` missing.

| Key / row | Meaning |
|---|---|
| `TOOLS_FOUND=` / `TOOLS_COVERED=` / `TOOLS_MISSING=` | Distinct tools that need a rule, and how many have at least one command no rule matches |
| `TOOLS_UNRESOLVED=` (`TOOL=<word> STATE=unresolved FILE=` with `--verbose`) | First words that are not on PATH, not a file in the project and not `./`-prefixed: a shebang recipe's body, a word the line scanner misread, or a tool not installed. Not counted in `STATUS` |
| `TYPE=missing_permission` row | One per missing tool: `TOOL=`, `FILE=`, and the first unmatched command in `MSG=` |
| `UNUSED_RULE_COUNT=` (`UNUSED_RULE=` with `--verbose`) | Project or project-local rules whose tool no scanned file runs. Informational, never a finding |

Scoring: OK with no missing tool, WARN for 1–3, ERROR for 4 or more (exit 1). The script needs bash 4 or later; under macOS `/bin/bash` 3.2 it reports `STATUS=ERROR` with `TYPE=bash_too_old` rather than a coverage result. The check is read-only and has no `--fix` path.

## Checks 1b, 1c, 1e

#### 1b. SessionStart smoke test

Check whether `scripts/install_pkgs.sh` (or any script registered in the `SessionStart` hook in `.claude/settings.json`) is executable and exits cleanly in both remote and local contexts. These runs execute project code, so the skill's `allowed-tools` does not pre-approve them; they go through the session's normal permission flow.

1. Locate the `SessionStart` hook command from `.claude/settings.json` (look for the `command` field).
2. If a script is found, run:
   ```bash
   CLAUDE_CODE_REMOTE=true bash <script-path>
   ```
   Capture exit code. Expected: 0.
3. Run again to verify idempotency — expected: 0.
4. Run with remote guard off:
   ```bash
   CLAUDE_CODE_REMOTE=false bash <script-path>
   ```
   Expected: 0 (typically a no-op).
5. Report:
   - OK: All three exit 0
   - WARN: Script exists but is not registered in settings.json hook
   - ERROR: Script exits non-zero, or script referenced in hook does not exist

#### 1c. Pre-commit config validator

If `.pre-commit-config.yaml` exists:

```bash
pre-commit validate-config .pre-commit-config.yaml
```

Report:
- OK: exits 0 (config is valid)
- WARN: `pre-commit` not installed — skip check, suggest `pip install pre-commit`
- ERROR: exits non-zero — show validation error

Permissions coverage (1d) runs as a script in Step 1a; see [1d. Permissions coverage](#1d-permissions-coverage-check-permissions-coveragesh).

#### 1e. Marketplace enrollment check

The local marketplace key (set by `claude marketplace add <name>`) is user-chosen and varies between installs (commonly `laurigates-claude-plugins`, sometimes `claude-plugins`). Identify the marketplace by its stable `source.repo`, not by a hardcoded local key.

1. Read `.claude/settings.json`.
2. Scan all entries under `extraKnownMarketplaces` and find the one whose `source.repo` equals `"laurigates/claude-plugins"`. Capture that entry's key as `$MP_KEY`.
3. Check that `enabledPlugins` contains at least one key with the suffix `@$MP_KEY`.
4. Report:
   - OK: Both checks pass
   - WARN: `enabledPlugins` has no `@$MP_KEY` entries (marketplace enrolled but no plugins enabled)
   - ERROR: no `extraKnownMarketplaces` entry with `source.repo = laurigates/claude-plugins` (run `/configure:claude-plugins --fix` to add it)

Reference `jq` snippet (for verification or fix scripts):

```bash
MP_KEY=$(jq -r '.extraKnownMarketplaces // {} | to_entries | map(select(.value.source.repo == "laurigates/claude-plugins")) | .[0].key // empty' .claude/settings.json)
if [ -z "$MP_KEY" ]; then
  echo "ERROR: no extraKnownMarketplaces entry with source.repo = laurigates/claude-plugins"
else
  jq -e --arg k "@$MP_KEY" '.enabledPlugins // {} | to_entries | map(select(.key | endswith($k))) | length > 0' .claude/settings.json >/dev/null \
    && echo "OK: marketplace enrolled as $MP_KEY with enabled plugins" \
    || echo "WARN: marketplace $MP_KEY enrolled but no @${MP_KEY} entries in enabledPlugins"
fi
```
