---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2026-01-19
description: Check and configure Dockerfile for project standards (minimal Alpine/slim, non-root, multi-stage)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <frontend|python|go|rust>]"
name: configure-dockerfile
---

# /configure:dockerfile

Check and configure Dockerfile against project standards with emphasis on **minimal images**, **non-root users**, and **multi-stage builds**.

## Context

- Dockerfiles: !`find . -maxdepth 1 \( -name 'Dockerfile' -o -name 'Dockerfile.*' -o -name '*.Dockerfile' \) 2>/dev/null`
- Dockerignore: !`test -f .dockerignore && echo "EXISTS" || echo "MISSING"`
- Project type: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) 2>/dev/null`
- Base images: !`grep -h '^FROM' Dockerfile Dockerfile.* *.Dockerfile 2>/dev/null | head -5`

## Parameters

Parse from command arguments:

- `--check-only`: Report compliance status without modifications
- `--fix`: Apply fixes automatically without prompting
- `--type <type>`: Override project type detection (frontend, python, go, rust)

## Execution

Execute this Dockerfile compliance check:

### Step 1: Detect project type and Dockerfiles

1. Find Dockerfile(s) in project root
2. Detect project type from context (package.json, pyproject.toml, go.mod, Cargo.toml)
3. Parse Dockerfile to analyze current configuration
4. Apply `--type` override if provided

### Step 2: Verify latest base image versions

Before flagging outdated base images, use WebSearch or WebFetch to verify latest versions:

1. **Node.js Alpine**: Check Docker Hub for latest LTS Alpine tags
2. **Python slim**: Check Docker Hub for latest slim tags
3. **nginx Alpine**: Check Docker Hub for latest Alpine tags
4. **Go Alpine**: Check Docker Hub for latest Alpine tags
5. **Rust Alpine**: Check Docker Hub for latest Alpine tags

### Step 3: Analyze compliance

Check the Dockerfile against these standards:

**Frontend (Node.js) Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Build base | `node:22-alpine` (LTS) | WARN if other |
| Runtime base | `nginx:1.27-alpine` | WARN if other |
| Multi-stage | Required | FAIL if missing |
| HEALTHCHECK | Required | FAIL if missing |
| Non-root user | Required | FAIL if missing |
| Build caching | `--mount=type=cache` recommended | INFO |
| OCI Labels | Required for GHCR integration | WARN if missing |

**Python Service Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Base image | `python:3.12-slim` | WARN if other |
| Multi-stage | Required for production | FAIL if missing |
| HEALTHCHECK | Required | FAIL if missing |
| Non-root user | Required | FAIL if missing |
| OCI Labels | Required for GHCR integration | WARN if missing |

**OCI Container Labels:**

| Label | Purpose | Severity |
|-------|---------|----------|
| `org.opencontainers.image.source` | Links to repository | WARN if missing |
| `org.opencontainers.image.description` | Package description | WARN if missing |
| `org.opencontainers.image.licenses` | SPDX license identifier | WARN if missing |
| `org.opencontainers.image.version` | Semantic version (via ARG) | INFO if missing |
| `org.opencontainers.image.revision` | Git commit SHA (via ARG) | INFO if missing |

### Step 4: Report results

Print a compliance report:

```
Dockerfile Compliance Report
================================
Project Type: <type> (detected)
Dockerfile: ./Dockerfile (found)

Configuration Checks:
  Build base      <image>           [PASS|WARN]
  Runtime base    <image>           [PASS|WARN]
  Multi-stage     <N> stages        [PASS|FAIL]
  HEALTHCHECK     <present|missing> [PASS|FAIL]
  Non-root user   <present|missing> [PASS|FAIL]
  Build caching   <enabled|missing> [PASS|INFO]

OCI Labels Checks:
  image.source       <present|missing> [PASS|WARN]
  image.description  <present|missing> [PASS|WARN]
  image.licenses     <present|missing> [PASS|WARN]

Recommendations:
  <list specific fixes needed>
```

If `--check-only`, stop here.

### Step 5: Apply fixes (if requested)

If `--fix` flag is set or user confirms:

1. **Missing Dockerfile**: Create from standard template (see Standard Templates below)
2. **Missing HEALTHCHECK**: Add standard healthcheck
3. **Missing multi-stage**: Suggest restructure (manual fix needed)
4. **Outdated base images**: Update FROM lines
5. **Missing OCI labels**: Add LABEL instructions

### Step 6: Update standards tracking

Update `.project-standards.yaml`:

```yaml
components:
  dockerfile: "2025.1"
```

## Standard Templates

### Frontend (Node/Vite/nginx)

```dockerfile
FROM node:22-alpine AS build

ARG SENTRY_AUTH_TOKEN
ARG VITE_SENTRY_DSN

WORKDIR /app

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci

COPY . .
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/app/node_modules/.vite \
    npm run build

FROM nginx:1.27-alpine

# OCI labels for GHCR integration
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production frontend application" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Your Organization"

# Dynamic labels via build args
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1
```

### Python Service

```dockerfile
FROM python:3.12-slim AS builder

WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN pip install uv && uv sync --frozen --no-dev

FROM python:3.12-slim

# OCI labels for GHCR integration
LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production Python API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Your Organization"

ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN useradd --create-home appuser
USER appuser
WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --chown=appuser:appuser . .

ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |
| `--type <type>` | Override project type (frontend, python) |

## Notes

- Node 22 is current LTS (recommended over 24)
- nginx:1.27-alpine preferred over debian variant
- HEALTHCHECK is critical for Kubernetes liveness probes
- Build caching significantly improves CI/CD speed
- Non-root user is mandatory for production containers

## See Also

- `/configure:container` - Comprehensive container infrastructure
- `/configure:skaffold` - Kubernetes development configuration
- `/configure:all` - Run all compliance checks
- `container-development` skill - Container best practices
