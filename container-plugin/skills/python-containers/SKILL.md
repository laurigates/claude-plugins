---
model: haiku
created: 2026-01-15
modified: 2026-01-15
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

**⚠️ CRITICAL**: Do NOT use Alpine for Python containers!

```dockerfile
# ❌ BAD: Alpine + Python = Problems
FROM python:3.11-alpine
# Will have issues with numpy, pandas, psycopg2, pillow, etc.
```

**Problems with Alpine + Python**:
- musl libc vs glibc incompatibility
- Many wheels don't work (numpy, pandas, scipy)
- Forces compilation from source (slow builds)
- Larger final images due to build tools
- Runtime errors with native extensions

**✅ Use `slim` instead**: Python slim images are based on Debian with minimal packages.

## The Optimization Journey: 1GB → 80-120MB

### Step 1: The Problem - Full Python Base (1GB)

```dockerfile
# ❌ BAD: Full Debian with all dev packages
FROM python:3.11
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

**Issues**:
- Full Debian base (~120MB)
- Build tools and compilers (~400MB)
- Unnecessary system packages
- All pip cache included

**Image size: ~1GB**

### Step 2: Slim Base (400MB)

```dockerfile
# ✅ BETTER: Slim removes unnecessary packages
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
```

**Improvements**:
- Minimal Debian (~70MB vs ~120MB full)
- No build tools (but may need them for some packages)
- Pip cache disabled

**Image size: ~400MB** (60% reduction)

### Step 3: Multi-Stage with Virtual Environment (150-200MB)

```dockerfile
# Build stage
FROM python:3.11-slim AS builder
WORKDIR /app

# Install uv (modern pip replacement, 10-100x faster)
RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

# Runtime stage
FROM python:3.11-slim
WORKDIR /app

# Create non-root user
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

# Copy virtual environment
COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup . .

ENV PATH="/app/.venv/bin:$PATH"
USER appuser

CMD ["python", "-m", "myapp"]
```

**Image size: ~150-200MB** (50% reduction from 400MB)

### Step 4: Optimized with uv (80-120MB)

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

**Image size: ~80-120MB** (40-60% reduction from 150-200MB)

## Package Manager Patterns

### uv (Recommended - 10-100x faster)

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app

# Install uv
RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Runtime
FROM python:3.11-slim
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
```

**Benefits**:
- 10-100x faster than pip
- Better dependency resolution
- Native lockfile support
- Smaller cache

### poetry

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app

# Install poetry
RUN pip install --no-cache-dir poetry

# Configure poetry to create venv in project
ENV POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_NO_INTERACTION=1

COPY pyproject.toml poetry.lock ./
RUN poetry install --only=main --no-root

COPY . .
RUN poetry install --only=main

# Runtime
FROM python:3.11-slim
COPY --from=builder /app/.venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"
```

### pip with requirements.txt

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app

# Install to specific directory
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime
FROM python:3.11-slim
COPY --from=builder /install /usr/local
```

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

## Python-Specific .dockerignore

```
# Python artifacts
__pycache__/
*.py[cod]
*$py.class
*.so
.Python

# Virtual environments
venv/
env/
ENV/
.venv/
virtualenv/

# Distribution / packaging
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
MANIFEST

# Testing
.pytest_cache/
.tox/
.coverage
.coverage.*
htmlcov/
.hypothesis/
*.cover

# Type checking
.mypy_cache/
.pytype/
.pyre/
.pyright/

# Development
.vscode/
.idea/
*.swp
.DS_Store
.env
.env.*

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

# Jupyter
.ipynb_checkpoints/
*.ipynb

# Database
*.db
*.sqlite

# Logs
*.log
logs/
```

## Handling C Extensions

### Packages with Compiled Extensions (numpy, pandas, pillow)

```dockerfile
# Build stage - includes build tools
FROM python:3.11-slim AS builder
WORKDIR /app

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

# Runtime stage - only runtime libraries
FROM python:3.11-slim
WORKDIR /app

# Install only runtime dependencies (no compilers)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup app/ /app/app/

ENV PATH="/app/.venv/bin:$PATH"
USER appuser
CMD ["python", "-m", "app"]
```

### Database Drivers

```dockerfile
# PostgreSQL (psycopg2)
RUN apt-get install -y --no-install-recommends \
    libpq-dev gcc \
    && pip install psycopg2-binary \
    && apt-get purge -y gcc \
    && rm -rf /var/lib/apt/lists/*

# Or use psycopg3 (pure Python option)
RUN pip install psycopg[binary]

# MySQL
RUN apt-get install -y --no-install-recommends \
    default-libmysqlclient-dev gcc \
    && pip install mysqlclient \
    && apt-get purge -y gcc \
    && rm -rf /var/lib/apt/lists/*
```

## Framework-Specific Patterns

### FastAPI / Uvicorn

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .

FROM python:3.11-slim
WORKDIR /app
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup app/ /app/app/

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Django

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .

# Collect static files
RUN .venv/bin/python manage.py collectstatic --noinput

FROM python:3.11-slim
WORKDIR /app
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup --from=builder /app/staticfiles /app/staticfiles
COPY --chown=appuser:appgroup . .

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=project.settings

USER appuser
EXPOSE 8000

CMD ["gunicorn", "project.wsgi:application", "--bind", "0.0.0.0:8000"]
```

### Flask / Gunicorn

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .

FROM python:3.11-slim
WORKDIR /app
RUN addgroup --gid 1001 appgroup && \
    adduser --uid 1001 --gid 1001 --disabled-password appuser

COPY --from=builder --chown=appuser:appgroup /app/.venv /app/.venv
COPY --chown=appuser:appgroup app/ /app/app/

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8000

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "app:create_app()"]
```

## Distroless for Python

```dockerfile
# Build stage
FROM python:3.11-slim AS builder
WORKDIR /app
RUN pip install --no-cache-dir uv
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev
COPY . .

# Runtime with distroless
FROM gcr.io/distroless/python3-debian12

WORKDIR /app
COPY --from=builder /app/.venv/lib/python3.11/site-packages /app/site-packages
COPY --from=builder /app/app /app/app

ENV PYTHONPATH=/app/site-packages
CMD ["app/main.py"]
```

**Note**: Distroless is harder with Python due to venv path complexities. Slim is usually better.

## Agentic Optimizations

Python-specific container commands:

| Context | Command | Purpose |
|---------|---------|---------|
| **Quick build** | `DOCKER_BUILDKIT=1 docker build -t app .` | Fast build with cache |
| **Size check** | `docker images app --format "table {{.Repository}}\t{{.Size}}"` | Check image size |
| **Layer analysis** | `docker history app:latest --human \| head -20` | Find large layers |
| **Test imports** | `docker run --rm app python -c "import app"` | Verify imports work |
| **Dependency list** | `docker run --rm app pip list --format=freeze` | See installed packages |
| **Security scan** | `docker run --rm app pip-audit` | Check for vulnerabilities |

## Best Practices

**Always**:
- Use `slim` NOT `alpine` for Python
- Use uv for fastest builds (10-100x faster than pip)
- Use multi-stage builds
- Set `PYTHONUNBUFFERED=1` for proper logging
- Set `PYTHONDONTWRITEBYTECODE=1` to skip .pyc files
- Run as non-root user
- Use virtual environments
- Pin all dependencies with lock files

**Never**:
- Use Alpine with Python (musl libc issues)
- Use `pip install` without `--no-cache-dir`
- Include `__pycache__` or `.pyc` files
- Run as root user
- Use `python:latest` (always pin versions)
- Include test files in production image

## Common Issues

### ImportError with Native Extensions

```dockerfile
# If getting ImportError in runtime
# Install runtime libraries in runtime stage
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libpq5 \        # For psycopg2
    libgomp1 \      # For numpy/pandas
    && rm -rf /var/lib/apt/lists/*
```

### Slow Builds

```dockerfile
# Use uv instead of pip - 10-100x faster
RUN pip install --no-cache-dir uv
RUN uv sync --frozen --no-dev
```

### Large Image Sizes

```bash
# Find what's taking space
docker history app:latest --human --no-trunc

# Check installed packages
docker run --rm app pip list --format=columns

# Remove unnecessary packages from requirements
```

## Related Skills

- `container-development` - General container patterns, multi-stage builds, security
- `go-containers` - Go-specific container optimizations
- `nodejs-containers` - Node.js-specific container optimizations
