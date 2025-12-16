---
name: fvh-skaffold
description: |
  FVH (Forum Virium Helsinki) Skaffold configuration standards for local Kubernetes
  development with OrbStack and dotenvx. Use when configuring Skaffold, setting up local
  K8s development, or when the user mentions FVH Skaffold, local development, Kubernetes
  profiles, or dotenvx secrets.
---

# FVH Skaffold Standards

## Version: 2025.1

FVH standard Skaffold configuration for local Kubernetes development workflows using OrbStack and dotenvx.

## Standard Configuration

### API Version

```yaml
apiVersion: skaffold/v4beta13
kind: Config
```

Always use the latest stable API version. Currently: `skaffold/v4beta13`

### Build Configuration

```yaml
build:
  local:
    push: false           # Never push to registry for local dev
    useDockerCLI: true    # Use Docker CLI (better caching)
    useBuildkit: true     # Enable BuildKit for performance
    concurrency: 0        # Unlimited parallel builds
  # Generate secrets from encrypted .env files before building
  hooks:
    before:
      - command: ['sh', '-c', 'dotenvx run -- sh scripts/generate-secrets.sh']
        os: [darwin, linux]
  artifacts:
    - image: app-name
      context: .
      docker:
        dockerfile: Dockerfile
    # Optional: init container for database migrations
    - image: app-db-init
      context: .
      docker:
        dockerfile: Dockerfile.db-init
```

### Port Forwarding (Security)

**IMPORTANT**: Always bind to localhost only:

```yaml
portForward:
  - resourceType: service
    resourceName: app-name
    port: 80
    localPort: 8080
    address: 127.0.0.1    # REQUIRED: Bind to localhost only
```

Never use `0.0.0.0` or omit the address field.

### Deploy Configuration

```yaml
deploy:
  kubeContext: orbstack  # OrbStack for local development
  kubectl:
    defaultNamespace: app-name
    # Optional: validation before deploy
    hooks:
      before:
        - host:
            command: ["sh", "-c", "echo 'Deploying...'"]
            os: [darwin, linux]
  statusCheck: true
  # Extended timeout for init containers (db migrations, seeding)
  statusCheckDeadlineSeconds: 180
  tolerateFailuresUntilDeadline: true
  # Parse JSON logs from applications for cleaner output
  logs:
    jsonParse:
      fields: ["message", "level", "timestamp"]
```

## Standard Profiles

### Profile: `db-only`

Database only - for running app dev server locally with hot-reload:

```yaml
profiles:
  - name: db-only
    build:
      artifacts: []  # Don't build app
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
        namespace: app-name
        port: 5432
        localPort: 5435
        address: 127.0.0.1
```

**Use case**: Run `skaffold dev -p db-only` + `bun run dev` for hot-reload development

### Profile: `services-only`

Backend services only (database, APIs) - use with local frontend dev:

```yaml
profiles:
  - name: services-only
    build:
      artifacts: []  # Don't build frontend
    manifests:
      rawYaml:
        - k8s/namespace.yaml
        - k8s/database/*.yaml
        - k8s/api/*.yaml
    portForward:
      - resourceType: service
        resourceName: postgresql
        port: 5432
        localPort: 5435
        address: 127.0.0.1
```

**Use case**: Run `skaffold dev -p services-only` + `bun run dev` for hot-reload frontend

### Profile: `e2e` or `e2e-with-prod-data`

Full stack for end-to-end testing:

```yaml
profiles:
  - name: e2e
    manifests:
      rawYaml:
        - k8s/*.yaml  # All manifests
```

### Profile: `migration-test`

Database migration testing:

```yaml
profiles:
  - name: migration-test
    manifests:
      rawYaml:
        - k8s/database/*.yaml
    test:
      - image: migration-tester
        custom:
          - command: "run-migrations.sh"
```

## Compliance Requirements

### Cluster Context (CRITICAL)

**Always specify `kubeContext: orbstack`** in deploy configuration. This is the FVH standard local development context.

```yaml
deploy:
  kubeContext: orbstack
  kubectl: {}
```

When using Skaffold commands, always include `--kube-context=orbstack`:

```bash
skaffold dev --kube-context=orbstack
skaffold run --kube-context=orbstack
skaffold delete --kube-context=orbstack
```

Only use a different context if explicitly requested by the user.

### Required Elements

| Element | Requirement |
|---------|-------------|
| API version | `skaffold/v4beta13` |
| deploy.kubeContext | `orbstack` (default) |
| local.push | `false` |
| portForward.address | `127.0.0.1` |
| statusCheck | `true` recommended |
| dotenvx hooks | Recommended for secrets |

### Recommended Profiles

Depending on project type:

| Profile | Purpose | Required |
|---------|---------|----------|
| `db-only` | Database only + local app dev | Recommended |
| `services-only` | Backend services + local frontend | Recommended |
| `minimal` | Without optional features | Optional |
| `e2e` | Full stack testing | Optional |

## Project Type Variations

### Frontend with Backend Services

```yaml
# Default: Full stack
manifests:
  rawYaml:
    - k8s/namespace.yaml
    - k8s/frontend/*.yaml
    - k8s/backend/*.yaml
    - k8s/database/*.yaml

profiles:
  - name: services-only
    build:
      artifacts: []
    manifests:
      rawYaml:
        - k8s/namespace.yaml
        - k8s/backend/*.yaml
        - k8s/database/*.yaml
```

### API Service Only

```yaml
# Simpler configuration
manifests:
  rawYaml:
    - k8s/*.yaml

# No profiles needed for simple services
```

### Infrastructure Testing

Skaffold may not be applicable for pure infrastructure repos. Use Terraform/Helm directly.

## dotenvx Integration

FVH projects use [dotenvx](https://dotenvx.com/) for encrypted secrets management in local development.

### How It Works

1. **Encrypted .env files**: `.env` files contain encrypted values, safe to commit
2. **Private key**: `DOTENV_PRIVATE_KEY` decrypts values at runtime
3. **Hooks**: Skaffold hooks run `dotenvx run -- script` to inject secrets
4. **Generated secrets**: Scripts create Kubernetes Secret manifests from .env

### Build Hooks with dotenvx

```yaml
build:
  hooks:
    before:
      - command: ['sh', '-c', 'dotenvx run -- sh scripts/generate-secrets.sh']
        os: [darwin, linux]
```

### Deploy Hooks with dotenvx

```yaml
deploy:
  kubectl:
    hooks:
      before:
        - host:
            command: ["sh", "-c", "dotenvx run -- sh scripts/generate-secrets.sh"]
```

### Generate Secrets Script

Create `scripts/generate-secrets.sh`:

```bash
#!/bin/bash
# Generate Kubernetes secrets from .env using dotenvx
set -euo pipefail

# Validate required env vars are set
: "${DATABASE_URL:?DATABASE_URL must be set}"
: "${SECRET_KEY:?SECRET_KEY must be set}"

# Generate app secrets manifest
cat > k8s/app-secrets.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: app-name
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

# Create encrypted .env
dotenvx set DATABASE_URL "postgresql://..."
dotenvx set SECRET_KEY "..."

# Encrypt existing .env
dotenvx encrypt

# Store private key securely (NOT in git)
echo "DOTENV_PRIVATE_KEY=..." >> ~/.zshrc
```

## Build Hooks (Validation)

Pre-build hooks for validation (in addition to dotenvx):

```yaml
build:
  artifacts:
    - image: app
      hooks:
        before:
          - command: ['bun', 'run', 'check']
            os: [darwin, linux]
```

## Status Levels

| Status | Condition |
|--------|-----------|
| PASS | Compliant configuration |
| WARN | Present but missing recommended elements |
| FAIL | Security issue (e.g., portForward without localhost) |
| SKIP | Not applicable (e.g., infrastructure repo) |

## Troubleshooting

### Pods Not Starting

- Check `statusCheckDeadlineSeconds` (increase if needed)
- Enable `tolerateFailuresUntilDeadline: true`
- Review pod logs: `kubectl logs -f <pod>`

### Port Forwarding Issues

- Ensure port is not already in use
- Check service name matches deployment
- Verify `address: 127.0.0.1` is set

### Build Caching

- Enable BuildKit: `useBuildkit: true`
- Use Docker CLI: `useDockerCLI: true`
- Set `concurrency: 0` for parallel builds
