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

### Basic Multi-Stage Build

```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# Final stage
FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .
CMD ["./main"]
```

### Node.js Multi-Stage Build

```dockerfile
# Dependencies stage
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./
USER node
CMD ["node", "dist/index.js"]
```

### Python Multi-Stage Build

```dockerfile
# Builder stage
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .
RUN uv build

# Runtime stage
FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/dist/*.whl /tmp/
RUN pip install --no-cache-dir /tmp/*.whl && rm -rf /tmp/*.whl
ENV PATH="/app/.venv/bin:$PATH"
USER nobody
CMD ["python", "-m", "myapp"]
```

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

# Use build args
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

### .dockerignore

```
# .dockerignore
node_modules
npm-debug.log
.git
.gitignore
.env
.env.*
*.md
.vscode
.idea
dist
build
coverage
.DS_Store
Dockerfile
docker-compose*.yml
```

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
