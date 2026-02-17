---
model: haiku
created: 2026-01-15
modified: 2026-02-14
reviewed: 2026-01-15
name: python-containers
description: |
  Python-specific container optimization patterns including slim base images (NOT Alpine),
  virtual environment handling, multi-stage builds with pip/poetry/uv, and optimization
  from ~1GB to ~80-120MB. Covers musl libc issues, wheel building, and Python-specific
  dependency management patterns.
  Use when working with Python containers, Dockerfiles for Python apps, or optimizing Python image sizes.
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
# Build stage
FROM python:3.11-slim AS builder
WORKDIR /app

RUN pip install --no-cache-dir uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies with uv (much faster than pip)
RUN uv sync --frozen --no-dev

COPY . .

# Runtime stage
FROM python:3.11-slim
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
