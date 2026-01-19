---
created: 2025-12-16
modified: 2026-01-19
reviewed: 2026-01-19
name: container-development
description: |
  Container development with Docker, Dockerfiles, 12-factor principles, multi-stage
  builds, and Skaffold workflows. Enforces MANDATORY non-root users, minimal Alpine/slim
  base images, and security hardening. Covers containerization, orchestration, and secure
  image construction.
  Use when user mentions Docker, Dockerfile, containers, docker-compose, multi-stage
  builds, container images, container security, or 12-factor app principles.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebSearch, WebFetch
---

# Container Development

Expert knowledge for containerization and orchestration with focus on **security-first**, lean container images and 12-factor app methodology.

## Security Philosophy (Non-Negotiable)

**Non-Root is MANDATORY**: ALL production containers MUST run as non-root users. This is not optional.

**Minimal Base Images**: Use Alpine (~5MB) for Node.js/Go/Rust. Use slim (~50MB) for Python (musl compatibility issues with Alpine).

**Multi-Stage Builds Required**: Separate build and runtime environments. Build tools should NOT be in production images.

## Core Expertise

**Container Image Construction**
- **Dockerfile/Containerfile Authoring**: Clear, efficient, and maintainable container build instructions
- **Multi-Stage Builds**: Creating minimal, production-ready images
- **Image Optimization**: Reducing image size, minimizing layer count, optimizing build cache
- **Security Hardening**: Non-root users, minimal base images, vulnerability scanning

**Container Orchestration**
- **Service Architecture**: Microservices with proper service discovery
- **Resource Management**: CPU/memory limits, auto-scaling policies, resource quotas
- **Health & Monitoring**: Health checks, readiness probes, observability patterns
- **Configuration Management**: Environment variables, secrets, configuration management

## Key Capabilities

- **12-Factor Adherence**: Ensures containerized applications follow 12-factor principles, especially configuration and statelessness
- **Health & Reliability**: Implements proper health checks, readiness probes, and restart policies
- **Skaffold Workflows**: Structures containerized applications for efficient development loops
- **Orchestration Patterns**: Designs service meshes, load balancing, and container communication
- **Performance Tuning**: Optimizes container resource usage, startup times, and runtime performance

## Image Crafting Process

1. **Analyze**: Understand application dependencies and build process
2. **Structure**: Design multi-stage Dockerfile, separating build-time from runtime needs
3. **Ignore**: Create comprehensive `.dockerignore` file
4. **Build & Scan**: Build image and scan for vulnerabilities
5. **Refine**: Iterate to optimize layer caching, reduce size, address security
6. **Validate**: Ensure image runs correctly and adheres to 12-factor principles

## Best Practices

### Core Optimization Principles

**1. Multi-Stage Builds** (MANDATORY):
- Separate build-time dependencies from runtime
- Keep build tools out of production images
- Typical reduction: 60-90% smaller final images

**2. Minimal Base Images**:
- Start with the smallest base that works
- Prefer Alpine for most languages (except Python)
- Consider distroless for maximum security

**3. Non-Root Users** (MANDATORY):
- Always create and use non-root user
- Set UID/GID explicitly (e.g., 1001)
- Security compliance requirement

**4. .dockerignore** (MANDATORY):
- Exclude `.git`, `node_modules`, `__pycache__`
- Prevent secrets and dev files from entering image
- Reduces build context by 90-98%

**5. Layer Optimization**:
- Copy dependency manifests separately from source
- Put frequently changing layers last
- Combine related RUN commands with `&&`

## Version Checking

**CRITICAL**: Before using base images, verify latest versions:
- **Node.js Alpine**: Check [Docker Hub node](https://hub.docker.com/_/node) for latest LTS
- **Python slim**: Check [Docker Hub python](https://hub.docker.com/_/python) for latest
- **Go Alpine**: Check [Docker Hub golang](https://hub.docker.com/_/golang) for latest
- **nginx Alpine**: Check [Docker Hub nginx](https://hub.docker.com/_/nginx)
- **Distroless**: Check [Google distroless](https://github.com/GoogleContainerTools/distroless) for latest

Use WebSearch or WebFetch to verify current versions.

## Language-Specific Optimization

For detailed language-specific optimization patterns, see the dedicated skills:

| Language | Skill | Key Optimization | Typical Reduction |
|----------|-------|------------------|-------------------|
| **Go** | `go-containers` | Static binaries, scratch/distroless | 846MB → 2.5MB (99.7%) |
| **Node.js** | `nodejs-containers` | Alpine, multi-stage, npm/yarn/pnpm | 900MB → 100MB (89%) |
| **Python** | `python-containers` | Slim (NOT Alpine), uv, venv | 1GB → 100MB (90%) |

### Quick Base Image Guide

**Choose the right base image**:
- **Go**: `scratch` or `distroless/static` (2-5MB)
- **Node.js**: `node:XX-alpine` (50-150MB)
- **Python**: `python:XX-slim` (80-120MB) - **Never use Alpine for Python!**
- **Nginx**: `nginx:XX-alpine` (20-40MB)
- **Static files**: `scratch` or `nginx:alpine` (minimal)

### Multi-Stage Build Template

```dockerfile
# Build stage - includes all build tools
FROM <language>:<version> AS builder
WORKDIR /app

# Copy dependency manifests first (better caching)
COPY package.json package-lock.json ./  # or go.mod, requirements.txt, etc.

# Install dependencies
RUN <install-command>

# Copy source code
COPY . .

# Build application
RUN <build-command>

# Runtime stage - minimal
FROM <minimal-base>
WORKDIR /app

# Create non-root user
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

# Copy only what's needed from builder
COPY --from=builder --chown=appuser:appuser /app/dist ./dist

USER appuser
EXPOSE <port>

HEALTHCHECK --interval=30s CMD <health-check-command>

CMD [<start-command>]
```

**Security Requirements (Mandatory)**
- **Non-root user**: REQUIRED - never run as root in production
- **Minimal base images**: Choose smallest viable base
  - Typical CVE reduction: 50-100% (full base: 50-70 CVEs → minimal: 0-12 CVEs)
  - No shell = no shell injection attacks
  - No package manager = no supply chain attacks
- **Multi-stage builds**: REQUIRED - keep build tools out of runtime
- **HEALTHCHECK**: REQUIRED for Kubernetes liveness/readiness probes
- **Vulnerability scanning**: Use Trivy, Grype, or Docker Scout in CI
- **Version pinning**: Always use specific tags (e.g., `node:20.10-alpine`), never `latest`
- **.dockerignore**: REQUIRED - prevents secrets, .env, .git from entering image

**Typical Impact of Full Optimization**:
- **Image size**: 85-99% reduction
- **Security**: 70-100% fewer CVEs
- **Pull time**: 80-98% faster
- **Build time**: 40-60% faster (with proper caching)
- **Memory usage**: 60-80% lower
- **Storage costs**: 90-99% reduction

**12-Factor App Principles**
- Configuration via environment variables
- Stateless processes
- Explicit dependencies
- Port binding for services
- Graceful shutdown handling

## Container Labels (OCI Annotations)

Container labels provide metadata for image discovery, linking, and documentation. **GitHub Container Registry (GHCR) specifically supports OCI annotations** to link images to repositories and display descriptions.

### Required Labels for GHCR

| Label | Purpose | Example |
|-------|---------|---------|
| `org.opencontainers.image.source` | **Links image to repository** (enables GHCR features) | `https://github.com/owner/repo` |
| `org.opencontainers.image.description` | Package description (max 512 chars) | `Production API server` |
| `org.opencontainers.image.licenses` | SPDX license identifier (max 256 chars) | `MIT`, `Apache-2.0` |

### Recommended Labels

| Label | Purpose | Example |
|-------|---------|---------|
| `org.opencontainers.image.version` | Semantic version | `1.2.3` |
| `org.opencontainers.image.revision` | Git commit SHA | `abc1234` |
| `org.opencontainers.image.created` | Build timestamp (RFC 3339) | `2025-01-19T12:00:00Z` |
| `org.opencontainers.image.title` | Human-readable name | `My Application` |
| `org.opencontainers.image.vendor` | Organization name | `Forum Virium Helsinki` |
| `org.opencontainers.image.url` | Project homepage | `https://example.com` |
| `org.opencontainers.image.documentation` | Documentation URL | `https://docs.example.com` |

### Adding Labels in Dockerfile

```dockerfile
# Static labels (set at build time)
LABEL org.opencontainers.image.source="https://github.com/owner/repo" \
      org.opencontainers.image.description="Production API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Dynamic labels (via build args)
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"
```

### Adding Labels at Build Time

```bash
docker build \
  --label "org.opencontainers.image.source=https://github.com/owner/repo" \
  --label "org.opencontainers.image.description=My container image" \
  --label "org.opencontainers.image.licenses=MIT" \
  --build-arg VERSION=1.2.3 \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  -t myapp:1.2.3 .
```

### GitHub Actions with docker/metadata-action

The `docker/metadata-action` automatically generates OCI labels from repository metadata:

```yaml
- id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    labels: |
      org.opencontainers.image.title=My Application
      org.opencontainers.image.description=Production API server
      org.opencontainers.image.vendor=Forum Virium Helsinki

- uses: docker/build-push-action@v6
  with:
    labels: ${{ steps.meta.outputs.labels }}
```

**Auto-generated labels by metadata-action:**
- `org.opencontainers.image.source` (from repository URL)
- `org.opencontainers.image.revision` (from commit SHA)
- `org.opencontainers.image.created` (build timestamp)
- `org.opencontainers.image.version` (from tags/refs)

**Skaffold Preference**
- Favor Skaffold over Docker Compose for local development
- Continuous development loop with hot reload
- Production-like local environment

## Agentic Optimizations

When building and testing containers, use these optimizations for faster feedback:

| Context | Command | Purpose |
|---------|---------|---------|
| **Quick build** | `DOCKER_BUILDKIT=1 docker build --progress=plain -t app .` | BuildKit with plain output |
| **Build with cache** | `docker build --cache-from app:latest -t app:new .` | Reuse layers from previous builds |
| **Security scan** | `docker scout cves app:latest \| head -50` | Quick vulnerability check |
| **Size analysis** | `docker images app --format "{{.Size}}"` | Check image size |
| **Layer inspection** | `docker history app:latest --human --no-trunc` | Analyze layer sizes |
| **Build without cache** | `docker build --no-cache --progress=plain -t app .` | Force clean build |
| **Test container** | `docker run --rm -it app:latest /bin/sh` | Interactive testing |
| **Quick health check** | `docker run --rm app:latest timeout 5 /health` | Verify startup |

**Build optimization flags**:
- `--target=<stage>`: Build specific stage only (faster iteration)
- `--build-arg BUILDKIT_INLINE_CACHE=1`: Enable inline cache
- `--secret id=key,src=file`: Mount secrets without including in image

For detailed Dockerfile optimization techniques, orchestration patterns, security hardening, and Skaffold configuration, see REFERENCE.md.

## Related Skills

**Language-Specific Container Optimization**:
- `go-containers` - Go static binaries, scratch/distroless (846MB → 2.5MB)
- `nodejs-containers` - Node.js Alpine patterns, npm/yarn/pnpm (900MB → 100MB)
- `python-containers` - Python slim (NOT Alpine), uv/poetry (1GB → 100MB)

## Related Commands

- `/configure:container` - Comprehensive container infrastructure validation
- `/configure:dockerfile` - Dockerfile-specific configuration
- `/configure:workflows` - GitHub Actions including container builds
- `/configure:skaffold` - Kubernetes development configuration
