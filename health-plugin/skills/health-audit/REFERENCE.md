# Health Audit Reference

## Tech Stack Detection Mapping

| Indicator | Technology | Related Plugins |
|-----------|------------|-----------------|
| `package.json` + `tsconfig.json` | TypeScript | typescript-plugin |
| `package.json` (no tsconfig) | JavaScript | typescript-plugin (JS support) |
| `bun.lockb` or bun in package.json | Bun runtime | typescript-plugin |
| `Cargo.toml` | Rust | rust-plugin |
| `pyproject.toml`, `requirements.txt`, `setup.py` | Python | python-plugin |
| `go.mod` | Go | (no plugin yet) |
| `Dockerfile`, `docker-compose.yml` | Docker/Containers | container-plugin |
| `.github/workflows/*.yml` | GitHub Actions | github-actions-plugin |
| `*.tf` files | Terraform | terraform-plugin |
| `k8s/`, `kubernetes/` with manifests | Kubernetes | kubernetes-plugin |
| `bevy` in Cargo.toml | Bevy game engine | bevy-plugin |
| `.claude-plugin/` directory | Claude plugin development | (this repo) |
| `docs/` with markdown | Documentation | documentation-plugin |
| `langchain` in dependencies | LangChain | langchain-plugin |
| OpenAPI/Swagger specs | API development | api-plugin |
| `biome.json`, `.eslintrc*` | Code quality | code-quality-plugin |
| `vitest.config.*`, `jest.config.*` | Testing | testing-plugin |
| Home Assistant configs | Home Assistant | home-assistant-plugin |

## Plugin Relevance Mapping

| Plugin | Relevant When |
|--------|--------------|
| typescript-plugin | package.json exists |
| python-plugin | Python project indicators exist |
| rust-plugin | Cargo.toml exists |
| container-plugin | Dockerfile or compose file exists |
| kubernetes-plugin | K8s manifests exist |
| github-actions-plugin | .github/workflows/ exists |
| terraform-plugin | *.tf files exist |
| git-plugin | Always relevant (all repos use git) |
| tools-plugin | Always relevant (common CLI tools) |
| configure-plugin | Always relevant (setup automation) |
| testing-plugin | Test files/configs exist |
| code-quality-plugin | Linter configs exist |
| bevy-plugin | Bevy in Cargo.toml dependencies |
| langchain-plugin | LangChain in dependencies |
| api-plugin | OpenAPI specs exist |
| documentation-plugin | docs/ directory with markdown |
| blueprint-plugin | docs/blueprint/ or planning documents |
| agents-plugin | Agent development context |
| project-plugin | Project management needs |

## enabledPlugins Shape

`enabledPlugins` is an object keyed by `plugin-name@marketplace-name`, each value a boolean ([settings reference](https://code.claude.com/docs/en/settings-reference#enabledplugins)):

```json
{
  "enabledPlugins": {
    "python-plugin@laurigates-claude-plugins": true,
    "terraform-plugin@laurigates-claude-plugins": false
  }
}
```

| Value | Meaning |
|-------|---------|
| `true` | Enabled at this scope |
| `false` | Disabled at this scope; overrides a `true` at a lower-precedence scope |
| no entry | Falls back to the next scope, then to the plugin's `defaultEnabled` |

Precedence: managed, then local (`.claude/settings.local.json`), then project (`.claude/settings.json`), then user (`~/.claude/settings.json`). `scripts/enabled-plugins.sh` reads and writes this shape; read names with `to_entries[] | select(.value == true) | .key`, never by iterating the values.

## Plugin List JSON

`claude plugin list --json --available` (Claude Code 2.1.322; `--available` requires `--json`) prints:

```json
{
  "installed": [
    {"id": "python-plugin@laurigates-claude-plugins", "version": "1.2.3", "scope": "user", "enabled": true}
  ],
  "available": [
    {"pluginId": "rust-plugin@laurigates-claude-plugins", "name": "rust-plugin",
     "description": "...", "marketplaceName": "laurigates-claude-plugins", "version": "1.0.0"}
  ]
}
```

| Array | Holds | Fields the audit uses |
|-------|-------|-----------------------|
| `installed` | Installed plugins, every scope | `id`, `scope` |
| `available` | Marketplace plugins not installed | `pluginId`, `name`, `description`, `marketplaceName` |

Installed entries carry no description, and neither array has keyword or category fields. They also carry `enabled`, `projectEnabled` and, for project and local rows, `projectPath`, which the audit does not use. Observed on 2.1.322 (2026-11-12, three directories): both booleans describe the plugin in the directory the command runs from and repeat on every row of that plugin; `enabled` matched whether the merged settings there enable it, `projectEnabled` whether that directory's `.claude/settings.json` does. Plain `claude plugin list --json` prints only the installed entries, as a bare array rather than this object.

## Report Template

```
Plugin Audit Report
===================
Project: <current-directory>
Date: <timestamp>

Detected Technology Stack
-------------------------
- TypeScript/JavaScript (package.json, tsconfig.json)
- Docker (Dockerfile, docker-compose.yml)
- GitHub Actions (.github/workflows/)

Currently Enabled Plugins (N)
-----------------------------
+ typescript-plugin     - RELEVANT (TypeScript project)
+ git-plugin            - RELEVANT (all repos)
x kubernetes-plugin     - NOT RELEVANT (no K8s manifests found)
x terraform-plugin      - NOT RELEVANT (no .tf files found)
x python-plugin         - NOT RELEVANT (no Python indicators)

Suggested Plugins to Add (N)
----------------------------
+ container-plugin      - Docker files detected
+ github-actions-plugin - Workflow files detected
+ testing-plugin        - Test configuration detected

Suggested Plugins to Remove (N)
-------------------------------
- kubernetes-plugin     - No K8s usage detected
- terraform-plugin      - No Terraform usage detected
- python-plugin         - No Python usage detected

Summary
-------
Enabled: N plugins
Relevant: N plugins
Irrelevant: N plugins (consider removing)
Missing: N plugins (consider adding)

Run `/health:check --scope=stack --fix` to apply these recommendations.
```
