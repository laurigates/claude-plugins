---
name: helm-release-management
description: |
  Manage Helm releases: install, upgrade, uninstall, list, and inspect releases.
  Covers helm install, helm upgrade, helm list, helm status, release history.
  Use when user mentions deploying Helm charts, upgrading releases, helm install,
  helm upgrade, or managing Kubernetes deployments with Helm.
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

**Key Flags:**
- `--keep-history` - Preserve release history
- `--wait` - Wait for resource deletion
- `--timeout` - Maximum time to wait for deletion

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
helm list \
  --namespace staging \
  --uninstalled

# Filter releases by name pattern
helm list --filter '^my.*' --namespace prod
```

**Key Flags:**
- `--all-namespaces` / `-A` - List releases across all namespaces
- `--all` - Show all releases including failed
- `--uninstalled` - Show uninstalled releases
- `--deployed` - Show only deployed releases (default)
- `--failed` - Show only failed releases
- `--pending` - Show pending releases
- `--filter` - Filter by release name (regex)
- `--max` - Maximum number of releases (default 256)

## Release Information & History

### Check Release Status

```bash
# Get release status
helm status myapp --namespace production

# Show deployed resources
helm status myapp \
  --namespace prod \
  --show-resources

# Show release notes
helm status myapp \
  --namespace prod \
  --show-desc
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
helm get values myapp \
  --namespace prod \
  --all

# Get release metadata
helm get metadata myapp --namespace production

# Get release notes
helm get notes myapp --namespace production

# Get release hooks
helm get hooks myapp --namespace production

# Get everything
helm get all myapp --namespace production
```

## Common Workflows

### Workflow 1: Deploy New Application

```bash
# 1. Add chart repository (if needed)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 2. Search for chart
helm search repo nginx

# 3. View default values
helm show values bitnami/nginx > default-values.yaml

# 4. Create custom values file
cat > my-values.yaml <<EOF
replicaCount: 3
service:
  type: LoadBalancer
ingress:
  enabled: true
  hostname: myapp.example.com
EOF

# 5. Dry-run to validate
helm install myapp bitnami/nginx \
  --namespace production \
  --create-namespace \
  --values my-values.yaml \
  --dry-run --debug

# 6. Install with atomic rollback
helm install myapp bitnami/nginx \
  --namespace production \
  --create-namespace \
  --values my-values.yaml \
  --atomic \
  --wait \
  --timeout 5m

# 7. Verify deployment
helm status myapp --namespace production
kubectl get pods -n production -l app.kubernetes.io/instance=myapp
```

### Workflow 2: Update Configuration

```bash
# 1. Check current values
helm get values myapp --namespace production > current-values.yaml

# 2. Edit values
vim current-values.yaml
# (change replicaCount: 3 → 5)

# 3. Upgrade with new values
helm upgrade myapp bitnami/nginx \
  --namespace production \
  --values current-values.yaml \
  --atomic \
  --wait

# 4. Verify upgrade
helm history myapp --namespace production
helm status myapp --namespace production
```

### Workflow 3: Upgrade Chart Version

```bash
# 1. Check available versions
helm search repo bitnami/nginx --versions | head -10

# 2. Review changelog for breaking changes
helm show readme bitnami/nginx --version 15.0.0

# 3. Compare values schemas
helm show values bitnami/nginx --version 15.0.0 > new-values.yaml
diff <(helm get values myapp -n prod --all) new-values.yaml

# 4. Upgrade to new version
helm upgrade myapp bitnami/nginx \
  --namespace production \
  --version 15.0.0 \
  --reuse-values \
  --atomic \
  --wait

# 5. Monitor upgrade
watch kubectl get pods -n production

# 6. Verify new version
helm list --namespace production
```

### Workflow 4: Multi-Environment Deployment

```bash
# Directory structure:
# charts/myapp/
# values/
#   ├── common.yaml        # Shared values
#   ├── dev.yaml          # Dev overrides
#   ├── staging.yaml      # Staging overrides
#   └── production.yaml   # Production overrides

# Deploy to dev
helm upgrade --install myapp ./charts/myapp \
  --namespace dev \
  --create-namespace \
  -f values/common.yaml \
  -f values/dev.yaml

# Deploy to staging
helm upgrade --install myapp ./charts/myapp \
  --namespace staging \
  --create-namespace \
  -f values/common.yaml \
  -f values/staging.yaml

# Deploy to production (with approval gate)
helm upgrade --install myapp ./charts/myapp \
  --namespace production \
  --create-namespace \
  -f values/common.yaml \
  -f values/production.yaml \
  --atomic \
  --wait \
  --timeout 10m
```

## Best Practices

### Namespace Management
✅ **DO**: Always specify `--namespace` explicitly
```bash
helm install myapp ./chart --namespace production
```

❌ **DON'T**: Rely on current kubectl context
```bash
helm install myapp ./chart  # Namespace may be unexpected
```

### Atomic Deployments
✅ **DO**: Use `--atomic` for production deployments
```bash
helm upgrade myapp ./chart --namespace prod --atomic --wait
```

**Why**: Automatically rolls back on failure, prevents partial deployments

### Value Management
✅ **DO**: Use multiple values files for layering
```bash
helm install myapp ./chart \
  -f values/base.yaml \
  -f values/production.yaml \
  -f values/secrets.yaml
```

✅ **DO**: Prefer `--values` over many `--set` flags
```bash
# Good: values.yaml
helm install myapp ./chart -f values.yaml

# Prefer: values.yaml over many --set flags
helm install myapp ./chart --set a=1 --set b=2 --set c=3
```

### Version Pinning
✅ **DO**: Pin chart versions in production
```bash
helm install myapp bitnami/nginx --version 15.0.2 --namespace prod
```

❌ **DON'T**: Use floating versions in production
```bash
helm install myapp bitnami/nginx --namespace prod  # Uses latest
```

### Pre-Deployment Validation
✅ **DO**: Always dry-run before installing/upgrading
```bash
# 1. Lint (if local chart)
helm lint ./mychart

# 2. Template to see rendered manifests
helm template myapp ./mychart -f values.yaml

# 3. Dry-run with debug
helm install myapp ./mychart \
  --namespace prod \
  -f values.yaml \
  --dry-run --debug

# 4. Actual install
helm install myapp ./mychart \
  --namespace prod \
  -f values.yaml \
  --atomic --wait
```

### History Management
✅ **DO**: Limit revision history
```bash
helm upgrade myapp ./chart \
  --namespace prod \
  --history-max 10  # Keep only last 10 revisions
```

### Resource Waiting
✅ **DO**: Use `--wait` for critical deployments
```bash
helm upgrade myapp ./chart \
  --namespace prod \
  --wait \
  --timeout 5m  # Fail if not ready in 5 minutes
```

### Release Naming
✅ **DO**: Use consistent, descriptive release names
```bash
# Good: environment-specific
helm install myapp-prod ./chart --namespace production
helm install myapp-staging ./chart --namespace staging

# Or: same name, different namespaces
helm install myapp ./chart --namespace production
helm install myapp ./chart --namespace staging
```

## Troubleshooting Common Issues

### Issue: "Release already exists"
```bash
# Check if release exists
helm list --all-namespaces | grep myapp

# If in different namespace, specify correct namespace
helm upgrade myapp ./chart --namespace <correct-namespace>

# If stuck in failed state, uninstall and reinstall
helm uninstall myapp --namespace <namespace>
helm install myapp ./chart --namespace <namespace>
```

### Issue: Upgrade hangs or times out
```bash
# Increase timeout
helm upgrade myapp ./chart \
  --namespace prod \
  --wait \
  --timeout 15m

# Check pod status manually
kubectl get pods -n prod -l app.kubernetes.io/instance=myapp
kubectl describe pod <pod-name> -n prod

# If stuck, consider force upgrade
helm upgrade myapp ./chart \
  --namespace prod \
  --force \
  --cleanup-on-fail
```

### Issue: Can't find release
```bash
# Search all namespaces
helm list --all-namespaces | grep myapp

# Check uninstalled releases
helm list --namespace <namespace> --uninstalled

# Check failed releases
helm list --namespace <namespace> --failed
```

### Issue: Wrong values applied
```bash
# Check what values were used
helm get values myapp --namespace prod --all

# Compare with expected values
diff <(helm get values myapp -n prod --all) values.yaml

# Upgrade with correct values
helm upgrade myapp ./chart \
  --namespace prod \
  --reset-values \  # Reset to chart defaults first
  -f correct-values.yaml
```

## Integration with Other Tools

### ArgoCD Integration
When using ArgoCD for GitOps:
- ArgoCD manages Helm releases via Application CRDs
- Use ArgoCD UI/CLI for sync operations instead of `helm upgrade`
- Can still use `helm template` locally for testing
- Use `helm get values/manifest` to inspect deployed resources

### CI/CD Integration
```yaml
# GitHub Actions example
- name: Deploy with Helm
  run: |
    helm upgrade --install myapp ./charts/myapp \
      --namespace ${{ env.NAMESPACE }} \
      --create-namespace \
      -f values/common.yaml \
      -f values/${{ env.ENVIRONMENT }}.yaml \
      --atomic \
      --wait \
      --timeout 10m
```

### Kubernetes Context
Always ensure correct context:
```bash
# Check current context
kubectl config current-context

# Switch context if needed
kubectl config use-context <context-name>

# Or specify kubeconfig
helm install myapp ./chart \
  --kubeconfig=/path/to/kubeconfig \
  --namespace prod
```

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
