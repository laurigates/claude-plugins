# health-check: environment checks (Step 1)

## Interpreting the 1a script output

If `check-settings.sh` emits `PROJECT_DIR_RESOLVED=<path>`, the workspace root had no `.claude/` but a single nested `*/.claude/settings.json` was found one level down (parent-workspace / monorepo layout). Note the resolved path in the report so the user knows which config was checked. If it emits `PROJECT_DIR_HINT=<msg>`, surface the hint — multiple nested configs were found and the user should re-run with `--project-dir` to target one.

`check-mcp.sh` walks `.mcp.json` from `--project-dir` up through its ancestors, stopping after `--home-dir` or the filesystem root, because Claude Code also loads `.mcp.json` from parent directories (issue #2666). It emits `MCP_SOURCE_COUNT=<n>` as the denominator for the `MCP_SOURCES:` block and one `SERVER: name=<n> file=<path>` line per server, so the report can name the file each server came from. A server name defined at more than one level is counted once against the nearest file; the outer copy is reported as `SERVER_SHADOWED: name=<n> file=<outer> shadowed_by=<nearer>`. Surface the source file (and any shadowing) in the report — parent-provided servers still need per-project approval via `enabledMcpjsonServers`.

## Checks 1b–1e

#### 1b. SessionStart smoke test

Check whether `scripts/install_pkgs.sh` (or any script registered in the `SessionStart` hook in `.claude/settings.json`) is executable and exits cleanly in both remote and local contexts.

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

#### 1d. Permissions coverage check

Compare tools referenced in project files against `permissions.allow` in `.claude/settings.json`.

1. Read `permissions.allow` from `.claude/settings.json`. Extract the command prefix from each `Bash(<prefix>:*)` entry.
2. Scan these files for tool invocations:
   - `justfile` / `Justfile` — commands on recipe lines
   - `Makefile` — shell commands on recipe lines
   - `.pre-commit-config.yaml` — `entry:` fields
3. For each tool found in project files:
   - Flag as **MISSING** if no matching `Bash(<tool>:*)` entry exists in `permissions.allow`
4. For each `Bash(<tool>:*)` entry in `permissions.allow`:
   - Flag as **UNUSED** if the tool is not found in any project file (informational, not an error)

Scoring:
- OK: No missing permissions
- WARN: 1–3 missing permissions
- ERROR: 4+ missing permissions

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
