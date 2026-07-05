# Skaffold Configuration Reference

Standard Skaffold configuration (v2025.1) for local Kubernetes development
with OrbStack and dotenvx. (Absorbed the former `skaffold-standards`
reference skill.)

## Report Template

```
Skaffold Compliance Report
==============================
Project Type: <type> (detected)
Skaffold: ./skaffold.yaml (found/missing)

Configuration Checks:
  API version     <version>         PASS/WARN
  local.push      <value>           PASS/FAIL
  useBuildkit     <value>           PASS/WARN
  Port security   <address>         PASS/FAIL
  statusCheck     <value>           PASS/WARN
  kubeContext     <value>           PASS/INFO
  dotenvx hooks   <status>          PASS/INFO
  JSON log parse  <status>          PASS/INFO

Profiles Found:
  db-only         Present/Missing
  services-only   Present/Missing
  minimal         Present/Missing

Scripts:
  generate-secrets.sh  Present/Missing

Overall: <status>
```

## Standard Skaffold Template

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

### Hook Placement Patterns

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

## Compliance Requirements

### Cluster Context (CRITICAL)

**Always specify `kubeContext: orbstack`** in the deploy configuration — the
standard local development context — and include `--kube-context=orbstack` on
Skaffold commands (`skaffold dev --kube-context=orbstack`, `skaffold run …`,
`skaffold delete …`). Only use a different context if explicitly requested.

### Required Elements

| Element | Requirement |
|---------|-------------|
| API version | `skaffold/v4beta13` (latest stable) |
| deploy.kubeContext | `orbstack` (default) |
| local.push | `false` |
| portForward.address | `127.0.0.1` — never `0.0.0.0` or omitted |
| statusCheck | `true` recommended |
| dotenvx hooks | Recommended for secrets |

### Recommended Profiles

| Profile | Purpose | Required |
|---------|---------|----------|
| `db-only` | Database only + local app dev with hot-reload (`skaffold dev -p db-only` + `bun run dev`) | Recommended |
| `services-only` | Backend services (db + APIs, `artifacts: []`) + local frontend dev | Recommended |
| `minimal` | Without optional features | Optional |
| `e2e` | Full stack (`k8s/*.yaml`) for end-to-end testing | Optional |
| `migration-test` | Database manifests + a `test:` stage running the migration script | Optional |

### Build Validation Hooks

Per-artifact pre-build validation (in addition to the dotenvx secrets hook):

```yaml
build:
  artifacts:
    - image: app
      hooks:
        before:
          - command: ['bun', 'run', 'check']
            os: [darwin, linux]
```

## Project Type Variations

| Project type | Shape |
|--------------|-------|
| Frontend with backend services | Default full-stack manifests; a `services-only` profile with `artifacts: []` for local frontend dev |
| API service only | Flat `k8s/*.yaml` manifests; usually no profiles needed |
| Pure infrastructure repo | Skaffold usually not applicable — use Terraform/Helm directly (report SKIP) |

## Status Levels

| Status | Condition |
|--------|-----------|
| PASS | Compliant configuration |
| WARN | Present but missing recommended elements |
| FAIL | Security issue (e.g., portForward without localhost binding) |
| SKIP | Not applicable (e.g., infrastructure repo) |

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Pods not starting | Increase `statusCheckDeadlineSeconds`; enable `tolerateFailuresUntilDeadline: true`; `kubectl logs -f <pod>` |
| Port forwarding issues | Port already in use; service name matches deployment; `address: 127.0.0.1` set |
| Slow builds | `useBuildkit: true`, `useDockerCLI: true`, `concurrency: 0` |
