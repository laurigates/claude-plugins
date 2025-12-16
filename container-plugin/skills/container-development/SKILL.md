---
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

## Version Checking

**CRITICAL**: Before using base images, verify latest versions:
- **Node.js Alpine**: Check [Docker Hub node](https://hub.docker.com/_/node) for latest LTS
- **Python slim**: Check [Docker Hub python](https://hub.docker.com/_/python) for latest
- **nginx Alpine**: Check [Docker Hub nginx](https://hub.docker.com/_/nginx)

Use WebSearch or WebFetch to verify current versions.

**Multi-Stage Dockerfile Pattern (Node.js - Non-Root Alpine)**
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

**Security Best Practices (Mandatory)**
- **Non-root user**: REQUIRED - never run as root in production
- **Minimal base images**: Alpine for Node/Go/Rust, slim for Python
- **Multi-stage builds**: REQUIRED - keep build tools out of runtime
- **HEALTHCHECK**: REQUIRED for Kubernetes probes
- **Vulnerability scanning**: Use Trivy or Grype in CI
- **Version pinning**: Always use specific tags, never `latest`

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

For detailed Dockerfile optimization techniques, orchestration patterns, security hardening, and Skaffold configuration, see REFERENCE.md.

## Related Commands

- `/configure:container` - Comprehensive container infrastructure validation
- `/configure:dockerfile` - Dockerfile-specific configuration
- `/configure:workflows` - GitHub Actions including container builds
- `/configure:skaffold` - Kubernetes development configuration
