# Node.js Container Optimization - Reference

Detailed reference material for Node.js container optimization patterns.

## The Optimization Journey: 900MB to 50-100MB

### Step 1: The Problem - Full Node Base (900MB)

```dockerfile
# Includes full Debian, all dependencies, build tools
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
