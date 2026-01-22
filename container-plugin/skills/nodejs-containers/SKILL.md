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

## The Optimization Journey: 900MB → 50-100MB

### Step 1: The Problem - Full Node Base (900MB)

```dockerfile
# ❌ BAD: Includes full Debian, all dependencies, build tools
FROM node:20
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3000
CMD ["node", "server.js"]
```

**Issues**:
- Full Debian base (~120MB)
- All npm dependencies including devDependencies
- Build tools and compilers for native modules
- Source files and tests in production image

**Image size: ~900MB**

### Step 2: Alpine Base (350MB)

```dockerfile
# ✅ BETTER: Alpine reduces OS overhead
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3000
CMD ["node", "server.js"]
```

**Improvements**:
- Alpine Linux (~5MB vs ~120MB Debian)
- Still includes all dependencies (dev + prod)
- Still includes source files

**Image size: ~350MB** (61% reduction)

### Step 3: Production Dependencies Only (200MB)

```dockerfile
# ✅ GOOD: Only production dependencies
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
USER node
CMD ["node", "server.js"]
```

**Improvements**:
- Only production dependencies
- Running as non-root user
- Better layer caching (package.json separate)

**Image size: ~200MB** (43% reduction from 350MB)

### Step 4: Multi-Stage Build for Static Sites (50-70MB)

```dockerfile
# Build stage - includes devDependencies for building
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage - minimal nginx Alpine
FROM nginx:1.27-alpine

# Create non-root user
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

# Copy built assets
COPY --from=build /app/dist /usr/share/nginx/html

# Make nginx dirs writable
RUN chown -R appuser:appgroup /var/cache/nginx /var/run /var/log/nginx

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

**Image size: ~50-70MB** (80% reduction from 200MB)

### Step 5: Multi-Stage for Node Servers (100-150MB)

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

**Image size: ~100-150MB** (depending on dependencies)

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
# Use npm ci for reproducible builds
COPY package*.json ./
RUN npm ci --only=production

# Clean npm cache
RUN npm cache clean --force
```

### yarn

```dockerfile
# Use yarn install --frozen-lockfile
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production

# Clean yarn cache
RUN yarn cache clean
```

### pnpm

```dockerfile
# Enable pnpm
RUN npm install -g pnpm

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

# pnpm creates smaller node_modules with hard links
# Image size: 20-30% smaller than npm
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

## Node.js-Specific .dockerignore

```
# Dependencies
node_modules/
npm-debug.log
yarn-debug.log
yarn-error.log
.pnpm-store/

# Lock files (keep the one you use)
package-lock.json  # If using yarn
yarn.lock          # If using npm
pnpm-lock.yaml     # If not using pnpm

# Testing
coverage/
.nyc_output/
*.test.js
*.test.ts
*.spec.js
*.spec.ts
__tests__/
__mocks__/
test/
tests/

# Build output
dist/
build/
.next/
.nuxt/
.cache/
.parcel-cache/
out/

# Development
.env
.env.*
.vscode/
.idea/
*.swp
.DS_Store

# Source maps (if not needed in production)
*.map

# Documentation
README.md
*.md
docs/

# CI/CD
.github/
.gitlab-ci.yml
Jenkinsfile

# Version control
.git
.gitignore

# Docker
Dockerfile*
docker-compose*.yml
.dockerignore
```

## Distroless for Node.js

```dockerfile
# Build stage
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --production

# Runtime with distroless
FROM gcr.io/distroless/nodejs20-debian12

WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./

# Distroless runs as non-root by default
EXPOSE 3000
CMD ["dist/server.js"]
```

**Distroless advantages**:
- No shell, package manager (security)
- Minimal CVEs (2-4 vs 45-60)
- ~120MB final image
- Harder to debug (no shell access)

## Framework-Specific Patterns

### Next.js

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:20-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production

COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

### Express.js

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./

USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### NestJS

```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

## Monorepo Patterns (Turborepo, Nx)

```dockerfile
FROM node:20-alpine AS base
RUN npm install -g turbo pnpm

FROM base AS pruner
WORKDIR /app
COPY . .
RUN turbo prune --scope=@myapp/api --docker

FROM base AS installer
WORKDIR /app
COPY --from=pruner /app/out/json/ .
RUN pnpm install --frozen-lockfile

COPY --from=pruner /app/out/full/ .
RUN pnpm turbo run build --filter=@myapp/api

FROM base AS runner
WORKDIR /app
COPY --from=installer /app/apps/api/dist ./dist
COPY --from=installer /app/node_modules ./node_modules

USER node
EXPOSE 3000
CMD ["node", "dist/main.js"]
```

## Agentic Optimizations

Node.js-specific container commands:

| Context | Command | Purpose |
|---------|---------|---------|
| **Fast rebuild** | `DOCKER_BUILDKIT=1 docker build --target build .` | Build only build stage |
| **Size check** | `docker images app --format "table {{.Repository}}\t{{.Size}}"` | Compare sizes |
| **Layer analysis** | `docker history app:latest --human --no-trunc \| head -20` | Find large layers |
| **Dependency audit** | `docker run --rm app npm audit --production` | Check vulnerabilities |
| **Cache clear** | `docker builder prune --filter type=exec.cachemount` | Clear BuildKit cache |
| **Test locally** | `docker run --rm -p 3000:3000 app` | Quick local test |

## Best Practices

**Always**:
- Use Alpine variants for smaller images
- Use `npm ci` not `npm install` (reproducible builds)
- Separate dev and production dependencies
- Run as non-root user
- Use multi-stage builds for production
- Layer package.json separately from source code
- Add .dockerignore to exclude node_modules, tests

**Never**:
- Copy node_modules from host
- Use `npm install` in production
- Run as root user
- Include devDependencies in production
- Use `node:latest` (always pin versions)
- Include source TypeScript files in production image

## Common Issues

### Native Modules (node-gyp)

```dockerfile
# If you have native modules
FROM node:20-alpine AS build

# Install build dependencies
RUN apk add --no-cache python3 make g++

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Runtime stage
FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER node
CMD ["node", "dist/server.js"]
```

### Canvas, Sharp, and Image Processing

```dockerfile
# For image processing libraries
FROM node:20-alpine AS build

# Install image libraries
RUN apk add --no-cache \
    build-base \
    cairo-dev \
    jpeg-dev \
    pango-dev \
    giflib-dev \
    pixman-dev

WORKDIR /app
COPY package*.json ./
RUN npm ci --build-from-source
COPY . .
RUN npm run build

FROM node:20-alpine
RUN apk add --no-cache cairo jpeg pango giflib pixman
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER node
CMD ["node", "dist/server.js"]
```

## Related Skills

- `container-development` - General container patterns, multi-stage builds, security
- `go-containers` - Go-specific container optimizations
- `python-containers` - Python-specific container optimizations
