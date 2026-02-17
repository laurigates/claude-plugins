---
model: opus
created: 2025-12-16
modified: 2026-02-13
reviewed: 2025-12-16
description: Check and configure GitHub Actions CI/CD workflows (container builds, tests, releases)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
name: configure-workflows
---

# /configure:workflows

Check and configure GitHub Actions CI/CD workflows against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Checking GitHub Actions workflows for compliance with project standards | Debugging a failing CI run (use github-actions-inspection skill) |
| Setting up container build, test, or release-please workflows | Installing Claude-powered reusable workflows (use `/configure:reusable-workflows`) |
| Updating outdated action versions (checkout, build-push, etc.) | Writing a custom workflow from scratch (use ci-workflows skill) |
| Adding multi-platform builds or GHA caching to existing workflows | Configuring security-specific workflows (use `/configure:security`) |
| Auditing which required workflows are missing from a project | Managing GitHub repository settings or branch protection rules |

## Context

- Workflows dir: !`find . -maxdepth 1 -type d -name \'.github/workflows\' 2>/dev/null`
- Workflow files: !`find .github/workflows -maxdepth 1 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Dockerfile: !`find . -maxdepth 1 -name 'Dockerfile*' 2>/dev/null`
- Release-please config: !`find . -maxdepth 1 -name \'release-please-config.json\' 2>/dev/null`

**Skills referenced**: `ci-workflows`, `github-actions-auth-security`

## Parameters

Parse from command arguments:

- `--check-only`: Report status without offering fixes
- `--fix`: Apply fixes automatically

## Execution

Execute this GitHub Actions workflow configuration check:

### Step 1: Fetch latest action versions

Verify latest versions before reporting outdated actions:

1. `actions/checkout` - [releases](https://github.com/actions/checkout/releases)
2. `actions/setup-node` - [releases](https://github.com/actions/setup-node/releases)
3. `actions/cache` - [releases](https://github.com/actions/cache/releases)
4. `docker/setup-buildx-action` - [releases](https://github.com/docker/setup-buildx-action/releases)
5. `docker/build-push-action` - [releases](https://github.com/docker/build-push-action/releases)
6. `docker/login-action` - [releases](https://github.com/docker/login-action/releases)
7. `docker/metadata-action` - [releases](https://github.com/docker/metadata-action/releases)
8. `reproducible-containers/buildkit-cache-dance` - [releases](https://github.com/reproducible-containers/buildkit-cache-dance/releases)
9. `google-github-actions/release-please-action` - [releases](https://github.com/google-github-actions/release-please-action/releases)

Use WebSearch or WebFetch to verify current versions.

### Step 2: Detect project type and list workflows

1. Check for `.github/workflows/` directory
2. List all workflow files (*.yml, *.yaml)
3. Categorize workflows by purpose (container build, test, release)

Determine required workflows based on project type:

| Project Type | Required Workflows |
|--------------|-------------------|
| Frontend | container-build, release-please |
| Python | container-build, release-please, test |
| Infrastructure | release-please (optional: docs) |

### Step 3: Analyze workflow compliance

**Container Build Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| checkout action | v4 | WARN if older |
| build-push action | v6 | WARN if older |
| Multi-platform | amd64 + arm64 | WARN if missing |
| Registry | GHCR (ghcr.io) | INFO |
| Caching | GHA cache enabled | WARN if missing |
| Permissions | Explicit | WARN if missing |
| `id-token: write` | Required when provenance/SBOM enabled | WARN if missing |
| Cache scope | Explicit `scope=` when multiple build jobs | WARN if missing |
| Dead metadata tags | No `type=schedule` without schedule trigger | INFO |
| Semver regex escaping | Dots escaped in `type=match` patterns (`\d+\.\d+`) | WARN if unescaped |
| Hardcoded image names | Derive from `${{ github.repository }}` | INFO if hardcoded |
| Digest output | Capture `build-push` digest via `id:` for traceability | INFO if missing |
| Job summary | Write image/digest/tags to `$GITHUB_STEP_SUMMARY` | INFO if missing |
| Duplicated job conditions | Identical `if:` on sibling jobs; suggest gate job | INFO |

**Release Please Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| Action version | v4 | WARN if older |
| Token | MY_RELEASE_PLEASE_TOKEN | WARN if GITHUB_TOKEN |
| Permissions | contents: write, pull-requests: write | FAIL if missing |

**Test Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| Node version | 22 | WARN if older |
| Linting | npm run lint | WARN if missing |
| Type check | npm run typecheck | WARN if missing |
| Coverage | Coverage upload | INFO |

### Step 4: Generate compliance report

Print a formatted compliance report showing workflow status, per-workflow check results, and missing workflows.

If `--check-only` is set, stop here.

For the report format, see [REFERENCE.md](REFERENCE.md).

### Step 5: Apply configuration (if --fix or user confirms)

1. **Missing workflows**: Create from standard templates
2. **Outdated actions**: Update version numbers
3. **Missing multi-platform**: Add platforms to build-push
4. **Missing caching**: Add GHA cache configuration

For standard templates (container build, test workflow), see [REFERENCE.md](REFERENCE.md).

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  workflows: "2025.1"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:workflows --check-only` |
| Auto-fix all issues | `/configure:workflows --fix` |
| List workflow files | `find .github/workflows -name '*.yml' -o -name '*.yaml'` |
| Check action versions | `rg 'uses:' .github/workflows/ --no-heading` |
| Verify release-please config | `test -f release-please-config.json && echo "EXISTS"` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## See Also

- `/configure:container` - Comprehensive container infrastructure (builds, registry, scanning)
- `/configure:dockerfile` - Dockerfile configuration and security
- `/configure:release-please` - Release automation specifics
- `/configure:all` - Run all compliance checks
- `ci-workflows` skill - Workflow patterns
- `github-actions-inspection` skill - Workflow debugging
