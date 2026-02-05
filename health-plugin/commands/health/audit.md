---
model: opus
created: 2026-02-05
modified: 2026-02-05
reviewed: 2026-02-05
description: Audit enabled plugins against project tech stack and recommend additions/removals for relevance
allowed-tools: Bash(cat *), Bash(test *), Bash(find *), Bash(ls *), Bash(jq *), Bash(claude plugin *), Read, Write, Edit, Glob, Grep, TodoWrite, AskUserQuestion
argument-hint: "[--fix] [--dry-run] [--verbose]"
---

# /health:audit

Audit the project's enabled plugins against the actual technology stack. Identifies plugins that don't apply to this project and suggests relevant plugins that aren't enabled.

## Context

- Current project: !`pwd`
- Project settings exists: !`find .claude -maxdepth 1 -name 'settings.json' 2>/dev/null`
- Enabled plugins: !`jq -r '.enabledPlugins[]? // empty' .claude/settings.json 2>/dev/null`
- Package.json exists: !`find . -maxdepth 1 -name 'package.json' 2>/dev/null`
- Cargo.toml exists: !`find . -maxdepth 1 -name 'Cargo.toml' 2>/dev/null`
- pyproject.toml exists: !`find . -maxdepth 1 -name 'pyproject.toml' 2>/dev/null`
- requirements.txt exists: !`find . -maxdepth 1 -name 'requirements.txt' 2>/dev/null`
- go.mod exists: !`find . -maxdepth 1 -name 'go.mod' 2>/dev/null`
- Dockerfile exists: !`find . -maxdepth 1 -name 'Dockerfile' 2>/dev/null`
- docker-compose exists: !`find . -maxdepth 1 \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null`
- GitHub workflows: !`find .github/workflows -maxdepth 1 -name '*.yml' 2>/dev/null -quit -print`
- Terraform files: !`find . -maxdepth 2 -name '*.tf' 2>/dev/null -quit -print`
- Kubernetes manifests: !`find . -maxdepth 3 \( -path '*/k8s/*' -o -path '*/kubernetes/*' \) -name '*.yaml' 2>/dev/null -quit -print`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply recommended changes to `.claude/settings.json` |
| `--dry-run` | Show what would be changed without modifying files |
| `--verbose` | Show detailed analysis of each plugin decision |

## Workflow

### Phase 1: Detect Technology Stack

Analyze project files to determine the technology stack:

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

### Phase 2: Get Available Plugins

Run `claude plugin list --json` to get all available plugins from configured marketplaces.

Parse the output to get:
- Plugin name
- Description
- Keywords
- Category

### Phase 3: Get Currently Enabled Plugins

Read `.claude/settings.json` and extract `enabledPlugins` array.

If file doesn't exist or `enabledPlugins` is not set, treat as empty list.

### Phase 4: Analyze Relevance

For each enabled plugin, check if it matches the detected tech stack:

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

### Phase 5: Generate Report

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
✓ typescript-plugin     - RELEVANT (TypeScript project)
✓ git-plugin            - RELEVANT (all repos)
✗ kubernetes-plugin     - NOT RELEVANT (no K8s manifests found)
✗ terraform-plugin      - NOT RELEVANT (no .tf files found)
✗ python-plugin         - NOT RELEVANT (no Python indicators)

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

Run `/health:audit --fix` to apply these recommendations.
```

### Phase 6: Apply Changes (if --fix)

If `--fix` flag is provided:

1. **Backup current settings**
   ```bash
   cp .claude/settings.json .claude/settings.json.backup
   ```

2. **Ask for confirmation** before each category of changes:
   - "Remove these irrelevant plugins? [y/N]: kubernetes-plugin, terraform-plugin"
   - "Add these relevant plugins? [y/N]: container-plugin, github-actions-plugin"

3. **Update `.claude/settings.json`**
   - Remove confirmed irrelevant plugins from `enabledPlugins`
   - Add confirmed relevant plugins to `enabledPlugins`
   - Preserve other settings

4. **Verify changes**
   - Re-read the file
   - Confirm JSON is valid
   - Show diff of changes

## User-Level vs Project-Level

Note: This command only manages **project-level** plugin settings in `.claude/settings.json`.

User-level plugins (in `~/.claude/settings.json`) are managed separately and don't need duplication at project level.

When analyzing, check if a plugin is already enabled at user level:
```bash
jq -r '.enabledPlugins[]? // empty' ~/.claude/settings.json 2>/dev/null
```

If a plugin is enabled at user level, it doesn't need to be in project settings unless you want project-specific behavior.

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| No `.claude/settings.json` | Create it with recommended plugins |
| Empty `enabledPlugins` | Suggest adding relevant plugins |
| Monorepo with multiple languages | Suggest all matching plugins |
| Plugin not in marketplace | Flag as "unknown" but don't remove |
| User declined changes | Respect decision, show manual instructions |

## Flags

| Flag | Description |
|------|-------------|
| `--fix` | Apply recommended changes (with confirmation) |
| `--dry-run` | Show what would be changed without modifying |
| `--verbose` | Show detailed reasoning for each decision |

## See Also

- `/health:plugins` - Fix plugin registry issues
- `/health:check` - Full diagnostic scan
- `/configure:claude-plugins` - Initial plugin setup
