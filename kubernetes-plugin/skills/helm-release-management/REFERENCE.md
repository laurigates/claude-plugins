# Helm Release Management - Reference

Detailed reference material for Helm release management.

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
# (change replicaCount: 3 -> 5)

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
Always specify `--namespace` explicitly:
```bash
helm install myapp ./chart --namespace production
```

### Atomic Deployments
Use `--atomic` for production deployments:
```bash
helm upgrade myapp ./chart --namespace prod --atomic --wait
```
Automatically rolls back on failure, prevents partial deployments.

### Value Management
Use multiple values files for layering:
```bash
helm install myapp ./chart \
  -f values/base.yaml \
  -f values/production.yaml \
  -f values/secrets.yaml
```

Prefer `--values` over many `--set` flags:
```bash
# Prefer: values.yaml
helm install myapp ./chart -f values.yaml

# Avoid: many --set flags
helm install myapp ./chart --set a=1 --set b=2 --set c=3
```

### Version Pinning
Pin chart versions in production:
```bash
helm install myapp bitnami/nginx --version 15.0.2 --namespace prod
```

### Pre-Deployment Validation
Always dry-run before installing/upgrading:
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
Limit revision history:
```bash
helm upgrade myapp ./chart \
  --namespace prod \
  --history-max 10  # Keep only last 10 revisions
```

### Resource Waiting
Use `--wait` for critical deployments:
```bash
helm upgrade myapp ./chart \
  --namespace prod \
  --wait \
  --timeout 5m  # Fail if not ready in 5 minutes
```

### Release Naming
Use consistent, descriptive release names:
```bash
# Environment-specific
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
  --reset-values \
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
