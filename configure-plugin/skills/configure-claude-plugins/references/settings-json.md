# settings.json Stanza and Permissions

Used by Step 3 (Configure .claude/settings.json) of `/configure:claude-plugins`.


## Suffix forms

> **One suffix, by design.** Both places take their suffix from a different source, and the stanza below sets them to the same value, so every reference is `<plugin>@laurigates-claude-plugins`:
>
> | Where | Suffix | Source of the suffix |
> |---|---|---|
> | `.claude/settings.json` → `enabledPlugins` (Step 3) | `<plugin>@laurigates-claude-plugins` | The **`extraKnownMarketplaces` key** in the same stanza |
> | `.github/workflows/claude*.yml` → `plugins:` (Steps 4–5) | `<plugin>@laurigates-claude-plugins` | The **`name` field** in `laurigates/claude-plugins/.claude-plugin/marketplace.json` |
>
> **Keep the key equal to the marketplace `name`.** A machine that added the marketplace with `/plugin marketplace add` already knows it as `laurigates-claude-plugins`; Claude Code registers each `extraKnownMarketplaces` key it does not already know, so any other key (the legacy keys are the policy's `settings.legacyMarketplaceAliases`) registers the same repo a second time, and that key's `enabledPlugins` entries point at the copy. A suffix that matches no marketplace key is silently ignored; a wrong suffix in the workflow `plugins:` block makes the action reject the run.

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

## Applying the repo baseline policy

The required settings keys live in one file, [`configure-plugin/policy/repo-baseline.json`](../../../policy/repo-baseline.json): the `$schema`, the marketplace stanza, the `enabledMcpjsonServers` approval floor, the legacy marketplace aliases, and the stack → plugin mapping. Read them from there; this file only says how to apply them. The policy is a **floor**: it names required keys, and everything else in a repo's settings passes through untouched.

| Policy field | How to apply it to `.claude/settings.json` |
|---|---|
| `settings.floor` | Deep-merge: objects merge key by key, lists are unioned, and an existing value the floor does not name is kept |
| `settings.legacyMarketplaceAliases` | Each is an old `extraKnownMarketplaces` key for the same marketplace (an entry whose `source.repo` is `laurigates/claude-plugins`). Rename the key **and** every `<plugin>@<alias>` suffix in `enabledPlugins` to the floor's key together |
| `stacks[].detect` | Evaluated against the repo **root** listing only: `files` = exact names, `globs` = fnmatch on root names, `cargoDependency` = the name appears under `[dependencies]` or `[workspace.dependencies]` in the root `Cargo.toml` |
| `stacks[].plugins` | Added as `true` only where the key is absent. An explicit `false` is never flipped |

The marketplace key and every `@laurigates-claude-plugins` suffix are coupled — changing the key without also changing every suffix silently disables every plugin in `enabledPlugins`.

After the floor is merged, add the permissions from [Stack-aware `permissions.allow` baseline](#stack-aware-permissionsallow-baseline) and the plugins selected in Step 2, as entries shaped like:

```json
{
  "enabledPlugins": {
    "<selected-plugin-1>@laurigates-claude-plugins": true,
    "<selected-plugin-2>@laurigates-claude-plugins": true
  }
}
```

If `.claude/settings.json` already exists, **MERGE** without duplicating entries. Preserve any existing `hooks`, `env`, or other fields.

## Important Notes

- The `CLAUDE_CODE_OAUTH_TOKEN` secret must be added manually to the repository
- `extraKnownMarketplaces` in `.claude/settings.json` is the key to surviving ephemeral web sessions — without it, the marketplace is only enrolled via CI
- **Workflow scaffolding is gated on a git remote.** A repo without a remote cannot run GitHub Actions, so `claude.yml` and `claude-code-review.yml` are skipped by default — writing them would create dormant files that confuse future readers. Override with `--workflows` to pre-stage them before adding a remote.
- **One suffix in both places** (see [Suffix forms](#suffix-forms)):
  - `enabledPlugins` entries use `<plugin>@laurigates-claude-plugins` — the `extraKnownMarketplaces` *key*
  - Workflow `plugins:` blocks use `<plugin>@laurigates-claude-plugins` — the marketplace `name` field from `marketplace.json`
- The two match only because the key is set to the marketplace `name`; a different key silently breaks `enabledPlugins` (entries ignored) or, when the suffixes follow it, registers the marketplace twice
