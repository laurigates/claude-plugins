---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: helm-release-management
description: |
  Manage Helm releases: install, upgrade, uninstall, list, and inspect releases.
  Covers helm install, helm upgrade, helm list, helm status, release history.
  Use when user mentions deploying Helm charts, upgrading releases, helm install,
  helm upgrade, or managing Kubernetes deployments with Helm.
allowed-tools: Bash, Read, Grep, Glob
---

# Helm Release Management

Comprehensive guidance for day-to-day Helm release operations including installation, upgrades, uninstallation, and release tracking.

## When to Use

Use this skill automatically when:
- User requests deploying or installing Helm charts
- User mentions upgrading or updating Helm releases
- User wants to list or manage releases across namespaces
- User needs to check release history or status
- User requests uninstalling or removing releases

## Core Release Operations

### Install New Release

```bash
# Basic install
helm install <release-name> <chart> --namespace <namespace> --create-namespace

# Install with custom values
helm install myapp bitnami/nginx \
  --namespace production \
  --create-namespace \
  --values values.yaml \
  --set replicaCount=3

# Install with atomic rollback on failure
helm install myapp ./mychart \
  --namespace staging \
  --atomic \
  --timeout 5m \
  --wait

# Install from repository with specific version
helm install mydb bitnami/postgresql \
  --namespace database \
  --version 12.1.9 \
  --values db-values.yaml

# Dry-run before actual install
helm install myapp ./chart \
  --namespace prod \
  --dry-run \
  --debug
```

**Key Flags:**
- `--namespace` - Target namespace (ALWAYS specify explicitly)
- `--create-namespace` - Create namespace if it doesn't exist
- `--values` / `-f` - Specify values file(s)
- `--set` - Override individual values
- `--atomic` - Rollback automatically on failure (RECOMMENDED)
- `--wait` - Wait for resources to be ready
- `--timeout` - Maximum time to wait (default 5m)
- `--dry-run --debug` - Preview without installing

### Upgrade Existing Release

```bash
# Basic upgrade with new values
helm upgrade myapp ./mychart \
  --namespace production \
  --values values.yaml

# Upgrade with value overrides
helm upgrade myapp bitnami/nginx \
  --namespace prod \
  --reuse-values \
  --set image.tag=1.21.0

# Upgrade with new chart version
helm upgrade mydb bitnami/postgresql \
  --namespace database \
  --version 12.2.0 \
  --atomic \
  --wait

# Install if not exists, upgrade if exists
helm upgrade --install myapp ./chart \
  --namespace staging \
  --create-namespace \
  --values values.yaml

# Force upgrade (recreate resources)
helm upgrade myapp ./chart \
  --namespace prod \
  --force \
  --recreate-pods
```

**Key Flags:**
- `--reuse-values` - Reuse existing values, merge with new
- `--reset-values` - Reset to chart defaults, ignore existing
- `--install` - Install if release doesn't exist
- `--force` - Force resource updates (use cautiously)
- `--recreate-pods` - Recreate pods even if no changes
- `--cleanup-on-fail` - Delete new resources on failed upgrade

**Value Override Precedence** (lowest to highest):
1. Chart default values (`values.yaml` in chart)
2. Previous release values (with `--reuse-values`)
3. Parent chart values
4. User-specified values files (`-f values.yaml`)
5. Individual value overrides (`--set key=value`)

### Uninstall Release

```bash
# Basic uninstall
helm uninstall myapp --namespace production

# Uninstall but keep history (allows rollback)
helm uninstall myapp \
  --namespace staging \
  --keep-history

# Uninstall with timeout
helm uninstall myapp \
  --namespace prod \
  --timeout 10m \
  --wait
```

### List Releases

```bash
# List releases in namespace
helm list --namespace production

# List all releases across all namespaces
helm list --all-namespaces

# List with additional details
helm list \
  --all-namespaces \
  --output yaml \
  --max 50

# List including uninstalled releases
helm list --namespace staging --uninstalled

# Filter releases by name pattern
helm list --filter '^my.*' --namespace prod
```

**Key Flags:**
- `--all-namespaces` / `-A` - List releases across all namespaces
- `--all` - Show all releases including failed
- `--uninstalled` - Show uninstalled releases
- `--failed` - Show only failed releases
- `--pending` - Show pending releases
- `--filter` - Filter by release name (regex)

## Release Information & History

### Check Release Status

```bash
# Get release status
helm status myapp --namespace production

# Show deployed resources
helm status myapp \
  --namespace prod \
  --show-resources
```

### View Release History

```bash
# View revision history
helm history myapp --namespace production

# View detailed history
helm history myapp \
  --namespace prod \
  --output yaml \
  --max 10
```

### Inspect Release

```bash
# Get deployed manifest
helm get manifest myapp --namespace production

# Get deployed values
helm get values myapp --namespace production

# Get all values (including defaults)
helm get values myapp --namespace prod --all

# Get release metadata
helm get metadata myapp --namespace production

# Get release notes
helm get notes myapp --namespace production

# Get everything
helm get all myapp --namespace production
```

For common workflows (deploy new application, update configuration, upgrade chart version, multi-environment deployment), best practices, troubleshooting, and integration with other tools, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List releases (structured) | `helm list -n <ns> -o json` |
| Release history (structured) | `helm history <release> -n <ns> --output json` |
| Release status (structured) | `helm status <release> -n <ns> -o json` |
| Values (structured) | `helm get values <release> -n <ns> -o json` |
| Failed releases | `helm list -n <ns> --failed -o json` |

## Related Skills

- **Helm Debugging** - Troubleshooting failed deployments
- **Helm Values Management** - Advanced values configuration
- **Helm Release Recovery** - Rollback and recovery strategies
- **ArgoCD CLI Login** - GitOps integration with ArgoCD
- **Kubernetes Operations** - Managing deployed resources

## References

- [Helm Install Documentation](https://helm.sh/docs/helm/helm_install/)
- [Helm Upgrade Documentation](https://helm.sh/docs/helm/helm_upgrade/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helm Values Documentation](https://helm.sh/docs/chart_template_guide/values_files/)
