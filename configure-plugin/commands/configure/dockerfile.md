---
created: 2025-12-16
modified: 2026-01-19
reviewed: 2026-01-19
description: Check and configure Dockerfile for FVH standards (minimal Alpine/slim, non-root, multi-stage)
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <frontend|python|go|rust>]"
---

# /configure:dockerfile

Check and configure Dockerfile against FVH (Forum Virium Helsinki) standards with emphasis on **minimal images**, **non-root users**, and **multi-stage builds**.

## Context

This command validates Dockerfile configuration for Node.js frontend, Python, Go, and Rust service projects.

**Skills referenced**: `container-development`

## Version Checking

**CRITICAL**: Before flagging outdated base images, verify latest versions:

1. **Node.js Alpine**: Check [Docker Hub node](https://hub.docker.com/_/node) for latest LTS Alpine tags
2. **Python slim**: Check [Docker Hub python](https://hub.docker.com/_/python) for latest slim tags
3. **nginx Alpine**: Check [Docker Hub nginx](https://hub.docker.com/_/nginx) for latest Alpine tags
4. **Go Alpine**: Check [Docker Hub golang](https://hub.docker.com/_/golang) for latest Alpine tags
5. **Rust Alpine**: Check [Docker Hub rust](https://hub.docker.com/_/rust) for latest Alpine tags

Use WebSearch or WebFetch to verify current base image versions before reporting outdated images.

## Security Requirements

**Non-negotiable security standards:**
- **Non-root user**: ALL containers MUST run as non-root (FAIL if missing)
- **Multi-stage builds**: Required to minimize attack surface (FAIL if missing)
- **Minimal base images**: Alpine for Node.js/Go/Rust, slim for Python
- **HEALTHCHECK**: Required for Kubernetes probes

## Workflow

### Phase 1: Detection

1. Find Dockerfile(s) in project root
2. Detect project type from context (package.json, pyproject.toml)
3. Parse Dockerfile to analyze configuration

### Phase 2: Compliance Analysis

**Frontend (Node.js) Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Build base | `node:22-alpine` (LTS) | WARN if other |
| Runtime base | `nginx:1.27-alpine` | WARN if other |
| Multi-stage | Required | FAIL if missing |
| HEALTHCHECK | Required | FAIL if missing |
| Build caching | `--mount=type=cache` recommended | INFO |
| EXPOSE | Should match nginx port | INFO |
| **OCI Labels** | Required for GHCR integration | WARN if missing |

**Python Service Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Base image | `python:3.12-slim` | WARN if other |
| Multi-stage | Required for production | FAIL if missing |
| HEALTHCHECK | Required | FAIL if missing |
| Non-root user | Recommended | WARN if missing |
| Poetry/uv | Modern package manager | INFO |
| **OCI Labels** | Required for GHCR integration | WARN if missing |

**OCI Container Labels Standards:**

| Label | Purpose | Severity |
|-------|---------|----------|
| `org.opencontainers.image.source` | Links to repository (enables GHCR features) | WARN if missing |
| `org.opencontainers.image.description` | Package description (max 512 chars) | WARN if missing |
| `org.opencontainers.image.licenses` | SPDX license identifier | WARN if missing |
| `org.opencontainers.image.version` | Semantic version (via ARG) | INFO if missing |
| `org.opencontainers.image.revision` | Git commit SHA (via ARG) | INFO if missing |
| `org.opencontainers.image.created` | Build timestamp (via ARG) | INFO if missing |

**Note**: Labels can be in Dockerfile (`LABEL` instruction) or applied via `docker/metadata-action` in workflows.

### Phase 3: Report Generation

```
FVH Dockerfile Compliance Report
================================
Project Type: frontend (detected)
Dockerfile: ./Dockerfile (found)

Configuration Checks:
  Build base      node:24-alpine    ⚠️ WARN (standard: node:22-alpine)
  Runtime base    nginx:1.27-alpine ✅ PASS
  Multi-stage     2 stages          ✅ PASS
  HEALTHCHECK     Present           ✅ PASS
  Build caching   npm cache         ✅ PASS
  EXPOSE          80                ✅ PASS

OCI Labels Checks:
  image.source    Present           ✅ PASS
  image.description Present         ✅ PASS
  image.licenses  Not found         ⚠️ WARN
  image.version   Via ARG           ✅ PASS
  image.revision  Via ARG           ✅ PASS

Recommendations:
  - Consider using Node 22 LTS for stability
  - Add org.opencontainers.image.licenses label
```

### Phase 4: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing Dockerfile**: Create from FVH template
2. **Missing HEALTHCHECK**: Add standard healthcheck
3. **Missing multi-stage**: Suggest restructure (manual fix needed)
4. **Outdated base images**: Update FROM lines

**HEALTHCHECK Template (nginx):**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost/health || exit 1
```

### Phase 5: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
components:
  dockerfile: "2025.1"
```

## FVH Standard Templates

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
      org.opencontainers.image.vendor="Forum Virium Helsinki"

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
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Dynamic labels via build args
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

## See Also

- `/configure:skaffold` - Kubernetes development configuration
- `/configure:all` - Run all FVH compliance checks
- `container-development` skill - Container best practices
