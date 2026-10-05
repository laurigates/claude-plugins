# settings.json Stanza and Permissions

Used by Step 3 (Configure .claude/settings.json) of `/configure:claude-plugins`.


## Suffix forms

> **Suffix forms — read this before copy-pasting.** The two suffix forms below are not interchangeable. Using the wrong one silently breaks the config:
>
> | Where | Suffix | Source of the suffix |
> |---|---|---|
> | `.claude/settings.json` → `enabledPlugins` (Step 3) | `<plugin>@claude-plugins` | The **`extraKnownMarketplaces` key** in the same stanza |
> | `.github/workflows/claude*.yml` → `plugins:` (Steps 4–5) | `<plugin>@laurigates-claude-plugins` | The **`name` field** in `laurigates/claude-plugins/.claude-plugin/marketplace.json` |
>
> Wrong suffix in `enabledPlugins` → entry silently ignored (marketplace key does not match). Wrong suffix in the workflow `plugins:` block → action rejects the run.

## Why `enabledPlugins` merge semantics matter

`enabledPlugins` is a **per-key merging map** across the settings hierarchy: a project entry overrides the matching global entry, but global entries the project does not mention still take effect. There is no `enabledPluginsExclusive` flag. So if a user has accidentally toggled an unwanted plugin globally (easy to do via the plugins UI), it leaks into every repo that does not explicitly set it to `false`.

| Mode | Project `enabledPlugins` contents | Behaviour vs global toggles |
|------|------------------------------------|------------------------------|
| Default (no flag) | Recommended plugins as `true` only | Lean. Vulnerable to global drift — any plugin the user toggled on globally is also active here. |
| `--exhaustive` | Every marketplace plugin enumerated as `true` or `false` | Deterministic. Project pin overrides every global toggle. Re-run when the marketplace adds plugins. |

Pick `--exhaustive` for repos that need a self-documenting, drift-resistant plugin set (infrastructure repos, repos shared with teammates / CI, repos sensitive to context tax from unrelated plugins). Use the default for personal scratch repos where global toggles are intentional.

## Stack-aware `permissions.allow` baseline

Always include these common entries:

```json
"Bash(git:*)", "Bash(gh:*)", "Bash(pre-commit:*)", "Bash(gitleaks:*)", "Bash(python3:*)"
```

Add stack-specific entries based on detected project type:

| Stack | Additional allow entries |
|---|---|
| Python (uv + ruff + ty) | `"Bash(uv:*)"`, `"Bash(uvx:*)"`, `"Bash(ruff:*)"`, `"Bash(ty:*)"`, `"Bash(pytest:*)"` |
| Node / TypeScript | `"Bash(npm:*)"`, `"Bash(pnpm:*)"`, `"Bash(bun:*)"`, `"Bash(tsc:*)"`, `"Bash(eslint:*)"`, `"Bash(prettier:*)"`, `"Bash(vitest:*)"` |
| Go | `"Bash(go:*)"`, `"Bash(gofmt:*)"`, `"Bash(golangci-lint:*)"` |
| Rust | `"Bash(cargo:*)"`, `"Bash(rustc:*)"`, `"Bash(clippy:*)"`, `"Bash(rustfmt:*)"` |
| C / C++ (CMake) | `"Bash(cmake:*)"`, `"Bash(ctest:*)"`, `"Bash(clang-format:*)"`, `"Bash(clang-tidy:*)"`, `"Bash(cppcheck:*)"`, `"Bash(make:*)"`, `"Bash(ninja:*)"` |
| ESP-IDF / embedded | `"Bash(idf.py:*)"`, `"Bash(esptool:*)"`, `"Bash(clang-format:*)"`, `"Bash(cppcheck:*)"`, `"Bash(docker:*)"`, `"Bash(docker compose:*)"`, `"Bash(just:*)"`, `"Bash(make:*)"` |
| ESPHome | `"Bash(esphome:*)"`, `"Bash(uv:*)"`, `"Bash(uvx:*)"` |

Use granular patterns only — do not add `Bash(bash *)` for CLI tools.

## Full settings.json stanza to merge

The `extraKnownMarketplaces` key (`claude-plugins`) is what each `enabledPlugins` entry's `@claude-plugins` suffix must match. The two stanzas are coupled — changing the key without also changing every suffix silently disables every plugin in `enabledPlugins`.

```json
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(gh:*)",
      "Bash(pre-commit:*)",
      "Bash(gitleaks:*)",
      "Bash(python3:*)"
      // ... plus stack-specific entries from the table above
    ]
  },
  "extraKnownMarketplaces": {
    "claude-plugins": {                                  // marketplace KEY (used by enabledPlugins suffix below)
      "source": { "source": "github", "repo": "laurigates/claude-plugins" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "<selected-plugin-1>@claude-plugins": true,          // suffix == extraKnownMarketplaces key, NOT marketplace name
    "<selected-plugin-2>@claude-plugins": true
  }
}
```

Replace `<selected-plugin-N>` with the plugin names selected in Step 2.

If `.claude/settings.json` already exists, **MERGE** without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository
- `extraKnownMarketplaces` in `.claude/settings.json` is the key to surviving ephemeral web sessions — without it, the marketplace is only enrolled via CI
- **Workflow scaffolding is gated on a git remote.** A repo without a remote cannot run GitHub Actions, so `claude.yml` and `claude-code-review.yml` are skipped by default — writing them would create dormant files that confuse future readers. Override with `--workflows` to pre-stage them before adding a remote.
- **Two distinct suffix forms** (see the callout at the top of Step 3 for the canonical table):
  - `enabledPlugins` entries use `<plugin>@claude-plugins` — the `extraKnownMarketplaces` *key*
  - Workflow `plugins:` blocks use `<plugin>@laurigates-claude-plugins` — the marketplace `name` field from `marketplace.json`
- Mixing the two forms silently breaks the config — `enabledPlugins` entries with the wrong suffix are ignored; workflow `plugins:` entries with the wrong suffix are rejected by the action
