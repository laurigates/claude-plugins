---
name: fvh-ci-workflows
description: |
  FVH (Forum Virium Helsinki) GitHub Actions workflow standards. Use when configuring
  CI/CD workflows, checking workflow compliance, or when the user mentions FVH workflows,
  GitHub Actions, container builds, or CI/CD automation.
---

# FVH CI Workflow Standards

## Version: 2025.1

FVH standard GitHub Actions workflows for CI/CD automation.

## Required Workflows

### 1. Container Build Workflow

**File**: `.github/workflows/container-build.yml`

Multi-platform container build with GHCR publishing:

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

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to Container Registry
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          build-args: |
            SENTRY_AUTH_TOKEN=${{ secrets.SENTRY_AUTH_TOKEN }}
```

**Key features:**
- Multi-platform builds (amd64, arm64)
- GitHub Container Registry (GHCR)
- Semantic version tagging
- Build caching with GitHub Actions cache
- Sentry integration for source maps

### 2. Release Please Workflow

**File**: `.github/workflows/release-please.yml`

See `fvh-release-please` skill for details.

### 3. Test Workflow (Recommended)

**File**: `.github/workflows/test.yml`

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

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

      - name: Run type check
        run: npm run typecheck

      - name: Run tests
        run: npm run test:coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: ./coverage/lcov.info
```

## Workflow Standards

### Action Versions

| Action | Version | Purpose |
|--------|---------|---------|
| actions/checkout | v4 | Repository checkout |
| docker/setup-buildx-action | v3 | Multi-platform builds |
| docker/login-action | v3 | Registry authentication |
| docker/metadata-action | v5 | Image tagging |
| docker/build-push-action | v6 | Container build/push |
| actions/setup-node | v4 | Node.js setup |
| googleapis/release-please-action | v4 | Release automation |

### Permissions

Minimal permissions required:

```yaml
permissions:
  contents: read      # Default for most jobs
  packages: write     # For container push to GHCR
  pull-requests: write  # For release-please PR creation
```

### Triggers

Standard trigger patterns:

```yaml
# Build on push and PR to main
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Also build on release
on:
  release:
    types: [published]
```

### Build Caching

Use GitHub Actions cache for Docker layers:

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

### Multi-Platform Builds

Build for both amd64 and arm64:

```yaml
platforms: linux/amd64,linux/arm64
```

## Compliance Requirements

### Required Workflows

| Workflow | Purpose | Required |
|----------|---------|----------|
| container-build | Container builds | Yes (if Dockerfile) |
| release-please | Automated releases | Yes |
| test | Testing and linting | Recommended |

### Required Elements

| Element | Requirement |
|---------|-------------|
| checkout action | v4 |
| build-push action | v6 |
| Multi-platform | amd64 + arm64 |
| Caching | GHA cache enabled |
| Permissions | Explicit and minimal |

## Status Levels

| Status | Condition |
|--------|-----------|
| PASS | All required workflows present with compliant config |
| WARN | Workflows present but using older action versions |
| FAIL | Missing required workflows |
| SKIP | Not applicable (no Dockerfile = no container-build) |

## Secrets Required

| Secret | Purpose | Required |
|--------|---------|----------|
| GITHUB_TOKEN | Container registry auth | Auto-provided |
| SENTRY_AUTH_TOKEN | Source map upload | If using Sentry |
| MY_RELEASE_PLEASE_TOKEN | Release PR creation | For release-please |

## Troubleshooting

### Build Failing

- Check Dockerfile syntax
- Verify build args are passed correctly
- Check cache invalidation issues

### Multi-Platform Issues

- Ensure Dockerfile is platform-agnostic
- Use official multi-arch base images
- Avoid architecture-specific binaries

### Cache Not Working

- Verify `cache-from` and `cache-to` are set
- Check GitHub Actions cache limits (10GB)
- Consider registry-based caching for large images
