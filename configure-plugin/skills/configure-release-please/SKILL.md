---
created: 2025-12-16
modified: 2026-06-24
reviewed: 2026-06-24
description: "release-please workflow setup and auditing. Use when configuring release-please, upgrading release-please-action, or adding a package to a monorepo config."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
name: configure-release-please
---

# /configure:release-please

Check and configure release-please against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Setting up release-please for a new project from scratch | Manually editing CHANGELOG.md or version fields — use conventional commits instead |
| Auditing existing release-please configuration for compliance | Creating a one-off release — use `gh release create` directly |
| Upgrading release-please-action to the latest version | Debugging a failed release PR — check GitHub Actions logs directly |
| Ensuring the workflow uses a correct release token (GitHub App token, preferred; or `MY_RELEASE_PLEASE_TOKEN`) | Managing npm/PyPI publishing — configure separate publish workflows |
| Adding a new package to a monorepo release-please configuration | Writing conventional commit messages — use `/git:commit` skill |

## Context

- Workflow file: !`find . -path '*/.github/workflows/*' -maxdepth 3 -name 'release-please*'`
- Config file: !`find . -maxdepth 1 -name \'release-please-config.json\'`
- Manifest file: !`find . -maxdepth 1 -name \'.release-please-manifest.json\'`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Workflows dir: !`find . -maxdepth 1 -type d -name \'.github/workflows\'`

**Skills referenced**: `release-please-standards`, `release-please-protection`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes
- `--fix`: Apply all fixes automatically

## Execution

Execute this release-please configuration check:

### Step 1: Fetch latest action version

Run this command to get the current release-please-action version dynamically:

```bash
curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest | jq -r '.tag_name'
```

**References**:
- [release-please-action releases](https://github.com/googleapis/release-please-action/releases)
- [release-please CLI releases](https://github.com/googleapis/release-please/releases)

### Step 2: Detect project type

Determine appropriate release-type from detected package files:

- **node**: Has `package.json` (default for frontend/backend apps)
- **python**: Has `pyproject.toml` without `package.json`
- **helm**: Infrastructure with Helm charts
- **simple**: Generic projects

### Step 3: Analyze compliance

**Workflow file checks**:
- Action version: `googleapis/release-please-action@v4`
- Token: Uses a non-`GITHUB_TOKEN` release token. Accept **either** pattern:
  - **GitHub App token (preferred)** — `actions/create-github-app-token` mints
    a token from `app-id: ${{ vars.RELEASE_PLEASE_APP_ID }}` /
    `private-key: ${{ secrets.RELEASE_PLEASE_PRIVATE_KEY }}`, passed as
    `token: ${{ steps.app-token.outputs.token }}`. Treat this as compliant —
    do **not** flag it to switch to `MY_RELEASE_PLEASE_TOKEN`.
  - **PAT (legacy)** — `token: ${{ secrets.MY_RELEASE_PLEASE_TOKEN }}`.
- Trigger: Push to `main` branch
- Permissions: `contents: write`, `pull-requests: write`

**Config file checks**:
- Valid release-type for project
- changelog-sections includes `feat` and `fix`
- Appropriate plugins (e.g., `node-workspace` for Node projects)

**Manifest file checks**:
- Valid JSON structure
- Package paths match config

### Step 4: Generate compliance report

Print a formatted compliance report showing file status and configuration check results. If `--check-only` is set, stop here.

For the report format, see [REFERENCE.md](REFERENCE.md).

### Step 5: Apply configuration (if --fix or user confirms)

1. **Missing workflow**: Create from standard template
2. **Missing config**: Create with detected release-type
3. **Missing manifest**: Create with initial version `0.0.0`
4. **Outdated action**: Update to v4
5. **Wrong token**: Use the GitHub App-token pattern (preferred) or
   `MY_RELEASE_PLEASE_TOKEN` — never `GITHUB_TOKEN`. A workflow already on
   `create-github-app-token` is compliant; leave it as-is.

For both token templates (App-token preferred, PAT legacy), see [REFERENCE.md](REFERENCE.md).

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  release-please: "2025.1"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:release-please --check-only` |
| Auto-fix all issues | `/configure:release-please --fix` |
| Check latest action version | `curl -s https://api.github.com/repos/googleapis/release-please-action/releases/latest \| jq -r '.tag_name'` |
| Verify config JSON | `jq . release-please-config.json` |
| Verify manifest JSON | `jq . .release-please-manifest.json` |
| Check workflow exists | `find .github/workflows -name 'release-please*'` |

## Important Notes

- **Release token (not `GITHUB_TOKEN`)** — a release PR needs a token that can
  trigger other workflows. Two patterns, App-token preferred:
  - **GitHub App token (preferred)** — `actions/create-github-app-token` reads
    `RELEASE_PLEASE_APP_ID` (a repo/org **variable**) and
    `RELEASE_PLEASE_PRIVATE_KEY` (a **secret**). For the laurigates org these
    credentials are pushed by gitops to repos flagged `release_please = true`,
    so this is the standard that matches every other repo.
  - **`MY_RELEASE_PLEASE_TOKEN` PAT (legacy)** — a personal-access-token secret
    in repository settings. Still valid, but diverges from the org standard.
- CHANGELOG.md is managed by release-please - never edit manually
- Version fields in package.json/pyproject.toml are managed automatically
- Works with `conventional-pre-commit` hook for commit validation

## See Also

- `/configure:pre-commit` - Ensure conventional commits hook
- `/configure:all` - Run all compliance checks
- `release-please-protection` skill - Protected file rules
