---
model: haiku
created: 2025-12-16
modified: 2026-02-13
reviewed: 2026-01-19
description: Check and configure container infrastructure (builds, registry, scanning, devcontainer)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, SlashCommand, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--component <dockerfile|workflow|registry|scanning|devcontainer>]"
name: configure-container
---

# /configure:container

Check and configure comprehensive container infrastructure against project standards with emphasis on **minimal images**, **non-root users**, and **security hardening**.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Auditing container infrastructure compliance (Dockerfile, workflows, scanning) | Writing a Dockerfile from scratch (`/configure:dockerfile`) |
| Checking multi-stage builds, non-root users, and security hardening | Configuring Kubernetes deployments (`/configure:skaffold`) |
| Setting up container build workflows with GHCR and multi-platform support | Running vulnerability scans on a built image (Trivy CLI directly) |
| Verifying `.dockerignore`, OCI labels, and base image versions | Configuring devcontainer features for VS Code |
| Adding Trivy/Grype scanning to CI pipelines | Debugging container runtime issues (system-debugging agent) |

## Context

- Dockerfiles: !`find . -maxdepth 2 \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) 2>/dev/null`
- Docker ignore: !`find . -maxdepth 1 -name '.dockerignore' 2>/dev/null`
- Container workflows: !`find .github/workflows -maxdepth 1 \( -name '*container*' -o -name '*docker*' -o -name '*build*' \) 2>/dev/null`
- Devcontainer: !`find .devcontainer -maxdepth 1 -name 'devcontainer.json' 2>/dev/null`
- Skaffold: !`find . -maxdepth 1 -name 'skaffold.yaml' 2>/dev/null`
- Package files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' 2>/dev/null`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications (CI/CD mode)
- `--fix`: Apply fixes automatically without prompting
- `--component <name>`: Check specific component only (dockerfile, workflow, registry, scanning, devcontainer)

## Security Philosophy

**Minimal Attack Surface**: Smaller images = fewer vulnerabilities. Use Alpine (~5MB) for Node.js, slim (~50MB) for Python.

**Non-Root by Default**: ALL containers MUST run as non-root users.

**Multi-Stage Required**: Separate build and runtime environments. Build tools and dev dependencies should NOT be in production images.

## Execution

Execute this container infrastructure compliance check:

### Step 1: Detect container-related files

Search for Dockerfile, workflow files, devcontainer config, and `.dockerignore`. Detect the project type (frontend, python, go, rust, infrastructure) from package files.

### Step 2: Look up latest base image versions

Use WebSearch or WebFetch to verify current versions before flagging outdated images:
1. **Node.js Alpine images**: Check Docker Hub for latest LTS Alpine tags
2. **Python slim images**: Check Docker Hub for latest slim tags
3. **nginx Alpine**: Check Docker Hub for latest Alpine tags
4. **GitHub Actions**: Check release pages for latest action versions
5. **Trivy**: Check aquasecurity/trivy-action releases

### Step 3: Analyze each component

Check each component against standards:

**Dockerfile Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Exists | Required for containerized projects | FAIL if missing |
| Multi-stage | Required (build + runtime stages) | FAIL if missing |
| HEALTHCHECK | Required for K8s probes | FAIL if missing |
| Non-root user | REQUIRED (not optional) | FAIL if missing |
| .dockerignore | Required | WARN if missing |
| .dockerignore `Dockerfile*` | Use glob to exclude all Dockerfile variants from context | WARN if only `Dockerfile` |
| Base image version | Latest stable (check Docker Hub) | WARN if outdated |
| Minimal base | Alpine for Node, slim for Python | WARN if bloated |

**Base Image Standards (verify latest before reporting):**

| Language | Build Image | Runtime Image | Size Target |
|----------|-------------|---------------|-------------|
| Node.js | `node:24-alpine` (LTS) | `nginx:1.27-alpine` | < 50MB |
| Python | `python:3.13-slim` | `python:3.13-slim` | < 150MB |
| Go | `golang:1.23-alpine` | `scratch` or `alpine:3.21` | < 20MB |
| Rust | `rust:1.84-alpine` | `alpine:3.21` | < 20MB |

**Security Hardening Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Non-root USER | Required (create dedicated user) | FAIL if missing |
| Read-only FS | `--read-only` or RO annotation | INFO if missing |
| No new privileges | `--security-opt=no-new-privileges` | INFO if missing |
| Drop capabilities | `--cap-drop=all` + explicit `--cap-add` | INFO if missing |
| No secrets in image | No ENV with sensitive data | FAIL if found |

**Build Workflow Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Workflow exists | container-build.yml or similar | FAIL if missing |
| checkout action | v4+ | WARN if older |
| build-push-action | v6+ | WARN if older |
| Multi-platform | linux/amd64,linux/arm64 | WARN if missing |
| Build caching | GHA cache enabled | WARN if missing |
| Security scan | Trivy/Grype in workflow | WARN if missing |
| `id-token: write` | Required when provenance/SBOM configured | WARN if missing |
| Cache scope | Explicit `scope=` for multi-image builds | WARN if missing |
| Scanner pinned | Trivy/Grype action pinned by SHA (not `@master`) | WARN if unpinned |

**Container Labels Standards (GHCR Integration):**

| Check | Standard | Severity |
|-------|----------|----------|
| `org.opencontainers.image.source` | Required - Links to repository | WARN if missing |
| `org.opencontainers.image.description` | Required - Package description | WARN if missing |
| `org.opencontainers.image.licenses` | Required - SPDX license | WARN if missing |

Run `/configure:dockerfile` for detailed Dockerfile checks if needed.

### Step 4: Generate compliance report

Print a formatted compliance report:

```
Container Infrastructure Compliance Report
==============================================
Project Type: frontend (detected)

Component Status:
  Dockerfile              PASS
  Build Workflow          PASS
  Registry Config         PASS
  Container Scanning      WARN (missing)
  Devcontainer           SKIP (not required)
  .dockerignore          PASS

Dockerfile Checks:
  Multi-stage             2 stages          PASS
  HEALTHCHECK             Present           PASS
  Base images             node:22, nginx    PASS

Build Workflow Checks:
  Workflow                container-build.yml PASS
  checkout                v4                PASS
  build-push-action       v6                PASS
  Multi-platform          amd64,arm64       PASS
  GHA caching             Enabled           PASS

Container Labels Checks:
  image.source            In metadata-action PASS
  image.description       Custom label set  PASS
  image.licenses          Not configured    WARN

Recommendations:
  - Add org.opencontainers.image.licenses label to workflow
  - Add Trivy or Grype vulnerability scanning to CI

Overall: 2 warnings, 1 info
```

If `--check-only`, stop here.

### Step 5: Apply fixes (if --fix or user confirms)

1. **Missing Dockerfile**: Run `/configure:dockerfile --fix`
2. **Missing build workflow**: Create from template in [REFERENCE.md](REFERENCE.md)
3. **Missing scanning**: Add Trivy scanning job
4. **Missing .dockerignore**: Create standard .dockerignore from [REFERENCE.md](REFERENCE.md)
5. **Outdated actions**: Update version numbers

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  container: "2025.1"
  dockerfile: "2025.1"
  container-workflow: "2025.1"
```

For detailed templates (Dockerfile, workflow, devcontainer, .dockerignore), see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick compliance check | `/configure:container --check-only` |
| Auto-fix all issues | `/configure:container --fix` |
| Dockerfile only | `/configure:container --check-only --component dockerfile` |
| Workflow only | `/configure:container --check-only --component workflow` |
| Scanning only | `/configure:container --fix --component scanning` |
| Find all Dockerfiles | `find . -maxdepth 2 \( -name 'Dockerfile' -o -name 'Dockerfile.*' \) 2>/dev/null` |

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |
| `--component <name>` | Check specific component only (dockerfile, workflow, registry, scanning, devcontainer) |

## Component Dependencies

```
Container Infrastructure
├── Dockerfile (required)
│   └── .dockerignore (recommended)
├── Build Workflow (required for CI/CD)
│   ├── Registry config
│   └── Multi-platform builds
├── Container Scanning (recommended)
│   └── SBOM generation (optional)
└── Devcontainer (optional)
    └── VS Code extensions
```

## Notes

- **Multi-platform builds**: Essential for M1/M2 Mac developers and ARM servers
- **GHCR**: GitHub Container Registry is preferred for GitHub-hosted projects
- **Trivy**: Recommended scanner for comprehensive vulnerability detection
- **Alpine vs Slim**: Use Alpine for Node.js/Go/Rust. Use slim (Debian) for Python (musl compatibility issues)
- **Non-root is mandatory**: Never run containers as root in production
- **Version pinning**: Always use specific version tags, never `latest`

## See Also

- `/configure:dockerfile` - Dockerfile-specific configuration
- `/configure:workflows` - GitHub Actions workflow configuration
- `/configure:skaffold` - Kubernetes development configuration
- `/configure:security` - Security scanning configuration
- `/configure:all` - Run all compliance checks
- `container-development` skill - Container best practices
- `ci-workflows` skill - CI/CD workflow patterns
