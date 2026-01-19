---
created: 2025-12-16
modified: 2026-01-19
reviewed: 2026-01-19
description: Check and configure container infrastructure (builds, registry, scanning, devcontainer)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, SlashCommand, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--component <dockerfile|workflow|registry|scanning|devcontainer>]"
---

# /configure:container

Check and configure comprehensive container infrastructure against FVH (Forum Virium Helsinki) standards with emphasis on **minimal images**, **non-root users**, and **security hardening**.

## Context

This command validates and configures the complete container ecosystem including:
- **Dockerfile** - Multi-stage builds, minimal Alpine/slim images, non-root users, healthchecks
- **Build workflows** - GitHub Actions container build pipelines with security scanning
- **Registry** - Container registry configuration (GHCR)
- **Scanning** - Container vulnerability scanning (Trivy/Grype)
- **Devcontainer** - Development container configuration
- **Version checking** - Validates base images and dependencies are up-to-date

**Skills referenced**: `container-development`, `fvh-ci-workflows`, `github-actions-auth-security`

## Security Philosophy

**Minimal Attack Surface**: Smaller images = fewer vulnerabilities. Use Alpine (~5MB) for Node.js, slim (~50MB) for Python.

**Non-Root by Default**: Running as root in containers is a critical security risk. ALL containers MUST run as non-root users.

**Multi-Stage Required**: Separate build and runtime environments. Build tools, dev dependencies, and source code should NOT be in production images.

**Immutable Infrastructure**: Read-only root filesystem where possible. Use tmpfs for write-needed directories.

## Workflow

### Phase 1: Detection

1. Check for container-related files:
   - `Dockerfile` / `Dockerfile.*` / `*.Dockerfile`
   - `.github/workflows/*container*`, `*docker*`, `*build*`
   - `.devcontainer/devcontainer.json`
   - `skaffold.yaml`
   - `.dockerignore`
2. Detect project type (frontend, python, infrastructure)
3. Identify container registry usage from workflows

### Phase 1.5: Version Lookup

**CRITICAL**: Before analyzing, fetch latest versions from authoritative sources:

1. **Node.js Alpine images**: Check [Docker Hub node](https://hub.docker.com/_/node) for latest LTS Alpine tags
2. **Python slim images**: Check [Docker Hub python](https://hub.docker.com/_/python) for latest slim tags
3. **nginx Alpine**: Check [Docker Hub nginx](https://hub.docker.com/_/nginx) for latest Alpine tags
4. **GitHub Actions**: Check release pages for latest action versions
5. **Trivy**: Check [aquasecurity/trivy-action](https://github.com/aquasecurity/trivy-action) releases

Use WebSearch or WebFetch to verify current versions before flagging outdated images.

### Phase 2: Component Analysis

**Dockerfile Standards:**
Run `/configure:dockerfile` checks (or reference results)

| Check | Standard | Severity |
|-------|----------|----------|
| Exists | Required for containerized projects | FAIL if missing |
| Multi-stage | Required (build + runtime stages) | FAIL if missing |
| HEALTHCHECK | Required for K8s probes | FAIL if missing |
| **Non-root user** | **REQUIRED** (not optional) | **FAIL if missing** |
| .dockerignore | Required | WARN if missing |
| Base image version | Latest stable (check Docker Hub) | WARN if outdated |
| Minimal base | Alpine for Node, slim for Python | WARN if bloated |

**Base Image Standards (check latest before reporting):**

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
| checkout action | v4+ (check latest) | WARN if older |
| setup-buildx-action | v3+ (check latest) | WARN if older |
| build-push-action | v6+ (check latest) | WARN if older |
| Multi-platform | linux/amd64,linux/arm64 | WARN if missing |
| Build caching | GHA cache enabled | WARN if missing |
| Permissions | Explicit `packages: write` | WARN if missing |
| Security scan | Trivy/Grype in workflow | WARN if missing |

**Registry Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Registry | GHCR (ghcr.io) | INFO if other |
| login-action | v3+ (check latest) | WARN if older |
| metadata-action | v5+ (check latest) | WARN if older |
| Tags | Semantic versioning + SHA | INFO |
| SBOM attestation | sigstore/cosign | INFO if missing |

**Container Labels Standards (GHCR Integration):**

| Check | Standard | Severity |
|-------|----------|----------|
| `org.opencontainers.image.source` | **Required** - Links to repository | WARN if missing |
| `org.opencontainers.image.description` | **Required** - Package description | WARN if missing |
| `org.opencontainers.image.licenses` | **Required** - SPDX license | WARN if missing |
| `org.opencontainers.image.version` | Recommended - Semantic version | INFO if missing |
| `org.opencontainers.image.revision` | Recommended - Git commit SHA | INFO if missing |
| `org.opencontainers.image.created` | Recommended - Build timestamp | INFO if missing |
| Labels in Dockerfile or workflow | Either LABEL instructions or metadata-action | WARN if neither |

**Label Sources:**
- **Dockerfile**: Static `LABEL` instructions and `ARG`-based dynamic labels
- **Build workflow**: `docker/metadata-action` auto-generates labels from repo metadata

**Scanning Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Vulnerability scan | Trivy or Grype | WARN if missing |
| Scan frequency | On every PR | WARN if not |
| SBOM generation | Required for supply chain | WARN if missing |
| Severity threshold | Block on CRITICAL/HIGH | INFO |
| SARIF upload | For GitHub Security tab | INFO if missing |

**Devcontainer Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| devcontainer.json | Recommended for complex projects | INFO if missing |
| Base image | mcr.microsoft.com/devcontainers | INFO |
| Features | Language-appropriate features | INFO |
| Extensions | Project-relevant VS Code extensions | INFO |

### Phase 3: Report Generation

```
FVH Container Infrastructure Compliance Report
==============================================
Project Type: frontend (detected)

Component Status:
  Dockerfile              ✅ PASS
  Build Workflow          ✅ PASS
  Registry Config         ✅ PASS
  Container Scanning      ⚠️ WARN (missing)
  Devcontainer           ⏭️ SKIP (not required)
  .dockerignore          ✅ PASS

Dockerfile Checks:
  Multi-stage             2 stages          ✅ PASS
  HEALTHCHECK             Present           ✅ PASS
  Base images             node:22, nginx    ✅ PASS

Build Workflow Checks:
  Workflow                container-build.yml ✅ PASS
  checkout                v4                ✅ PASS
  build-push-action       v6                ✅ PASS
  Multi-platform          amd64,arm64       ✅ PASS
  GHA caching             Enabled           ✅ PASS

Registry Checks:
  Registry                ghcr.io           ✅ PASS
  Login action            v3                ✅ PASS
  Metadata action         v5                ✅ PASS

Container Labels Checks:
  image.source            In metadata-action ✅ PASS
  image.description       Custom label set  ✅ PASS
  image.licenses          Not configured    ⚠️ WARN
  image.version           Auto from tags    ✅ PASS
  image.revision          Auto from SHA     ✅ PASS

Scanning Checks:
  Vulnerability scan      Not configured    ⚠️ WARN
  SBOM generation         Not configured    ℹ️ INFO

Recommendations:
  - Add org.opencontainers.image.licenses label to workflow
  - Add Trivy or Grype vulnerability scanning to CI
  - Consider SBOM generation for supply chain security

Overall: 2 warnings, 1 info
```

### Phase 4: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing Dockerfile**: Run `/configure:dockerfile --fix`
2. **Missing build workflow**: Create from template
3. **Missing scanning**: Add Trivy scanning job
4. **Missing .dockerignore**: Create standard .dockerignore
5. **Outdated actions**: Update version numbers

### Phase 5: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  container: "2025.1"
  dockerfile: "2025.1"
  container-workflow: "2025.1"
```

## FVH Standard Templates

### Container Build Workflow (with Security Scanning)

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
      security-events: write  # For scanning results

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
          # Custom labels for GHCR integration (source/revision/created auto-generated)
          labels: |
            org.opencontainers.image.title=${{ github.event.repository.name }}
            org.opencontainers.image.description=${{ github.event.repository.description }}
            org.opencontainers.image.vendor=Forum Virium Helsinki
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha

      - uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      # Scan the built image for vulnerabilities
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
```

### .dockerignore Template

```
# Git
.git
.gitignore

# CI/CD
.github
.gitlab-ci.yml

# IDE
.idea
.vscode
*.swp
*.swo

# Dependencies (rebuilt in container)
node_modules
.venv
__pycache__
*.pyc

# Build artifacts
dist
build
target

# Test and coverage
coverage
.coverage
.pytest_cache
.nyc_output

# Documentation
docs
*.md
!README.md

# Environment
.env
.env.*
*.local

# Temporary
tmp
temp
*.tmp
*.log
```

### Dockerfile Template (Node.js/Frontend - Non-Root Alpine)

```dockerfile
# Build stage - use Alpine for minimal size
FROM node:24-alpine AS build

WORKDIR /app

# Copy dependency files first for better caching
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --only=production

COPY . .
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/app/node_modules/.vite \
    npm run build

# Runtime stage - minimal nginx Alpine
FROM nginx:1.27-alpine

# OCI labels for GHCR integration (static labels)
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production frontend application" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Dynamic labels via build args
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copy built assets
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/

# Security: Make nginx dirs writable by non-root user
RUN chown -R appuser:appgroup /var/cache/nginx /var/run /var/log/nginx && \
    chmod -R 755 /var/cache/nginx /var/run /var/log/nginx

# Switch to non-root user
USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
```

### Dockerfile Template (Python - Non-Root Slim)

```dockerfile
# Build stage
FROM python:3.13-slim AS builder

WORKDIR /app

# Install uv for fast dependency resolution
RUN pip install --no-cache-dir uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies (no dev deps for production)
RUN uv sync --frozen --no-dev

# Runtime stage
FROM python:3.13-slim

# OCI labels for GHCR integration (static labels)
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production Python API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Dynamic labels via build args
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Create non-root user BEFORE copying files
RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -s /bin/false appuser

WORKDIR /app

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code (owned by non-root user)
COPY --chown=appuser:appgroup . .

# Set environment
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Switch to non-root user
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Dockerfile Template (Go - Scratch/Distroless)

```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Download dependencies
COPY go.mod go.sum ./
RUN go mod download

# Build static binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server ./cmd/server

# Runtime stage - scratch for minimal attack surface
FROM scratch

# OCI labels for GHCR integration
# Note: For scratch images, labels are best applied via build command or workflow
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production Go service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Copy CA certificates for HTTPS
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary
COPY --from=builder /app/server /server

# Non-root user (numeric for scratch)
USER 1001:1001

EXPOSE 8080

ENTRYPOINT ["/server"]
```

### Devcontainer Template (Node/Frontend)

```json
{
  "name": "Project Dev Container",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:24",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "biomejs.biome",
        "ms-azuretools.vscode-docker"
      ]
    }
  },
  "postCreateCommand": "npm install",
  "forwardPorts": [3000, 5173],
  "remoteUser": "node"
}
```

### Devcontainer Template (Python)

```json
{
  "name": "Python Dev Container",
  "image": "mcr.microsoft.com/devcontainers/python:3.13",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "ms-azuretools.vscode-docker"
      ]
    }
  },
  "postCreateCommand": "pip install uv && uv sync",
  "forwardPorts": [8000],
  "remoteUser": "vscode"
}
```

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
- **Devcontainer**: Recommended for teams to ensure consistent dev environments
- **Alpine vs Slim**: Use Alpine for Node.js/Go/Rust. Use slim (Debian) for Python (musl compatibility issues)
- **Non-root is mandatory**: Never run containers as root in production
- **Version pinning**: Always use specific version tags, never `latest`

## Security Best Practices References

- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Snyk Container Security Best Practices](https://snyk.io/blog/10-docker-image-security-best-practices/)
- [Sysdig Dockerfile Best Practices](https://sysdig.com/blog/dockerfile-best-practices/)

## See Also

- `/configure:dockerfile` - Dockerfile-specific configuration
- `/configure:workflows` - GitHub Actions workflow configuration
- `/configure:skaffold` - Kubernetes development configuration
- `/configure:security` - Security scanning configuration
- `/configure:all` - Run all FVH compliance checks
- `container-development` skill - Container best practices
- `fvh-ci-workflows` skill - CI/CD workflow patterns
