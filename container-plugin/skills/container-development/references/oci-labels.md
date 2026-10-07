# Container Labels (OCI Annotations) — reference

## Container Labels (OCI Annotations)

Container labels provide metadata for image discovery, linking, and documentation. **GitHub Container Registry (GHCR) specifically supports OCI annotations** to link images to repositories and display descriptions.

### Required Labels for GHCR

| Label | Purpose | Example |
|-------|---------|---------|
| `org.opencontainers.image.source` | **Links image to repository** (enables GHCR features) | `https://github.com/owner/repo` |
| `org.opencontainers.image.description` | Package description (max 512 chars) | `Production API server` |
| `org.opencontainers.image.licenses` | SPDX license identifier (max 256 chars) | `MIT`, `Apache-2.0` |

### Recommended Labels

| Label | Purpose | Example |
|-------|---------|---------|
| `org.opencontainers.image.version` | Semantic version | `1.2.3` |
| `org.opencontainers.image.revision` | Git commit SHA | `abc1234` |
| `org.opencontainers.image.created` | Build timestamp (RFC 3339) | `2025-01-19T12:00:00Z` |
| `org.opencontainers.image.title` | Human-readable name | `My Application` |
| `org.opencontainers.image.vendor` | Organization name | `Forum Virium Helsinki` |
| `org.opencontainers.image.url` | Project homepage | `https://example.com` |
| `org.opencontainers.image.documentation` | Documentation URL | `https://docs.example.com` |

### Adding Labels in Dockerfile

```dockerfile
# Static labels (set at build time)
LABEL org.opencontainers.image.source="https://github.com/owner/repo" \
      org.opencontainers.image.description="Production API server" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Forum Virium Helsinki"

# Dynamic labels (via build args)
ARG VERSION=dev
ARG BUILD_DATE
ARG VCS_REF

LABEL org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"
```

### Adding Labels at Build Time

```bash
docker build \
  --label "org.opencontainers.image.source=https://github.com/owner/repo" \
  --label "org.opencontainers.image.description=My container image" \
  --label "org.opencontainers.image.licenses=MIT" \
  --build-arg VERSION=1.2.3 \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  -t myapp:1.2.3 .
```

### GitHub Actions with docker/metadata-action

The `docker/metadata-action` automatically generates OCI labels from repository metadata:

```yaml
- id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    labels: |
      org.opencontainers.image.title=My Application
      org.opencontainers.image.description=Production API server
      org.opencontainers.image.vendor=Forum Virium Helsinki

- uses: docker/build-push-action@v6
  with:
    labels: ${{ steps.meta.outputs.labels }}
```

**Auto-generated labels by metadata-action:**
- `org.opencontainers.image.source` (from repository URL)
- `org.opencontainers.image.revision` (from commit SHA)
- `org.opencontainers.image.created` (build timestamp)
- `org.opencontainers.image.version` (from tags/refs)
