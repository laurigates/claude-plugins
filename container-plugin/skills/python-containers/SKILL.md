---
created: 2026-01-15
modified: 2026-09-02
reviewed: 2026-01-15
name: python-containers
description: "Python container optimization — slim images (not Alpine), virtualenv, multi-stage, pip/poetry/uv, musl gotchas (1GB to ~120MB). Use when working with Python containers or optimizing image sizes."
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob, Edit, Write, TodoWrite, WebSearch, WebFetch
---

# Python Container Optimization

Expert knowledge for building optimized Python container images using slim base images, virtual environments, modern package managers (uv, poetry), and multi-stage build patterns.

## When to Use This Skill

| Use this skill when... | Use `container-development` instead when... |
|------------------------|---------------------------------------------|
| Building Python-specific Dockerfiles | General multi-stage build patterns |
| Optimizing Python image sizes | Language-agnostic container security |
| Handling pip/poetry/uv in containers | Docker Compose configuration |
| Dealing with musl/glibc issues | Non-Python container optimization |

## Core Expertise

**Python Container Challenges**:
- Large base images with unnecessary packages (~1GB)
- **Critical**: Alpine causes issues with Python (musl vs glibc)
- Complex dependency management (pip, poetry, pipenv, uv)
- Compiled C extensions requiring build tools
- Virtual environment handling in containers

**Key Capabilities**:
- Slim-based images (NOT Alpine for Python)
- Multi-stage builds with modern tools (uv recommended)
- Virtual environment optimization
- Compiled extension handling
- Non-root user configuration

## Why NOT Alpine for Python

Use `slim` instead of Alpine for Python containers. Alpine uses musl libc which causes:
- Many wheels don't work (numpy, pandas, scipy)
- Forces compilation from source (slow builds)
- Larger final images due to build tools
- Runtime errors with native extensions

## Optimized Dockerfile Pattern (uv)

The recommended pattern achieves ~80-120MB images:

```dockerfile
# Both stages MUST share this interpreter version — see below.
ARG PYTHON_VERSION=3.11

# Build stage
FROM python:${PYTHON_VERSION}-slim AS builder
WORKDIR /app

RUN pip install --no-cache-dir uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies with uv (much faster than pip)
RUN uv sync --frozen --no-dev

COPY . .

# Runtime stage
FROM python:${PYTHON_VERSION}-slim
WORKDIR /app

# Install only runtime dependencies (if needed)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

# Copy only what's needed
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup app/ /app/app/
COPY --chown=appuser:appgroup pyproject.toml /app/

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER appuser
EXPOSE 8000

HEALTHCHECK --interval=30s CMD python -c "import requests; requests.get('http://localhost:8000/health')" || exit 1

CMD ["python", "-m", "app"]
```

## Interpreter Coupling — Both Stages, One Version

The pattern above copies a virtualenv across a stage boundary:

```dockerfile
COPY --from=builder /app/.venv /app/.venv
```

That venv is **not** portable across Python minor versions. Its packages live in
`/app/.venv/lib/python<X.Y>/site-packages`, and any compiled extension inside it
carries that version's ABI tag. Run it on a different minor version and the
interpreter looks in a directory that does not exist, so the venv is dropped from
`sys.path` **entirely** — not one missing package, all of them:

```
runtime python : 3.14.7
venv libdirs   : python3.12
sys.path       : ['', '/usr/local/lib/python314.zip',
                  '/usr/local/lib/python3.14',
                  '/usr/local/lib/python3.14/lib-dynload']
```

The symptom is `ModuleNotFoundError` on the **first non-stdlib import** the
entrypoint reaches, which reliably sends people hunting for a missing dependency
rather than a mismatched interpreter.

Drive both `FROM` lines from **one** `ARG`, as the example does. Renovate expands
`ARG` defaults used in `FROM`, so the version stays updatable while the halves
cannot drift apart.

### Why a bot can split the stages

Renovate matches images by name. When both stages name the same image it updates
them together; when they name *different* images — a builder like
`ghcr.io/astral-sh/uv:python3.12-alpine` next to a runtime of
`python:3.12-alpine` — its python rule matches only the second and moves that one
alone. Nothing in the diff shows a coupling was broken.

If you need uv in the builder, copy the binary in rather than switching base
images, so both stages stay on the same `python:` base:

```dockerfile
ARG PYTHON_VERSION=3.12
FROM ghcr.io/astral-sh/uv:0.12.7 AS uv

FROM python:${PYTHON_VERSION}-slim AS build
COPY --from=uv /uv /uvx /bin/

FROM python:${PYTHON_VERSION}-slim AS runtime
COPY --from=build /app/.venv /app/.venv
```

### Verify it, and give the check teeth

A `docker build` that succeeds proves the layers assembled, not that anything can
start. Run the image before publishing it, and assert the venv is on the path
rather than just importing something:

```sh
docker run --rm -i "$IMAGE" /app/.venv/bin/python - <<'EOF'
import sys
assert [p for p in sys.path if "/app/.venv/" in p], sys.path
print("ok", sys.version.split()[0])
EOF
```

`-i` is load-bearing. Without it docker does not forward stdin, `python -` reads
an **empty script**, and the check exits **0 having asserted nothing** — it then
passes on every image, including a broken one. Confirm any such gate by running
it against a deliberately mismatched build and requiring it to fail.

## Package Manager Summary

| Manager | Speed | Command | Notes |
|---------|-------|---------|-------|
| **uv** | 10-100x faster | `uv sync --frozen --no-dev` | Recommended |
| **poetry** | Standard | `poetry install --only=main` | Set `POETRY_VIRTUALENVS_IN_PROJECT=1` |
| **pip** | Standard | `pip install --no-cache-dir --prefix=/install -r requirements.txt` | Use `--prefix` for multi-stage |

## Performance Impact

| Metric | Full (1GB) | Slim (400MB) | Multi-Stage (150MB) | Optimized (100MB) |
|--------|------------|--------------|---------------------|-------------------|
| **Image Size** | 1GB | 400MB | 150MB | 100MB |
| **Pull Time** | 4m | 1m 30s | 35s | 20s |
| **Build Time (pip)** | 5m | 4m | 3m | 3m |
| **Build Time (uv)** | - | - | 45s | 30s |
| **Memory Usage** | 600MB | 350MB | 200MB | 150MB |

## Security Impact

| Image Type | Vulnerabilities | Size | Risk |
|------------|-----------------|------|------|
| **python:3.11 (full)** | 50-70 CVEs | 1GB | High |
| **python:3.11-slim** | 12-18 CVEs | 400MB | Medium |
| **Multi-stage slim** | 8-12 CVEs | 150MB | Low |
| **Distroless Python** | 4-6 CVEs | 140MB | Very Low |

## Agentic Optimizations

| Context | Command | Purpose |
|---------|---------|---------|
| **Quick build** | `DOCKER_BUILDKIT=1 docker build -t app .` | Fast build with cache |
| **Size check** | `docker images app --format "table {{.Repository}}\t{{.Size}}"` | Check image size |
| **Layer analysis** | `docker history app:latest --human \| head -20` | Find large layers |
| **Test imports** | `docker run --rm app python -c "import app"` | Verify imports work |
| **Dependency list** | `docker run --rm app pip list --format=freeze` | See installed packages |
| **Security scan** | `docker run --rm app pip-audit` | Check for vulnerabilities |

## Best Practices

- Use `slim` NOT `alpine` for Python
- Use uv for fastest builds (10-100x faster than pip)
- Use multi-stage builds
- Set `PYTHONUNBUFFERED=1` and `PYTHONDONTWRITEBYTECODE=1`
- Run as non-root user
- Use virtual environments and pin dependencies with lock files
- Use `--no-cache-dir` with pip

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Related Skills

- `container-development` - General container patterns, multi-stage builds, security
- `go-containers` - Go-specific container optimizations
- `nodejs-containers` - Node.js-specific container optimizations
