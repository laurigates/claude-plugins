---
created: 2025-12-16
modified: 2026-01-15
reviewed: 2026-01-15
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

### Image Optimization Principles

**Right-Size Your Base Image**:
- Go: Use `scratch` or `distroless` for production (2-5MB final images)
- Node.js: Use `alpine` variants (reduces from ~900MB to ~100MB)
- Python: Use `slim` variants, not Alpine (musl compatibility issues)

**Optimization Journey** (typical Go app):
1. Full base image (golang:1.23): 846MB
2. Alpine base (golang:1.23-alpine): 312MB (63% reduction)
3. Multi-stage build (Alpine runtime): 15MB (95% reduction)
4. Stripped binary + flags: 8MB (47% reduction)
5. Scratch/distroless: 2.5MB (68% reduction)

**Result**: 99.7% size reduction with improved security and performance

## Version Checking

**CRITICAL**: Before using base images, verify latest versions:
- **Node.js Alpine**: Check [Docker Hub node](https://hub.docker.com/_/node) for latest LTS
- **Python slim**: Check [Docker Hub python](https://hub.docker.com/_/python) for latest
- **Go Alpine**: Check [Docker Hub golang](https://hub.docker.com/_/golang) for latest
- **nginx Alpine**: Check [Docker Hub nginx](https://hub.docker.com/_/nginx)
- **Distroless**: Check [Google distroless](https://github.com/GoogleContainerTools/distroless) for latest

Use WebSearch or WebFetch to verify current versions.

## Language-Specific Patterns

### Go (Production-Optimized)

**Recommended**: Scratch or distroless for minimal images (2.5-5MB)

```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .

# Optimized build: strip debug info, remove paths
RUN CGO_ENABLED=0 GOOS=linux go build \
    -a \
    -installsuffix cgo \
    -ldflags="-w -s" \
    -trimpath \
    -o main .

# Runtime stage - scratch for absolute minimum
FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /app/main /main
EXPOSE 8080
CMD ["/main"]
```

**Build flags explained**:
- `CGO_ENABLED=0`: Static binary, no dynamic dependencies
- `-ldflags="-w -s"`: Strip debug info (~40% size reduction)
- `-trimpath`: Remove local filesystem paths (security)

See REFERENCE.md "Go Binary Optimization" for complete 846MB→2.5MB optimization journey.

### Node.js (Multi-Stage with Non-Root Alpine)

**Recommended**: Alpine with non-root user (~50-100MB)

```dockerfile
# Build stage - use Alpine for minimal size
FROM node:24-alpine AS build

WORKDIR /app
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build

# Runtime stage - minimal nginx Alpine
FROM nginx:1.27-alpine

# Create non-root user BEFORE copying files
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

COPY --from=build /app/dist /usr/share/nginx/html

# Security: Make nginx dirs writable by non-root
RUN chown -R appuser:appgroup /var/cache/nginx /var/run /var/log/nginx

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
```

### Python (Slim with Non-Root)

**Recommended**: Use `slim` not `alpine` (musl libc compatibility issues)

```dockerfile
# Build stage
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .

# Runtime stage
FROM python:3.11-slim
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --from=builder --chown=appuser:appgroup /app .
ENV PATH="/app/.venv/bin:$PATH"
USER appuser
CMD ["python", "-m", "myapp"]
```

**Security Best Practices (Mandatory)**
- **Non-root user**: REQUIRED - never run as root in production
- **Minimal base images**:
  - Go: `scratch` or `distroless` (0 CVEs vs 63 CVEs in Debian-based)
  - Node.js/Rust: `alpine` (12 CVEs vs 63 CVEs in Debian-based)
  - Python: `slim` (8 CVEs vs 63 CVEs in full image)
- **Multi-stage builds**: REQUIRED - keep build tools out of runtime
- **Binary stripping**: Use `-ldflags="-w -s"` for Go to remove debug info
- **HEALTHCHECK**: REQUIRED for Kubernetes probes
- **Vulnerability scanning**: Use Trivy or Grype in CI
- **Version pinning**: Always use specific tags, never `latest`
- **.dockerignore**: REQUIRED - prevents secrets, .env, .git from entering image

**Impact of Optimization** (real-world metrics):
- **Image size**: 99.7% reduction (846MB → 2.5MB for Go)
- **Security**: 100% reduction in CVEs (63 → 0 for scratch/distroless)
- **Pull time**: 98% faster (52s → 1s)
- **Startup time**: 62% faster (2.1s → 0.8s)
- **Memory usage**: 73% lower (480MB → 128MB)
- **Storage costs**: 99.8% reduction

**12-Factor App Principles**
- Configuration via environment variables
- Stateless processes
- Explicit dependencies
- Port binding for services
- Graceful shutdown handling

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

## Related Commands

- `/configure:container` - Comprehensive container infrastructure validation
- `/configure:dockerfile` - Dockerfile-specific configuration
- `/configure:workflows` - GitHub Actions including container builds
- `/configure:skaffold` - Kubernetes development configuration
