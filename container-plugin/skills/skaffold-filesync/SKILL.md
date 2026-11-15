---
name: skaffold-filesync
description: "Skaffold file sync — copy changed files to containers without rebuilding. Use when optimizing the dev loop, configuring sync rules, or the user mentions hot reload or fast iteration."
user-invocable: false
allowed-tools: Bash(skaffold dev *), Bash(skaffold build *), Bash(grep *), Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-21
modified: 2026-11-14
reviewed: 2026-04-25
---

# Skaffold File Sync

## When to Use This Skill

| Use this skill when... | Use a sibling Skaffold/container skill instead when... |
|---|---|
| Configuring Skaffold `sync` rules (manual / infer / auto) | Wiring OrbStack networking or Ingress (`skaffold-orbstack`) |
| Optimizing the inner edit -> running-container loop for hot reload | Adding pre-deploy `test` or post-deploy `verify` stages (`skaffold-testing`) |
| Debugging why files are not syncing into a running pod | Writing or hardening the Dockerfile itself (`container-development`) |

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

Static-asset, Node.js hot-reload (nodemon) and Python hot-reload (uvicorn `--reload`) manual-sync examples: [REFERENCE.md](REFERENCE.md#manual-sync-examples).

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

Complete `skaffold.yaml` files for Node.js, Python FastAPI, Go with Air, and a static site with Nginx: [REFERENCE.md](REFERENCE.md#full-configuration-examples).

## Host-Side Generated Assets

When a build step produces a file the app serves (compiled CSS, bundled JS), run that step's watcher **on the host** and let an ordinary sync rule ship its output. No rebuild and no sidecar.

```bash
# justfile recipe body (e.g. `just k8s-up`)
tailwindcss -i src/app/static/input.css -o src/app/static/app.css --watch=always --silent &
trap 'kill $! 2>/dev/null' EXIT
skaffold dev --port-forward
```

```yaml
sync:
  manual:
    - src: "src/**/static/**"   # matches the watcher's OUTPUT (app.css), not its input
      dest: /app
```

Verified (OrbStack, skaffold v2.25.0): a template class change → the host watcher rewrites `app.css` → Skaffold logs `Syncing 2 files` → the class is in the pod and in the served CSS. Ctrl-C stops both processes.

| Rule | Why |
|------|-----|
| The sync rule must match the watcher's **output** path | Skaffold syncs files that changed on disk; a rule covering only the input never ships the generated asset |
| Keep a backgrounded watcher alive when stdin closes | Tailwind v4 `--watch` exits when stdin closes, so CSS silently stops updating; use `--watch=always`. For Vite/esbuild, use their watch mode and confirm it survives backgrounding |
| `trap … EXIT` before `skaffold dev` | Kills the watcher when the recipe exits, so no orphan keeps writing |
| CI freshness checks use a one-shot build | Tailwind watch mode only **adds** classes; removed ones linger until a one-shot `tailwindcss -i … -o …`. Compare against that, never against watcher output |

| Choose | When |
|--------|------|
| Host watcher + sync | Output lands in a path a sync rule already covers, or is **committed** to git |
| Sidecar watcher in the pod | Output is neither committed nor needed on the host — a sidecar writes inside the pod, so a committed copy goes stale |
| Full rebuild | The asset is produced only by the image build (multi-stage `RUN npm run build`) |

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
| Builder-generated files (made inside the image build) | Full rebuild required — unless generated on the host into a synced path ([Host-Side Generated Assets](#host-side-generated-assets)) |
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

Run `skaffold dev -v info` and look for `Syncing N files`; if nothing syncs, check that the container has `tar`, that the files are writable by the container user, and that the destination path exists: [REFERENCE.md](REFERENCE.md#debugging-sync-issues).

## Profiles for Sync vs Rebuild

Keep sync in a `dev` profile and leave it out of a `ci` profile so CI and production always do full rebuilds: [REFERENCE.md](REFERENCE.md#profiles-for-sync-vs-rebuild).

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
