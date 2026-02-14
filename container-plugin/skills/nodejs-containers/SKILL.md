---
model: haiku
created: 2026-01-15
modified: 2026-01-15
reviewed: 2026-01-15
name: nodejs-containers
description: |
  Node.js-specific container optimization patterns including Alpine variants,
  multi-stage builds, node_modules caching, production dependency separation,
  and optimization from ~900MB to ~50-100MB. Covers npm/yarn/pnpm patterns,
  BuildKit cache mounts, and non-root user configuration.
  Use when working with Node.js containers, Dockerfiles for Node apps, or optimizing Node image sizes.
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, TodoWrite, WebSearch, WebFetch
---

# Node.js Container Optimization

Expert knowledge for building optimized Node.js container images using Alpine variants, multi-stage builds, and Node.js-specific dependency management patterns.

## When to Use This Skill

| Use this skill when... | Use `container-development` instead when... |
|------------------------|---------------------------------------------|
| Building Node.js-specific Dockerfiles | General multi-stage build patterns |
| Optimizing Node.js image sizes | Language-agnostic container security |
| Handling npm/yarn/pnpm in containers | Docker Compose configuration |
| Dealing with native module builds | Non-Node.js container optimization |

## Core Expertise

**Node.js Container Challenges**:
- Large node_modules directories (100-500MB)
- Full base images include build tools (~900MB)
- Separate dev and production dependencies
- Different package managers (npm, yarn, pnpm)
- Native modules requiring build tools

**Key Capabilities**:
- Alpine-based images (~100MB vs ~900MB full)
- Multi-stage builds separating build and runtime
- BuildKit cache mounts for node_modules
- Production-only dependency installation
- Non-root user configuration

## Optimized Multi-Stage Pattern (Node Servers)

The recommended pattern achieves ~100-150MB images:

```dockerfile
# Dependencies stage - production only
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Build stage - includes devDependencies
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage - minimal
FROM node:20-alpine
WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -u 1001 -S nodejs -G nodejs

# Copy dependencies and built app
COPY --from=deps --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=nodejs:nodejs /app/dist ./dist
COPY --chown=nodejs:nodejs package.json ./

USER nodejs
EXPOSE 3000

HEALTHCHECK --interval=30s CMD node healthcheck.js || exit 1

CMD ["node", "dist/server.js"]
```

## BuildKit Cache Mounts (Fastest Builds)

```dockerfile
# syntax=docker/dockerfile:1

FROM node:20-alpine AS build
WORKDIR /app

# Cache mount for npm cache
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    npm ci

COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
USER node
CMD ["node", "dist/server.js"]
```

**Build performance**:
- First build: ~2-3 minutes
- Subsequent builds (no package changes): ~10-20 seconds
- Subsequent builds (package changes): ~30-60 seconds

## Package Manager Patterns

### npm

```dockerfile
COPY package*.json ./
RUN npm ci --only=production
RUN npm cache clean --force
```

### yarn

```dockerfile
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production
RUN yarn cache clean
```

### pnpm

```dockerfile
RUN npm install -g pnpm
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod
# pnpm creates smaller node_modules with hard links (20-30% smaller)
```

## Performance Impact

| Metric | Full Node (900MB) | Alpine (350MB) | Multi-Stage (100MB) | Improvement |
|--------|-------------------|----------------|---------------------|-------------|
| **Image Size** | 900MB | 350MB | 100MB | 89% reduction |
| **Pull Time** | 3m 20s | 1m 10s | 25s | 87% faster |
| **Build Time** | 4m 30s | 3m 15s | 2m 30s | 44% faster |
| **Rebuild (cached)** | 2m 10s | 1m 30s | 15s | 88% faster |
| **Memory Usage** | 512MB | 256MB | 180MB | 65% reduction |

## Security Impact

| Image Type | Vulnerabilities | Size | Risk |
|------------|-----------------|------|------|
| **node:20 (Debian)** | 45-60 CVEs | 900MB | High |
| **node:20-alpine** | 8-12 CVEs | 350MB | Medium |
| **Multi-stage Alpine** | 4-8 CVEs | 100MB | Low |
| **Distroless Node** | 2-4 CVEs | 120MB | Very Low |

## Agentic Optimizations

| Context | Command | Purpose |
|---------|---------|---------|
| **Fast rebuild** | `DOCKER_BUILDKIT=1 docker build --target build .` | Build only build stage |
| **Size check** | `docker images app --format "table {{.Repository}}\t{{.Size}}"` | Compare sizes |
| **Layer analysis** | `docker history app:latest --human --no-trunc \| head -20` | Find large layers |
| **Dependency audit** | `docker run --rm app npm audit --production` | Check vulnerabilities |
| **Cache clear** | `docker builder prune --filter type=exec.cachemount` | Clear BuildKit cache |
| **Test locally** | `docker run --rm -p 3000:3000 app` | Quick local test |

## Best Practices

- Use Alpine variants for smaller images
- Use `npm ci` not `npm install` (reproducible builds)
- Separate dev and production dependencies
- Run as non-root user
- Use multi-stage builds for production
- Layer package.json separately from source code
- Add .dockerignore to exclude node_modules, tests

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Related Skills

- `container-development` - General container patterns, multi-stage builds, security
- `go-containers` - Go-specific container optimizations
- `python-containers` - Python-specific container optimizations
