# Container Development Reference

Comprehensive reference for Docker multi-stage builds, 12-factor app principles, security best practices, Skaffold workflows, and Docker Compose patterns.

## Table of Contents

- [Multi-Stage Build Patterns](#multi-stage-build-patterns)
- [12-Factor App Principles](#12-factor-app-principles)
- [Security Best Practices](#security-best-practices)
- [Skaffold Workflows](#skaffold-workflows)
- [Docker Compose Patterns](#docker-compose-patterns)
- [Performance Optimization](#performance-optimization)
- [Advanced Dockerfile Patterns](#advanced-dockerfile-patterns)

---

## Multi-Stage Build Patterns

Multi-stage builds separate build-time dependencies from runtime, dramatically reducing image sizes (60-95% reduction typical).

### Generic Multi-Stage Template

```dockerfile
# Build stage - includes all build tools and dependencies
FROM <build-image>:<version> AS builder
WORKDIR /app

# Copy dependency manifests first (better layer caching)
COPY <dependency-files> ./

# Install dependencies
RUN <install-dependencies-command>

# Copy source code
COPY . .

# Build application
RUN <build-command>

# Runtime stage - minimal base image
FROM <runtime-image>:<version>
WORKDIR /app

# Create non-root user
RUN <create-user-command>

# Copy only compiled/built artifacts from builder
COPY --from=builder --chown=<user>:<group> /app/<artifacts> ./

# Set user
USER <user>

# Health check
HEALTHCHECK --interval=30s CMD <health-check-command>

# Start application
CMD [<start-command>]
```

### Language-Specific Examples

For detailed multi-stage build patterns optimized for specific languages:
- **Go**: See `go-containers` skill - scratch/distroless patterns
- **Node.js**: See `nodejs-containers` skill - npm/yarn/pnpm patterns
- **Python**: See `python-containers` skill - uv/poetry/pip patterns

### Optimized Layer Caching

```dockerfile
# Bad: Invalidates cache on any file change
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install

# Good: Cache dependencies separately
FROM node:20-alpine
WORKDIR /app
# Copy only dependency files first
COPY package*.json ./
RUN npm ci --only=production
# Copy application code last
COPY . .
CMD ["node", "index.js"]
```

### Build-Time Variables

```dockerfile
FROM alpine:latest AS builder

# Build arguments
ARG VERSION=latest
ARG BUILD_DATE
ARG VCS_REF

# Use build args for dynamic labels
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Conditional builds
ARG BUILD_ENV=production
RUN if [ "$BUILD_ENV" = "development" ]; then \
      apk add --no-cache git vim curl; \
    fi

# Build command:
# docker build \
#   --build-arg VERSION=1.2.3 \
#   --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
#   --build-arg VCS_REF=$(git rev-parse --short HEAD) \
#   -t myapp:1.2.3 .
```

---

## OCI Container Labels

OCI (Open Container Initiative) annotations provide standardized metadata for container images. These labels are essential for **GitHub Container Registry (GHCR)** integration and image discovery.

### Complete OCI Label Reference

| Label | Description | Required | Example |
|-------|-------------|----------|---------|
| `org.opencontainers.image.source` | Repository URL | **Required for GHCR** | `https://github.com/owner/repo` |
| `org.opencontainers.image.description` | Short description (max 512 chars) | **Required for GHCR** | `Production API server` |
| `org.opencontainers.image.licenses` | SPDX license identifier (max 256 chars) | **Required for GHCR** | `MIT`, `Apache-2.0` |
| `org.opencontainers.image.version` | Semantic version | Recommended | `1.2.3` |
| `org.opencontainers.image.revision` | VCS commit hash | Recommended | `abc123def456` |
| `org.opencontainers.image.created` | Build timestamp (RFC 3339) | Recommended | `2025-01-19T12:00:00Z` |
| `org.opencontainers.image.title` | Human-readable name | Optional | `My Application` |
| `org.opencontainers.image.vendor` | Organization/company name | Optional | `Forum Virium Helsinki` |
| `org.opencontainers.image.authors` | Contact details | Optional | `team@example.com` |
| `org.opencontainers.image.url` | Project homepage | Optional | `https://myapp.example.com` |
| `org.opencontainers.image.documentation` | Documentation URL | Optional | `https://docs.example.com` |
| `org.opencontainers.image.ref.name` | Reference name (tag/digest) | Optional | `v1.2.3` |
| `org.opencontainers.image.base.name` | Base image reference | Optional | `docker.io/library/alpine:3.19` |

### GHCR-Specific Labels

GitHub Container Registry uses these labels for special features:

| Label | GHCR Feature |
|-------|--------------|
| `org.opencontainers.image.source` | **Links package to repository** (enables repo permissions inheritance) |
| `org.opencontainers.image.description` | Displayed on package page |
| `org.opencontainers.image.licenses` | Displayed on package page |

**Important**: Without `org.opencontainers.image.source`, your container image won't be linked to your repository, and you'll need to manually manage package permissions.

### Dockerfile Label Patterns

#### Static Labels (for stable metadata)

```dockerfile
# Place early in Dockerfile for caching (rarely changes)
LABEL org.opencontainers.image.source="https://github.com/owner/repo" \
      org.opencontainers.image.description="Production API server for MyApp" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki" \
      org.opencontainers.image.title="MyApp API" \
      org.opencontainers.image.documentation="https://docs.myapp.example.com"
```

#### Dynamic Labels (for build-time metadata)

```dockerfile
# Build arguments for dynamic values
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

# Dynamic labels (place late in Dockerfile)
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"
```

#### Complete Example

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-alpine

# Static labels (GHCR integration)
LABEL org.opencontainers.image.source="https://github.com/owner/myapp" \
      org.opencontainers.image.description="Production Node.js API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki" \
      org.opencontainers.image.title="MyApp API"

# Dynamic labels (build-time metadata)
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

# Create non-root user
RUN addgroup -g 1001 appgroup && adduser -D -u 1001 -G appgroup appuser

WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/dist ./dist
COPY --from=builder --chown=appuser:appuser /app/node_modules ./node_modules

USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s CMD wget -q --spider http://localhost:8080/health || exit 1
CMD ["node", "dist/server.js"]
```

### Build Commands with Labels

```bash
# Build with all labels
docker build \
  --build-arg VERSION=$(git describe --tags --always) \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse HEAD) \
  --label "org.opencontainers.image.source=https://github.com/owner/repo" \
  --label "org.opencontainers.image.description=My container image" \
  --label "org.opencontainers.image.licenses=MIT" \
  -t ghcr.io/owner/myapp:1.2.3 .

# Override labels at build time (useful for CI)
docker build \
  --label "org.opencontainers.image.version=${GITHUB_REF_NAME}" \
  --label "org.opencontainers.image.revision=${GITHUB_SHA}" \
  -t ghcr.io/${{ github.repository }}:${{ github.sha }} .
```

### GitHub Actions Integration

#### Using docker/metadata-action (Recommended)

The `docker/metadata-action` automatically generates OCI-compliant labels:

```yaml
name: Build and Push

on:
  push:
    branches: [main]
    tags: ['v*']

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
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          # Add custom labels to auto-generated ones
          labels: |
            org.opencontainers.image.title=My Application
            org.opencontainers.image.description=Production API server for MyApp
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
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Labels auto-generated by metadata-action:**
- `org.opencontainers.image.source` - From `$GITHUB_SERVER_URL/$GITHUB_REPOSITORY`
- `org.opencontainers.image.revision` - From `$GITHUB_SHA`
- `org.opencontainers.image.created` - Build timestamp
- `org.opencontainers.image.version` - From tag/ref
- `org.opencontainers.image.licenses` - From repository license (if detectable)

#### Manual Labels in GitHub Actions

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
    labels: |
      org.opencontainers.image.source=https://github.com/${{ github.repository }}
      org.opencontainers.image.description=My container image
      org.opencontainers.image.licenses=MIT
      org.opencontainers.image.version=${{ github.ref_name }}
      org.opencontainers.image.revision=${{ github.sha }}
      org.opencontainers.image.created=${{ github.event.head_commit.timestamp }}
```

### Inspecting Labels

```bash
# View labels of local image
docker inspect --format='{{json .Config.Labels}}' myapp:latest | jq

# View labels of remote image (skopeo)
skopeo inspect docker://ghcr.io/owner/myapp:latest | jq '.Labels'

# View labels with crane
crane config ghcr.io/owner/myapp:latest | jq '.config.Labels'
```

### Multi-Architecture Label Considerations

For multi-arch images, labels in the Dockerfile apply to each architecture. The manifest-level annotations require the `--provenance` flag or explicit annotation:

```yaml
- uses: docker/build-push-action@v6
  with:
    context: .
    platforms: linux/amd64,linux/arm64
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    # Enable provenance for manifest annotations
    provenance: true
```

---

## Language-Specific Optimization

For detailed language-specific optimization patterns and step-by-step guides, see the dedicated skills:

- **`go-containers`**: Go static binaries, scratch/distroless, ldflags optimization (846MB → 2.5MB, 99.7% reduction)
- **`nodejs-containers`**: Node.js Alpine patterns, npm/yarn/pnpm, BuildKit cache (900MB → 100MB, 89% reduction)
- **`python-containers`**: Python slim (NOT Alpine), uv/poetry, virtual environments (1GB → 100MB, 90% reduction)

---

## 12-Factor App Principles

### I. Codebase

```dockerfile
# Single codebase tracked in version control
FROM node:20-alpine

# Include git metadata for tracking
ARG VCS_REF
LABEL vcs.ref="${VCS_REF}"

WORKDIR /app
COPY . .
```

### II. Dependencies

```dockerfile
# Explicitly declare dependencies
FROM python:3.11-slim

# Use lock files for reproducible builds
COPY requirements.txt requirements-lock.txt ./
RUN pip install --no-cache-dir -r requirements-lock.txt

# Never rely on system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*
```

### III. Config

```dockerfile
# Store config in environment variables
FROM node:20-alpine

# Never hardcode config
# Bad: ENV DATABASE_URL=postgres://localhost/db
# Good: Pass at runtime via -e or docker-compose

ENV NODE_ENV=production
# Config comes from runtime environment
CMD ["node", "server.js"]
```

```yaml
# docker-compose.yml
services:
  app:
    image: myapp
    environment:
      DATABASE_URL: ${DATABASE_URL}
      API_KEY: ${API_KEY}
    env_file:
      - .env
```

### IV. Backing Services

```dockerfile
# Treat backing services as attached resources
FROM node:20-alpine
WORKDIR /app

# Connect via environment variables
# DATABASE_URL, REDIS_URL, STORAGE_URL, etc.

COPY . .
CMD ["node", "server.js"]
```

```yaml
# docker-compose.yml
services:
  app:
    environment:
      DATABASE_URL: postgresql://postgres:password@db:5432/myapp  # pragma: allowlist secret
      REDIS_URL: redis://redis:6379
      S3_ENDPOINT: http://minio:9000

  db:
    image: postgres:16

  redis:
    image: redis:7-alpine

  minio:
    image: minio/minio
```

### V. Build, Release, Run

```dockerfile
# Strict separation of stages
# Build stage
FROM node:20-alpine AS build
WORKDIR /app
COPY . .
RUN npm ci && npm run build

# Release stage (immutable)
FROM node:20-alpine AS release
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/package*.json ./
RUN npm ci --only=production

# Run stage
FROM node:20-alpine
WORKDIR /app
COPY --from=release /app ./
USER node
CMD ["node", "dist/server.js"]
```

### VI. Processes

```dockerfile
# Execute as stateless processes
FROM python:3.11-slim

# Don't store state in the container
# Use external services for sessions, cache, etc.

WORKDIR /app
COPY . .

# Process should be stateless and share-nothing
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "app:app"]
```

### VII. Port Binding

```dockerfile
# Export services via port binding
FROM node:20-alpine
WORKDIR /app

# Expose port for binding
EXPOSE 3000

# App binds to port at runtime
ENV PORT=3000
CMD ["node", "server.js"]
```

### VIII. Concurrency

```dockerfile
# Scale out via the process model
FROM node:20-alpine
WORKDIR /app

# Single process per container
# Scale horizontally with multiple containers
CMD ["node", "server.js"]
```

```yaml
# docker-compose.yml
services:
  web:
    image: myapp
    deploy:
      replicas: 3  # Scale horizontally
```

### IX. Disposability

```dockerfile
# Fast startup and graceful shutdown
FROM node:20-alpine
WORKDIR /app

# Minimal image for fast startup
COPY --from=builder /app/dist ./dist

# Handle SIGTERM gracefully
STOPSIGNAL SIGTERM
# Give 10 seconds to shut down gracefully
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD node healthcheck.js

CMD ["node", "server.js"]
```

```javascript
// Graceful shutdown handler
process.on('SIGTERM', () => {
  console.log('SIGTERM received, closing server...');
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});
```

### X. Dev/Prod Parity

```dockerfile
# Use same image for dev and prod
FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Development
FROM base AS development
ENV NODE_ENV=development
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]

# Production
FROM base AS production
ENV NODE_ENV=production
COPY . .
RUN npm run build
USER node
CMD ["node", "dist/server.js"]
```

```yaml
# docker-compose.dev.yml
services:
  app:
    build:
      target: development
    volumes:
      - .:/app
      - /app/node_modules

# docker-compose.prod.yml
services:
  app:
    build:
      target: production
```

### XI. Logs

```dockerfile
# Treat logs as event streams
FROM node:20-alpine
WORKDIR /app

# Write to stdout/stderr, not files
# Container runtime handles log aggregation
CMD ["node", "server.js"]
```

```javascript
// Log to stdout/stderr
console.log('INFO: Server started');
console.error('ERROR: Database connection failed');

// Use structured logging
const logger = pino();
logger.info({ userId: 123 }, 'User logged in');
```

### XII. Admin Processes

```dockerfile
# Run admin tasks as one-off processes
FROM python:3.11-slim
WORKDIR /app

# Same image for app and admin tasks
COPY . .

# Default command
CMD ["gunicorn", "app:app"]

# Run admin task:
# docker run myapp python manage.py migrate
# docker run myapp python manage.py shell
```

---

## Security Best Practices

### Minimal Base Images

```dockerfile
# Use minimal base images
FROM alpine:latest          # ~5MB
FROM debian:bookworm-slim  # ~70MB
FROM distroless/static     # ~2MB (no shell)

# Distroless for Go
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app/main /
CMD ["/main"]

# Distroless for Python
FROM gcr.io/distroless/python3-debian12
COPY --from=builder /app /app
WORKDIR /app
CMD ["main.py"]
```

### Non-Root User

```dockerfile
# Always run as non-root user
FROM alpine:latest

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app
COPY --chown=appuser:appuser . .

# Switch to non-root
USER appuser

CMD ["./app"]
```

### Secret Management

```dockerfile
# NEVER include secrets in image
# Bad:
# COPY .env .
# ENV API_KEY=secret123

# Good: Use build secrets (BuildKit)
# docker build --secret id=npmrc,src=$HOME/.npmrc .

FROM node:20-alpine
WORKDIR /app

# Mount secret during build
RUN --mount=type=secret,id=npmrc,dst=/root/.npmrc \
    npm ci

# Or use runtime secrets
CMD ["node", "server.js"]
# Pass at runtime: docker run -e API_KEY=$API_KEY myapp
```

### Image Scanning

```bash
# Scan with Trivy
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp:latest

# Scan with Grype
grype myapp:latest

# Scan with Docker Scout
docker scout cves myapp:latest

# CI/CD Integration
docker build -t myapp:$VERSION .
trivy image --exit-code 1 --severity HIGH,CRITICAL myapp:$VERSION
```

### Vulnerability Management

```dockerfile
# Keep base images updated
FROM node:20-alpine

# Update packages
RUN apk update && apk upgrade

# Remove unnecessary packages
RUN apk add --no-cache ca-certificates && \
    rm -rf /var/cache/apk/*

# Use specific versions
FROM node:20.10.0-alpine3.19
```

### Read-Only Filesystem

```dockerfile
FROM alpine:latest
RUN adduser -D appuser
USER appuser
WORKDIR /app
COPY --chown=appuser:appuser . .

# Create writable temp directory
VOLUME /tmp

CMD ["./app"]
```

```yaml
# docker-compose.yml
services:
  app:
    image: myapp
    read_only: true
    tmpfs:
      - /tmp
      - /var/run
```

### Security Scanning in CI

```yaml
# .github/workflows/security.yml
name: Security Scan
on: [push]

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Run Trivy scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: myapp:${{ github.sha }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload results
        uses: github/codeql-action/upload-sarif@v2
        with:
          sarif_file: 'trivy-results.sarif'
```

---

## Skaffold Workflows

### Basic skaffold.yaml

```yaml
apiVersion: skaffold/v4beta6
kind: Config
metadata:
  name: myapp

build:
  artifacts:
    - image: myapp
      docker:
        dockerfile: Dockerfile
        buildArgs:
          VERSION: "{{.VERSION}}"

deploy:
  kubectl:
    manifests:
      - k8s/*.yaml

portForward:
  - resourceType: service
    resourceName: myapp
    port: 8080
    localPort: 8080
```

### Development Workflow

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta6
kind: Config

build:
  artifacts:
    - image: myapp
      sync:
        manual:
          - src: "src/**/*.js"
            dest: /app/src
      docker:
        dockerfile: Dockerfile.dev

deploy:
  kubectl:
    manifests:
      - k8s/dev/*.yaml

profiles:
  - name: dev
    activation:
      - command: dev
    patches:
      - op: add
        path: /build/artifacts/0/docker/target
        value: development
```

```bash
# Start development mode
skaffold dev

# Debug mode
skaffold debug

# Run once
skaffold run

# Cleanup
skaffold delete
```

### Multi-Service Setup

```yaml
apiVersion: skaffold/v4beta6
kind: Config

build:
  artifacts:
    - image: frontend
      context: ./frontend
      docker:
        dockerfile: Dockerfile

    - image: backend
      context: ./backend
      docker:
        dockerfile: Dockerfile

    - image: worker
      context: ./worker
      docker:
        dockerfile: Dockerfile

deploy:
  kubectl:
    manifests:
      - k8s/frontend/*.yaml
      - k8s/backend/*.yaml
      - k8s/worker/*.yaml
```

### Profiles for Different Environments

```yaml
apiVersion: skaffold/v4beta6
kind: Config

build:
  artifacts:
    - image: myapp

deploy:
  kubectl:
    manifests:
      - k8s/base/*.yaml

profiles:
  - name: dev
    build:
      artifacts:
        - image: myapp
          docker:
            target: development
    deploy:
      kubectl:
        manifests:
          - k8s/base/*.yaml
          - k8s/dev/*.yaml

  - name: staging
    build:
      googleCloudBuild: {}
    deploy:
      kubectl:
        manifests:
          - k8s/base/*.yaml
          - k8s/staging/*.yaml

  - name: prod
    build:
      googleCloudBuild: {}
    deploy:
      kubectl:
        manifests:
          - k8s/base/*.yaml
          - k8s/prod/*.yaml
```

```bash
# Use specific profile
skaffold dev -p dev
skaffold run -p staging
skaffold run -p prod
```

---

## Docker Compose Patterns

### Multi-Service Application

```yaml
version: '3.9'

services:
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - API_URL=http://backend:8000
    depends_on:
      - backend
    networks:
      - app-network

  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://postgres:password@db:5432/myapp  # pragma: allowlist secret
      - REDIS_URL=redis://redis:6379
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - app-network
    volumes:
      - ./backend:/app

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    volumes:
      - postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    networks:
      - app-network

volumes:
  postgres-data:
  redis-data:

networks:
  app-network:
    driver: bridge
```

### Development vs Production

```yaml
# docker-compose.yml (base)
version: '3.9'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      NODE_ENV: ${NODE_ENV:-production}

# docker-compose.dev.yml (development overrides)
version: '3.9'

services:
  app:
    build:
      target: development
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      NODE_ENV: development
      DEBUG: "app:*"
    command: npm run dev

# docker-compose.prod.yml (production overrides)
version: '3.9'

services:
  app:
    build:
      target: production
    restart: always
    environment:
      NODE_ENV: production
```

```bash
# Development
docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Health Checks

```yaml
services:
  web:
    image: nginx:alpine
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  api:
    image: myapi
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Resource Limits

```yaml
services:
  app:
    image: myapp
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
```

---

## Performance Optimization

### Layer Caching Strategy

```dockerfile
# Optimize layer order for caching
FROM node:20-alpine

WORKDIR /app

# 1. Copy and install system dependencies (rarely changes)
RUN apk add --no-cache python3 make g++

# 2. Copy dependency manifests (changes occasionally)
COPY package*.json ./

# 3. Install dependencies (cached unless manifests change)
RUN npm ci --only=production

# 4. Copy source code (changes frequently)
COPY . .

# 5. Build (only runs if source changes)
RUN npm run build

CMD ["node", "dist/server.js"]
```

### .dockerignore Best Practices

A comprehensive `.dockerignore` file reduces build context size, speeds up builds, and prevents sensitive files from entering images.

#### Universal Exclusions

```
# Version control
.git
.gitignore
.gitattributes
.hg

# IDE and editors
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store
.project
.settings/
*.sublime-project
*.sublime-workspace

# Documentation (unless needed in image)
README.md
*.md
docs/
LICENSE
CONTRIBUTING.md

# CI/CD
.github/
.gitlab-ci.yml
.travis.yml
.circleci/
Jenkinsfile
azure-pipelines.yml

# Environment and secrets
.env
.env.*
*.env
secrets/
credentials/
*.key
*.pem
*.crt

# Docker files
Dockerfile*
docker-compose*.yml
.dockerignore

# Build artifacts
dist/
build/
out/
bin/
target/
tmp/
temp/

# Logs
*.log
logs/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Test coverage
coverage/
.nyc_output/
*.cover
htmlcov/
```

#### Node.js Specific

```
# Dependencies
node_modules/
npm-debug.log
yarn-error.log
package-lock.json  # Only if using yarn
yarn.lock          # Only if using npm

# Testing
coverage/
.nyc_output/
*.test.js
*.spec.js
__tests__/
test/
tests/

# Build
dist/
build/
.cache/
.parcel-cache/
.next/
.nuxt/
.output/
```

#### Python Specific

```
# Byte-compiled / optimized / DLL files
__pycache__/
*.py[cod]
*$py.class
*.so

# Distribution / packaging
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# Virtual environments
venv/
env/
ENV/
.venv/

# Testing
.pytest_cache/
.tox/
.coverage
htmlcov/
*.cover

# Type checking
.mypy_cache/
.pytype/
.pyre/
```

#### Go Specific

```
# Binaries
*.exe
*.exe~
*.dll
*.so
*.dylib
*.test
*.out

# Go workspace
go.work
go.work.sum

# Vendor (if using modules)
vendor/

# Testing
*_test.go
testdata/
coverage.out
```

#### Impact on Build Performance

| Build Context | Without .dockerignore | With .dockerignore | Improvement |
|---------------|----------------------|-------------------|-------------|
| **Node.js project** | 450MB (node_modules) | 12MB | 97% reduction |
| **Python project** | 180MB (venv, pycache) | 8MB | 96% reduction |
| **Go project** | 95MB (vendor, .git) | 2MB | 98% reduction |

**Build time improvements:**
- Initial build: 15-30% faster
- Subsequent builds: 40-60% faster (better cache hits)

### BuildKit Optimizations

```dockerfile
# syntax=docker/dockerfile:1

FROM node:20-alpine

# Enable BuildKit cache mounts
RUN --mount=type=cache,target=/root/.npm \
    npm install -g npm@latest

WORKDIR /app

# Cache npm modules
RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    --mount=type=cache,target=/root/.npm \
    npm ci --only=production

COPY . .
CMD ["node", "server.js"]
```

```bash
# Build with BuildKit
DOCKER_BUILDKIT=1 docker build -t myapp .

# Or set as default
export DOCKER_BUILDKIT=1
```

### Image Size Reduction

```dockerfile
# Use multi-stage to remove build dependencies
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Minimal runtime image
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package.json ./
USER node
CMD ["node", "dist/server.js"]
```

```bash
# Compare image sizes
docker images

# Analyze image layers
docker history myapp:latest

# Use dive to explore image
dive myapp:latest
```

---

## Advanced Dockerfile Patterns

### Health Checks

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY . .

# Built-in health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js || exit 1

CMD ["node", "server.js"]
```

```javascript
// healthcheck.js
const http = require('http');

const options = {
  host: 'localhost',
  port: 3000,
  path: '/health',
  timeout: 2000
};

const req = http.request(options, (res) => {
  process.exit(res.statusCode === 200 ? 0 : 1);
});

req.on('error', () => process.exit(1));
req.end();
```

### Signal Handling

```dockerfile
FROM node:20-alpine
WORKDIR /app

# Use tini as init system
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]

COPY . .
CMD ["node", "server.js"]
```

### Logging Configuration

```dockerfile
FROM python:3.11-slim
WORKDIR /app

# Log to stdout/stderr
ENV PYTHONUNBUFFERED=1

# Configure logging
COPY logging.conf /etc/logging.conf
ENV LOG_CONFIG=/etc/logging.conf

COPY . .
CMD ["python", "app.py"]
```

### Development Tools Integration

```dockerfile
# Multi-target for dev tools
FROM node:20-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM base AS development
RUN npm install
# Development tools
RUN npm install -g nodemon
COPY . .
CMD ["nodemon", "server.js"]

FROM base AS production
COPY . .
USER node
CMD ["node", "server.js"]
```

---

## Additional Resources

- **Docker Documentation**: https://docs.docker.com/
- **Dockerfile Best Practices**: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
- **12-Factor App**: https://12factor.net/
- **Skaffold Documentation**: https://skaffold.dev/docs/
- **Docker Compose Documentation**: https://docs.docker.com/compose/
- **Container Security**: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
