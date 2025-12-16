---
description: Check and configure GitHub Actions CI/CD workflows (container builds, tests, releases)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
---

# /configure:workflows

Check and configure GitHub Actions CI/CD workflows against FVH (Forum Virium Helsinki) standards.

## Context

This command validates `.github/workflows/` configuration against FVH standards including:
- **Container build workflows** - Multi-platform builds, registry push, security scanning
- **Test workflows** - Linting, type checking, test execution, coverage
- **Release workflows** - release-please automation, semantic versioning

**Skills referenced**: `fvh-ci-workflows`, `github-actions-auth-security`

## Version Checking

**CRITICAL**: Before flagging outdated actions, verify latest versions:

1. **GitHub Actions**: Check release pages for latest versions
   - `actions/checkout` - [releases](https://github.com/actions/checkout/releases)
   - `actions/setup-node` - [releases](https://github.com/actions/setup-node/releases)
   - `docker/build-push-action` - [releases](https://github.com/docker/build-push-action/releases)
   - `docker/login-action` - [releases](https://github.com/docker/login-action/releases)
   - `docker/metadata-action` - [releases](https://github.com/docker/metadata-action/releases)
   - `google-github-actions/release-please-action` - [releases](https://github.com/google-github-actions/release-please-action/releases)

Use WebSearch or WebFetch to verify current versions before reporting outdated actions.

## Workflow

### Phase 1: Detection

1. Check for `.github/workflows/` directory
2. List all workflow files (*.yml, *.yaml)
3. Categorize workflows by purpose

### Phase 2: Required Workflow Check

**Required workflows based on project type:**

| Project Type | Required Workflows |
|--------------|-------------------|
| Frontend | container-build, release-please |
| Python | container-build, release-please, test |
| Infrastructure | release-please (optional: docs) |

### Phase 3: Compliance Analysis

**Container Build Workflow Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| checkout action | v4 | WARN if older |
| build-push action | v6 | WARN if older |
| Multi-platform | amd64 + arm64 | WARN if missing |
| Registry | GHCR (ghcr.io) | INFO |
| Caching | GHA cache enabled | WARN if missing |
| Permissions | Explicit | WARN if missing |

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

### Phase 4: Report Generation

```
FVH GitHub Workflows Compliance Report
======================================
Project Type: frontend (detected)
Workflows Directory: .github/workflows/ (found)

Workflow Status:
  container-build.yml   ✅ PASS
  release-please.yml    ✅ PASS
  test.yml              ❌ FAIL (missing)

container-build.yml Checks:
  checkout              v4              ✅ PASS
  build-push-action     v6              ✅ PASS
  Multi-platform        amd64,arm64     ✅ PASS
  Caching               GHA cache       ✅ PASS
  Permissions           Explicit        ✅ PASS

release-please.yml Checks:
  Action version        v4              ✅ PASS
  Token                 MY_RELEASE...   ✅ PASS

Missing Workflows:
  - test.yml (recommended for frontend projects)

Overall: 1 issue found
```

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing workflows**: Create from FVH templates
2. **Outdated actions**: Update version numbers
3. **Missing multi-platform**: Add platforms to build-push
4. **Missing caching**: Add GHA cache configuration

### Phase 6: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  workflows: "2025.1"
```

## FVH Standard Templates

### Container Build Template

```yaml
name: Build Container

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  release:
    types: [published]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}

      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Test Workflow Template (Node)

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run test:coverage
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## See Also

- `/configure:container` - Comprehensive container infrastructure (builds, registry, scanning)
- `/configure:dockerfile` - Dockerfile configuration and security
- `/configure:release-please` - Release automation specifics
- `/configure:all` - Run all FVH compliance checks
- `fvh-ci-workflows` skill - Workflow patterns
- `github-actions-inspection` skill - Workflow debugging
