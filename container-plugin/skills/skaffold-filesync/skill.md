---
model: haiku
name: skaffold-filesync
description: |
  Fast iterative development with Skaffold file sync - copy changed files to running containers
  without rebuilding images. Use when optimizing the development loop, configuring sync rules,
  or when the user mentions file sync, hot reload, live reload, or fast iteration.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-21
modified: 2026-01-21
reviewed: 2026-01-21
---

# Skaffold File Sync

## Overview

File sync copies changed files directly to running containers, avoiding image rebuilds. This dramatically speeds up the development loop for interpreted languages and static assets.

```
Without sync: Edit → Build Image → Deploy → Restart Pod → Test (~30-60s)
With sync:    Edit → Copy File → Test (~1-2s)
```

## How It Works

1. Skaffold watches for file changes
2. Creates a tar archive of modified files matching sync rules
3. Extracts the archive in the running container
4. Application picks up changes (hot reload, file watch, etc.)

## Three Sync Modes

| Mode | Configuration | Best For |
|------|---------------|----------|
| **Manual** | Explicit src/dest mappings | Full control, complex layouts |
| **Infer** | Derived from Dockerfile | Docker builds, simple projects |
| **Auto** | Zero-config for known builders | Buildpacks, Jib |

**Important**: Cannot mix modes - choose one per artifact.

## Manual Sync

Explicitly map source files to container destinations.

### Basic Configuration

```yaml
apiVersion: skaffold/v4beta13
kind: Config
build:
  artifacts:
    - image: my-app
      context: .
      docker:
        dockerfile: Dockerfile
      sync:
        manual:
          - src: "src/**/*.js"
            dest: /app/src
          - src: "public/**/*"
            dest: /app/public
```

### With Directory Stripping

Use `strip` to remove directory levels from the source path:

```yaml
sync:
  manual:
    # src/components/Button.js → /app/Button.js (strips 'src/components/')
    - src: "src/components/**/*.js"
      dest: /app
      strip: "src/components/"

    # assets/images/logo.png → /var/www/static/logo.png
    - src: "assets/images/**/*"
      dest: /var/www/static
      strip: "assets/images/"
```

### Static Assets Example

```yaml
sync:
  manual:
    # HTML files to nginx root
    - src: "static/*.html"
      dest: /usr/share/nginx/html

    # CSS with directory structure preserved
    - src: "static/css/**/*.css"
      dest: /usr/share/nginx/html/css
      strip: "static/css/"

    # Images
    - src: "static/images/**/*"
      dest: /usr/share/nginx/html/images
      strip: "static/images/"
```

### Node.js Hot Reload Example

```yaml
build:
  artifacts:
    - image: node-app
      sync:
        manual:
          - src: "src/**/*.ts"
            dest: /app/src
          - src: "src/**/*.tsx"
            dest: /app/src
          - src: "*.json"
            dest: /app
```

Pair with nodemon or ts-node-dev in container:

```dockerfile
CMD ["npx", "nodemon", "--watch", "/app/src", "src/index.ts"]
```

### Python Hot Reload Example

```yaml
build:
  artifacts:
    - image: python-app
      sync:
        manual:
          - src: "app/**/*.py"
            dest: /app
          - src: "templates/**/*.html"
            dest: /app/templates
            strip: "templates/"
```

Pair with Flask debug mode or uvicorn reload:

```dockerfile
CMD ["uvicorn", "main:app", "--reload", "--host", "0.0.0.0"]
```

## Inferred Sync

Skaffold automatically determines destinations from Dockerfile `COPY`/`ADD` instructions.

### Configuration

```yaml
build:
  artifacts:
    - image: my-app
      docker:
        dockerfile: Dockerfile
      sync:
        infer:
          - "**/*.js"
          - "**/*.css"
          - "**/*.html"
```

### How Inference Works

Given this Dockerfile:

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY src/ ./src/        # Skaffold infers: src/* → /app/src/*
COPY public/ ./public/  # Skaffold infers: public/* → /app/public/*
```

Skaffold analyzes COPY instructions to determine sync destinations.

### Limitations

| Limitation | Workaround |
|------------|------------|
| File deletion triggers full rebuild | Use manual sync for delete support |
| Multi-stage builds may confuse inference | Use manual sync |
| Complex COPY patterns | Use manual sync |

## Auto Sync

Zero-configuration sync for supported builders.

### Buildpacks (Cloud Native Buildpacks)

```yaml
build:
  artifacts:
    - image: my-app
      buildpacks:
        builder: gcr.io/buildpacks/builder:v1
      sync:
        auto: true  # Enabled by default for buildpacks
```

Supported languages:
- **Go**: `.go` files
- **Java**: `.java`, `.kt`, `.properties`, `.xml` files
- **Node.js**: `.js`, `.ts`, `.json` files

Disable auto sync:

```yaml
sync:
  auto: false
```

### Jib (Java)

```yaml
build:
  artifacts:
    - image: my-app
      jib: {}
      sync:
        auto: true  # Enabled by default for Jib
```

Auto-syncs:
- Class files (compiled)
- Resource files
- Extra directory files

## Full Configuration Examples

### Node.js Development Stack

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: node-app

build:
  local:
    push: false
    useBuildkit: true
  artifacts:
    - image: node-app
      context: .
      docker:
        dockerfile: Dockerfile
      sync:
        manual:
          - src: "src/**/*.ts"
            dest: /app/src
          - src: "src/**/*.tsx"
            dest: /app/src
          - src: "public/**/*"
            dest: /app/public

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

### Python FastAPI Stack

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: fastapi-app

build:
  local:
    push: false
  artifacts:
    - image: fastapi-app
      sync:
        manual:
          - src: "app/**/*.py"
            dest: /code/app
          - src: "templates/**/*.html"
            dest: /code/templates
            strip: "templates/"
          - src: "static/**/*"
            dest: /code/static
            strip: "static/"

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

### Go with Air (Hot Reload)

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: go-app

build:
  artifacts:
    - image: go-app
      sync:
        manual:
          - src: "**/*.go"
            dest: /app
          - src: "go.mod"
            dest: /app
          - src: "go.sum"
            dest: /app

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

With Air in Dockerfile:

```dockerfile
FROM golang:1.22-alpine
RUN go install github.com/cosmtrek/air@latest
WORKDIR /app
COPY . .
CMD ["air", "-c", ".air.toml"]
```

### Static Site with Nginx

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: static-site

build:
  artifacts:
    - image: static-site
      sync:
        manual:
          - src: "dist/**/*"
            dest: /usr/share/nginx/html
            strip: "dist/"

deploy:
  kubeContext: orbstack
  kubectl:
    manifests:
      - k8s/*.yaml
```

## Requirements and Limitations

### Container Requirements

| Requirement | Reason |
|-------------|--------|
| `tar` command available | Used to extract synced files |
| Writable target directories | Cannot sync to read-only paths |
| Container user has write permissions | Files must be modifiable by container UID |

### What Cannot Be Synced

| Scenario | Solution |
|----------|----------|
| Builder-generated files | Full rebuild required |
| Files requiring compilation | Use hot-reload tools (nodemon, air) |
| System files / package installs | Full rebuild required |
| Permission changes | Full rebuild required |

### Sync vs Rebuild Decision

| Change Type | Sync | Rebuild |
|-------------|------|---------|
| Source code (interpreted) | Yes | - |
| Static assets | Yes | - |
| Config files | Yes | - |
| Dockerfile | - | Yes |
| Dependencies (package.json, go.mod) | - | Yes |
| Build scripts | - | Yes |

## Debugging Sync Issues

### Verify Sync Is Working

```bash
# Watch Skaffold output for sync messages
skaffold dev -v info

# Look for:
# Syncing 1 files for my-app:latest
# Watching for changes...
```

### Check Container Has tar

```bash
kubectl exec -it <pod> -- which tar
# Should output: /bin/tar or /usr/bin/tar
```

### Verify File Permissions

```bash
kubectl exec -it <pod> -- ls -la /app/src/
# Check files are writable by container user
```

### Test Manual Sync Path

```bash
# Verify destination exists in container
kubectl exec -it <pod> -- ls -la /app/

# Check container user
kubectl exec -it <pod> -- whoami
```

## Profiles for Sync vs Rebuild

```yaml
profiles:
  # Fast iteration - sync enabled
  - name: dev
    build:
      artifacts:
        - image: my-app
          sync:
            manual:
              - src: "src/**/*"
                dest: /app/src

  # CI/Production - no sync, full rebuilds
  - name: ci
    build:
      artifacts:
        - image: my-app
          # No sync configuration
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Dev with sync | `skaffold dev --kube-context=orbstack` |
| Verbose sync debug | `skaffold dev -v info` |
| Force rebuild (skip sync) | `skaffold dev --force=true` |
| Single rebuild | `skaffold build && skaffold deploy` |
| Check sync status | `skaffold dev -v debug 2>&1 \| grep -i sync` |

## Quick Reference

### Sync Configuration Fields

| Field | Description | Required |
|-------|-------------|----------|
| `src` | Glob pattern for source files | Yes |
| `dest` | Destination path in container | Yes |
| `strip` | Directory prefix to remove | No |

### Sync Modes Comparison

| Feature | Manual | Infer | Auto |
|---------|--------|-------|------|
| Explicit mapping | Yes | No | No |
| Delete support | Yes | No | Yes |
| Multi-stage Docker | Yes | Limited | N/A |
| Zero-config | No | Partial | Yes |
| Buildpacks support | No | No | Yes |
| Jib support | No | No | Yes |

### Glob Patterns

| Pattern | Matches |
|---------|---------|
| `*.js` | JS files in root only |
| `**/*.js` | JS files in all directories |
| `src/**/*` | All files under src/ |
| `{src,lib}/**/*.ts` | TS files in src/ or lib/ |
