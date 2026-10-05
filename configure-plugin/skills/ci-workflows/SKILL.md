---
created: 2025-12-16
modified: 2026-10-05
reviewed: 2026-06-01
name: ci-workflows
description: "Reference YAML for the canonical container-build, test, release-please and auto-fix workflow files. Use when another skill or a review needs the standard shape to cite or diff against."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# CI Workflow Standards

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| You need the canonical GitHub Actions workflow shapes (container build, test, release) | You want to audit or install workflows end-to-end as an interactive workflow — use `configure-workflows` |
| You are checking whether existing `.github/workflows/*.yml` follows the documented conventions | You want pre-built reusable callers wired up — use `configure-reusable-workflows` |
| Another skill needs to cite the standard workflow structure | The user asked you to actually create or repair CI workflows |

## Version: 2025.1

Standard GitHub Actions workflows for CI/CD automation.

## Display name convention

Every workflow's `name:` follows `<Domain>: <Action> [<target>]` so the GitHub Actions sidebar groups related workflows alphabetically. Quote the value because YAML treats `:` inside an unquoted scalar as a key separator. See `.claude/rules/workflow-naming.md` for the canonical rule, the active domain list, and the cross-workflow rename procedure. Mirror the pattern in any workflow you scaffold here.

## Required Workflows

Full YAML, key features, and prerequisites for each file live in [references/workflow-templates.md](references/workflow-templates.md) — read it when citing, diffing against, or scaffolding a specific workflow.

| # | Workflow | File | Status |
|---|----------|------|--------|
| 1 | [Container Build](references/workflow-templates.md#1-container-build-workflow) | `.github/workflows/container-build.yml` | Required if Dockerfile |
| 2 | Release Please | `.github/workflows/release-please.yml` | Required |
| 3 | [ArgoCD Auto-merge](references/workflow-templates.md#3-argocd-auto-merge-workflow-optional) | `.github/workflows/argocd-automerge.yml` | Optional |
| 4 | [Test](references/workflow-templates.md#4-test-workflow-recommended) | `.github/workflows/test.yml` | Recommended |
| 5 | [Claude Auto-Fix](references/workflow-templates.md#5-claude-auto-fix-workflow-optional) | `.github/workflows/claude-auto-fix.yml` | Optional |

### 2. Release Please Workflow

**File**: `.github/workflows/release-please.yml`

See `configure-release-please` (its REFERENCE.md carries the standard workflow, token, and config templates) for details.

## Workflow Standards

### Action Versions

| Action | Version | Purpose |
|--------|---------|---------|
| actions/checkout | v6 | Repository checkout |
| docker/setup-buildx-action | v4 | Multi-platform builds |
| docker/login-action | v4 | Registry authentication |
| docker/metadata-action | v6 | Image tagging |
| docker/build-push-action | v7 | Container build/push |
| actions/setup-node | v6 | Node.js setup |
| googleapis/release-please-action | v5 | Release automation |

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
| argocd-automerge | Auto-merge image updates | Optional (if using ArgoCD Image Updater) |
| claude-auto-fix | Automated CI failure remediation | Optional |

### Required Elements

| Element | Requirement |
|---------|-------------|
| checkout action | v6 |
| build-push action | v7 |
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
| CLAUDE_CODE_OAUTH_TOKEN | Claude Code Action auth | For claude-auto-fix |

## Troubleshooting

Build failures, multi-platform issues, and cache misses: see [references/troubleshooting.md](references/troubleshooting.md) when a compliant workflow still fails at runtime.
