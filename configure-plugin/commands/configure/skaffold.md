---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
description: Check and configure Skaffold for project standards
allowed-tools: Glob, Grep, Read, Write, Edit, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix]"
---

# /configure:skaffold

Check and configure Skaffold against project standards.

## Context

This command validates Skaffold configuration for local Kubernetes development using OrbStack.

**Skills referenced**: `skaffold-standards`, `container-development`, `skaffold-orbstack`

**Applicability**: Only for projects with Kubernetes deployment (k8s/, helm/ directories)

## Version Checking

**CRITICAL**: Before configuring Skaffold, verify latest versions:

1. **Skaffold**: Check [skaffold.dev](https://skaffold.dev/) or [GitHub releases](https://github.com/GoogleContainerTools/skaffold/releases)
2. **API version**: Current recommended is `skaffold/v4beta13`
3. **dotenvx**: Check [dotenvx.com](https://dotenvx.com/) for latest patterns

Use WebSearch or WebFetch to verify current Skaffold version and API version.

## Workflow

### Phase 1: Applicability Check

1. Check for `k8s/` or `helm/` directories
2. If not found: Report SKIP (Skaffold not applicable)
3. If found: Check for `skaffold.yaml`

### Phase 2: Configuration Detection

Parse `skaffold.yaml` for:
- API version
- Build configuration
- Deploy configuration
- Port forwarding
- Profiles

### Phase 3: Compliance Analysis

**Required Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| API version | `skaffold/v4beta13` | WARN if older |
| local.push | `false` | FAIL if true |
| portForward.address | `127.0.0.1` | FAIL if missing/0.0.0.0 |
| useBuildkit | `true` | WARN if false |
| kubeContext | `orbstack` | INFO (recommended for local dev) |
| dotenvx hooks | Build or deploy hooks | INFO (recommended for secrets) |

**Security-Critical:**
- Port forwarding MUST bind to localhost only (`127.0.0.1`)
- Never allow `0.0.0.0` or missing address
- Secrets should be generated via dotenvx hooks, not hardcoded

**Recommended:**
- `db-only` or `services-only` profile for local dev workflow
- `statusCheck: true` with reasonable deadline (180s for init containers)
- `tolerateFailuresUntilDeadline: true` for graceful pod initialization
- JSON log parsing for structured application logs
- dotenvx hooks for secrets generation from .env files

### Phase 4: Report Generation

```
Skaffold Compliance Report
==============================
Project Type: frontend (detected)
Skaffold: ./skaffold.yaml (found)

Configuration Checks:
  API version     v4beta13          ✅ PASS
  local.push      false             ✅ PASS
  useBuildkit     true              ✅ PASS
  Port security   127.0.0.1         ✅ PASS
  statusCheck     true              ✅ PASS
  kubeContext     orbstack          ✅ PASS
  dotenvx hooks   build hooks       ✅ PASS
  JSON log parse  enabled           ✅ PASS

Profiles Found:
  db-only         ✅ Present
  services-only   ✅ Present
  minimal         ✅ Present

Scripts:
  generate-secrets.sh ✅ Present (dotenvx integration)

Overall: Fully compliant
```

### Phase 5: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing skaffold.yaml**: Create from standard template
2. **Security issues**: Fix port forwarding addresses
3. **Missing profiles**: Add `db-only` profile template
4. **Outdated API**: Update apiVersion to v4beta13
5. **Missing dotenvx hooks**: Add secrets generation hook
6. **Missing scripts**: Create `scripts/generate-secrets.sh` template
7. **Missing kubeContext**: Add `orbstack` for local development

### Phase 6: Standards Tracking

Update `.project-standards.yaml`:

```yaml
components:
  skaffold: "2025.1"
```

## Standard Template

```yaml
apiVersion: skaffold/v4beta13
kind: Config
metadata:
  name: project-name-local

build:
  local:
    push: false
    useDockerCLI: true
    useBuildkit: true
    concurrency: 0
  # Generate secrets before building
  hooks:
    before:
      - command: ['sh', '-c', 'dotenvx run -- sh scripts/generate-secrets.sh']
        os: [darwin, linux]
  artifacts:
    - image: app
      context: .
      docker:
        dockerfile: Dockerfile
    # Optional: init container for database migrations
    - image: app-db-init
      context: .
      docker:
        dockerfile: Dockerfile.db-init

manifests:
  rawYaml:
    - k8s/namespace.yaml
    - k8s/postgresql-secret.yaml
    - k8s/postgresql-configmap.yaml
    - k8s/postgresql-service.yaml
    - k8s/postgresql-statefulset.yaml
    - k8s/app-secrets.yaml
    - k8s/app-deployment.yaml
    - k8s/app-service.yaml

deploy:
  kubeContext: orbstack  # OrbStack for local development
  kubectl:
    defaultNamespace: project-name
    # Optional: validation before deploy
    hooks:
      before:
        - host:
            command: ["sh", "-c", "echo 'Validating configuration...'"]
            os: [darwin, linux]
  statusCheck: true
  # Extended timeout for init containers (db migrations, seeding)
  statusCheckDeadlineSeconds: 180
  # Don't fail immediately on pod restarts during initialization
  tolerateFailuresUntilDeadline: true
  # Parse JSON logs from applications for cleaner output
  logs:
    jsonParse:
      fields: ["message", "level", "timestamp"]

portForward:
  - resourceType: service
    resourceName: postgresql
    namespace: project-name
    port: 5432
    localPort: 5435
    address: 127.0.0.1  # REQUIRED: localhost only
  - resourceType: service
    resourceName: app
    namespace: project-name
    port: 3000
    localPort: 8080
    address: 127.0.0.1  # REQUIRED: localhost only

profiles:
  # Database only - for running app dev server locally
  - name: db-only
    build:
      artifacts: []
    manifests:
      rawYaml:
        - k8s/namespace.yaml
        - k8s/postgresql-secret.yaml
        - k8s/postgresql-configmap.yaml
        - k8s/postgresql-service.yaml
        - k8s/postgresql-statefulset.yaml
    portForward:
      - resourceType: service
        resourceName: postgresql
        namespace: project-name
        port: 5432
        localPort: 5435
        address: 127.0.0.1

  # Minimal - without optional features
  - name: minimal
    patches:
      - op: replace
        path: /manifests/rawYaml/4
        value: k8s/postgresql-statefulset-minimal.yaml
```

## dotenvx Integration

Projects use [dotenvx](https://dotenvx.com/) for encrypted secrets management in local development.

### How It Works

1. **Encrypted .env files**: `.env` files contain encrypted values
2. **Private key**: `DOTENV_PRIVATE_KEY` decrypts values at runtime
3. **Hooks**: Skaffold hooks run `dotenvx run -- script` to inject secrets
4. **Generated secrets**: Scripts create Kubernetes Secret manifests from .env

### Generate Secrets Script Template

Create `scripts/generate-secrets.sh`:

```bash
#!/bin/bash
# Generate Kubernetes secrets from .env using dotenvx
# Run with: dotenvx run -- sh scripts/generate-secrets.sh

set -euo pipefail

# Validate required env vars are set (decrypted by dotenvx)
: "${DATABASE_URL:?DATABASE_URL must be set}"
: "${SECRET_KEY:?SECRET_KEY must be set}"

# Generate app secrets manifest
cat > k8s/app-secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: project-name
type: Opaque
stringData:
  DATABASE_URL: "${DATABASE_URL}"
  SECRET_KEY: "${SECRET_KEY}"
EOF

echo "Generated k8s/app-secrets.yaml"
```

### dotenvx Setup

```bash
# Install dotenvx
curl -sfS https://dotenvx.sh | sh

# Create encrypted .env (first time)
dotenvx set DATABASE_URL "postgresql://..."
dotenvx set SECRET_KEY "..."

# Encrypt existing .env
dotenvx encrypt

# Store private key securely (NOT in git)
echo "DOTENV_PRIVATE_KEY=..." >> ~/.zshrc
```

### Usage Patterns

**Build hook** (runs before building images):
```yaml
build:
  hooks:
    before:
      - command: ['sh', '-c', 'dotenvx run -- sh scripts/generate-secrets.sh']
        os: [darwin, linux]
```

**Deploy hook** (runs before applying manifests):
```yaml
deploy:
  kubectl:
    hooks:
      before:
        - host:
            command: ["sh", "-c", "dotenvx run -- sh scripts/generate-secrets.sh"]
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply fixes automatically |

## Security Note

Port forwarding without `address: 127.0.0.1` exposes services to the network.
This is a **FAIL** condition that should always be fixed.

## See Also

- `/configure:dockerfile` - Container configuration
- `/configure:all` - Run all compliance checks
- `skaffold-standards` skill - Skaffold patterns
