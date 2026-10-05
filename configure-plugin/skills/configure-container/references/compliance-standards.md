# Container Compliance Standards

Used by Step 3 (Analyze each component) of `/configure:container` — the per-component check tables and severities.

**Dockerfile Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Exists | Required for containerized projects | FAIL if missing |
| Multi-stage | Required (build + runtime stages) | FAIL if missing |
| HEALTHCHECK | Required for K8s probes | FAIL if missing |
| Non-root user | REQUIRED (not optional) | FAIL if missing |
| .dockerignore | Required | WARN if missing |
| .dockerignore `Dockerfile*` | Use glob to exclude all Dockerfile variants from context | WARN if only `Dockerfile` |
| Base image version | Latest stable (check Docker Hub) | WARN if outdated |
| Minimal base | Alpine for Node, slim for Python | WARN if bloated |

**Base Image Standards (verify latest before reporting):**

| Language | Build Image | Runtime Image | Size Target |
|----------|-------------|---------------|-------------|
| Node.js | `node:24-alpine` (LTS) | `nginx:1.30-alpine` | < 50MB |
| Python | `python:3.14-slim` | `python:3.14-slim` | < 150MB |
| Go | `golang:1.26-alpine` | `scratch` or `alpine:3.23` | < 20MB |
| Rust | `rust:1.96-alpine` | `alpine:3.23` | < 20MB |

**Security Hardening Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Non-root USER | Required (create dedicated user) | FAIL if missing |
| Read-only FS | `--read-only` or RO annotation | INFO if missing |
| No new privileges | `--security-opt=no-new-privileges` | INFO if missing |
| Drop capabilities | `--cap-drop=all` + explicit `--cap-add` | INFO if missing |
| No secrets in image | No ENV with sensitive data | FAIL if found |

**Build Workflow Standards:**

| Check | Standard | Severity |
|-------|----------|----------|
| Workflow exists | container-build.yml or similar | FAIL if missing |
| checkout action | v4+ | WARN if older |
| build-push-action | v6+ | WARN if older |
| Multi-platform | linux/amd64,linux/arm64 | WARN if missing |
| Build caching | GHA cache enabled | WARN if missing |
| Security scan | Trivy/Grype in workflow | WARN if missing |
| `id-token: write` | Required when provenance/SBOM configured | WARN if missing |
| Cache scope | Explicit `scope=` for multi-image builds | WARN if missing |
| Scanner pinned | Trivy/Grype action pinned by SHA (not `@master`) | WARN if unpinned |

**Container Labels Standards (GHCR Integration):**

| Check | Standard | Severity |
|-------|----------|----------|
| `org.opencontainers.image.source` | Required - Links to repository | WARN if missing |
| `org.opencontainers.image.description` | Required - Package description | WARN if missing |
| `org.opencontainers.image.licenses` | Required - SPDX license | WARN if missing |
