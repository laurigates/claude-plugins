# Python Container Optimization - Reference

Detailed reference material for Python container optimization patterns.

## The Optimization Journey: 1GB to 80-120MB

### Step 1: The Problem - Full Python Base (1GB)

```dockerfile
# Full Debian with all dev packages
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

## Package Manager Patterns

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
