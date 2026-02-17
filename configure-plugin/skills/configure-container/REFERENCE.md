# Container Infrastructure Reference

Templates for container builds, workflows, scanning, and devcontainers.

## Container Build Workflow (with Security Scanning)

```yaml
name: Build Container

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write
      id-token: write  # Required for provenance/SBOM attestations

    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        if: github.event_name != 'pull_request'
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          labels: |
            org.opencontainers.image.title=${{ github.event.repository.name }}
            org.opencontainers.image.description=${{ github.event.repository.description }}
            org.opencontainers.image.vendor=Your Organization
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
            # For release-please component tags — escape dots in regex
            type=match,pattern=.*-v(\d+\.\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+\.\d+),group=1
            type=match,pattern=.*-v(\d+),group=1

      - id: build-push
        uses: docker/build-push-action@v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha,scope=app
          cache-to: type=gha,mode=max,scope=app
          provenance: ${{ startsWith(github.ref, 'refs/tags/') && 'mode=max' || 'false' }}
          sbom: ${{ startsWith(github.ref, 'refs/tags/') }}

      # Pin Trivy by SHA — never use @master
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@c1824fd6edce30d7ab345a9989de00bbd46ef284 # 0.34.0
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.meta.outputs.version }}
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'

      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@9e907b5e64f6b83e7804b09294d44122997950d6 # v4.32.3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'

      - name: Job summary
        if: always()
        run: |
          echo "## Container Build" >> $GITHUB_STEP_SUMMARY
          echo "- **Image**: \`${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Digest**: \`${{ steps.build-push.outputs.digest }}\`" >> $GITHUB_STEP_SUMMARY
          echo "- **Tags**:" >> $GITHUB_STEP_SUMMARY
          echo '${{ steps.meta.outputs.tags }}' | while read -r tag; do
            echo "  - \`$tag\`" >> $GITHUB_STEP_SUMMARY
          done
```

## .dockerignore Template

```
# Git
.git
.gitignore

# CI/CD
.github
.gitlab-ci.yml

# Dockerfiles (prevent variants leaking into build context)
Dockerfile*

# IDE
.idea
.vscode
*.swp
*.swo

# Dependencies (rebuilt in container)
node_modules
.venv
__pycache__
*.pyc

# Build artifacts
dist
build
target

# Test and coverage
coverage
.coverage
.pytest_cache
.nyc_output

# Documentation
docs
*.md
!README.md

# Environment
.env
.env.*
*.local

# Temporary
tmp
temp
*.tmp
*.log
```

## Dockerfile Template (Node.js/Frontend - Non-Root Alpine)

```dockerfile
# Build stage - use Alpine for minimal size
FROM node:24-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --only=production

COPY . .
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=cache,target=/app/node_modules/.vite \
    npm run build

# Runtime stage - minimal nginx Alpine
FROM nginx:1.27-alpine

LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production frontend application" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/

RUN chown -R appuser:appgroup /var/cache/nginx /var/run /var/log/nginx && \
    chmod -R 755 /var/cache/nginx /var/run /var/log/nginx

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
```

## Dockerfile Template (Python - Non-Root Slim)

```dockerfile
FROM python:3.13-slim AS builder

WORKDIR /app

RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-dev

FROM python:3.13-slim

LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production Python API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF
LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN groupadd -g 1001 appgroup && \
    useradd -u 1001 -g appgroup -s /bin/false appuser

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv

COPY --chown=appuser:appgroup . .

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Dockerfile Template (Go - Scratch/Distroless)

```dockerfile
FROM golang:1.23-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /app/server ./cmd/server

FROM scratch

LABEL org.opencontainers.image.source="https://github.com/OWNER/REPO" \
      org.opencontainers.image.description="Production Go service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /app/server /server

USER 1001:1001

EXPOSE 8080

ENTRYPOINT ["/server"]
```

## Devcontainer Template (Node/Frontend)

```json
{
  "name": "Project Dev Container",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:24",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "biomejs.biome",
        "ms-azuretools.vscode-docker"
      ]
    }
  },
  "postCreateCommand": "npm install",
  "forwardPorts": [3000, 5173],
  "remoteUser": "node"
}
```

## Devcontainer Template (Python)

```json
{
  "name": "Python Dev Container",
  "image": "mcr.microsoft.com/devcontainers/python:3.13",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {},
    "ghcr.io/devcontainers/features/github-cli:1": {}
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-python.python",
        "ms-python.vscode-pylance",
        "charliermarsh.ruff",
        "ms-azuretools.vscode-docker"
      ]
    }
  },
  "postCreateCommand": "pip install uv && uv sync",
  "forwardPorts": [8000],
  "remoteUser": "vscode"
}
```

## Security Best Practices References

- [Docker Security Best Practices](https://docs.docker.com/develop/security-best-practices/)
- [OWASP Docker Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html)
- [Snyk Container Security Best Practices](https://snyk.io/blog/10-docker-image-security-best-practices/)
- [Sysdig Dockerfile Best Practices](https://sysdig.com/blog/dockerfile-best-practices/)
