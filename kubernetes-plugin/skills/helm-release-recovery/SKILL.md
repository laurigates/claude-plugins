---
name: helm-release-recovery
description: |
  Recover from failed Helm deployments, rollback releases, fix stuck states
  (pending-install, pending-upgrade). Covers helm rollback, release history,
  atomic deployments. Use when user mentions rollback, failed Helm upgrade,
  stuck release, or recovering from Helm deployment failures.
---

# Helm Release Recovery

Comprehensive guidance for recovering from failed Helm deployments, rolling back releases, and managing stuck or corrupted release states.

## When to Use

Use this skill automatically when:
- User needs to rollback a failed or problematic deployment
- User reports stuck releases (pending-install, pending-upgrade)
- User mentions failed upgrades or partial deployments
- User needs to recover from corrupted release state
- User wants to view release history
- User needs to clean up failed releases

## Core Recovery Operations

### Rollback to Previous Revision

```bash
# Rollback to previous revision (most recent successful)
helm rollback <release> --namespace <namespace>

# Rollback to specific revision number
helm rollback <release> 3 --namespace <namespace>

# Rollback with wait and atomic behavior
helm rollback <release> \
  --namespace <namespace> \
  --wait \
  --timeout 5m \
  --cleanup-on-fail

# Rollback without waiting (faster but less safe)
helm rollback <release> \
  --namespace <namespace> \
  --no-hooks
```

**Key Flags:**
- `--wait` - Wait for resources to be ready
- `--timeout` - Maximum time to wait (default 5m)
- `--cleanup-on-fail` - Delete new resources on failed rollback
- `--no-hooks` - Skip running rollback hooks
- `--force` - Force resource updates through deletion/recreation
- `--recreate-pods` - Perform pods restart for the resource if applicable

### View Release History

```bash
# View all revisions
helm history <release> --namespace <namespace>

# View detailed history (YAML format)
helm history <release> \
  --namespace <namespace> \
  --output yaml

# Limit number of revisions shown
helm history <release> \
  --namespace <namespace> \
  --max 10
```

**History Output Fields:**
- REVISION: Sequential version number
- UPDATED: Timestamp of deployment
- STATUS: deployed, superseded, failed, pending-install, pending-upgrade
- CHART: Chart name and version
- APP VERSION: Application version
- DESCRIPTION: What happened (Install complete, Upgrade complete, Rollback to X)

### Check Release Status

```bash
# Check current release status
helm status <release> --namespace <namespace>

# Show deployed resources
helm status <release> \
  --namespace <namespace> \
  --show-resources

# Get status of specific revision
helm status <release> \
  --namespace <namespace> \
  --revision 5
```

## Common Recovery Scenarios

### Scenario 1: Recent Deploy Failed - Simple Rollback

**Symptoms:**
- Recent upgrade/install failed
- Application not working after deployment
- Want to restore previous working version

**Recovery Steps:**

```bash
# 1. Check release status
helm status myapp --namespace production

# 2. View history to identify good revision
helm history myapp --namespace production

# Output example:
# REVISION  STATUS      CHART        DESCRIPTION
# 1         superseded  myapp-1.0.0  Install complete
# 2         superseded  myapp-1.1.0  Upgrade complete
# 3         deployed    myapp-1.2.0  Upgrade "myapp" failed

# 3. Rollback to previous working revision (2)
helm rollback myapp 2 \
  --namespace production \
  --wait \
  --timeout 5m

# 4. Verify rollback
helm history myapp --namespace production
# REVISION  STATUS      CHART        DESCRIPTION
# ...
# 4         deployed    myapp-1.1.0  Rollback to 2

# 5. Verify application health
kubectl get pods -n production -l app.kubernetes.io/instance=myapp
helm status myapp --namespace production
```

### Scenario 2: Stuck Release (pending-install/pending-upgrade)

**Symptoms:**
```bash
helm list -n production
# NAME   STATUS          CHART
# myapp  pending-upgrade myapp-1.0.0
```

**Causes:**
- Installation/upgrade process interrupted
- Timeout during deployment
- Kubernetes API issues
- Network issues during deployment

**Recovery Steps:**

```bash
# 1. Check what's actually deployed
kubectl get all -n production -l app.kubernetes.io/instance=myapp

# 2. Check release history
helm history myapp --namespace production

# Option A: Rollback to previous working revision
helm rollback myapp <previous-working-revision> \
  --namespace production \
  --wait

# Option B: Force new upgrade to unstick
helm upgrade myapp ./chart \
  --namespace production \
  --force \
  --wait \
  --atomic

# Option C: If rollback fails, delete and reinstall
# WARNING: This will cause downtime
helm uninstall myapp --namespace production --keep-history
helm install myapp ./chart --namespace production --atomic

# 3. Verify recovery
helm status myapp --namespace production
```

### Scenario 3: Failed Upgrade - Partial Deployment

**Symptoms:**
- Some resources updated, others not
- Mixed old/new versions running
- Application in inconsistent state

**Recovery Steps:**

```bash
# 1. Assess current state
helm status myapp --namespace production --show-resources
kubectl get pods -n production -l app.kubernetes.io/instance=myapp

# 2. Check recent history
helm history myapp --namespace production

# 3. Identify last successful revision
# Look for STATUS=deployed (not superseded or failed)

# 4. Rollback with force to ensure consistency
helm rollback myapp <good-revision> \
  --namespace production \
  --force \
  --recreate-pods \
  --wait \
  --timeout 10m

# 5. If rollback fails, try cleanup and retry
kubectl delete pod -n production -l app.kubernetes.io/instance=myapp --grace-period=0 --force
helm rollback myapp <good-revision> \
  --namespace production \
  --force \
  --wait

# 6. Verify all pods are consistent
kubectl get pods -n production -l app.kubernetes.io/instance=myapp -o wide
```

### Scenario 4: Can't Rollback - "No Revision for Release"

**Symptoms:**
```
Error: no revision for release "myapp"
```

**Causes:**
- Release history corrupted or deleted
- Helm storage backend issues
- Namespace issues

**Recovery Steps:**

```bash
# 1. Check if release actually exists
helm list --all-namespaces | grep myapp

# 2. Check for secrets (Helm storage)
kubectl get secrets -n production -l owner=helm,name=myapp

# 3. If secrets exist, check their data
kubectl get secret sh.helm.release.v1.myapp.v1 -n production -o yaml

# Option A: Uninstall and reinstall (data loss risk)
helm uninstall myapp --namespace production
helm install myapp ./chart --namespace production

# Option B: Adopt existing resources (advanced)
# Manually annotate resources to be managed by new Helm release
kubectl annotate <resource-type> <name> \
  meta.helm.sh/release-name=myapp \
  meta.helm.sh/release-namespace=production \
  -n production
kubectl label <resource-type> <name> \
  app.kubernetes.io/managed-by=Helm \
  -n production

# Then install new release
helm install myapp ./chart --namespace production
```

### Scenario 5: Rollback Itself Failed

**Symptoms:**
```
Error: UPGRADE FAILED: <reason>
```

**Recovery Steps:**

```bash
# 1. Check current state
helm status myapp --namespace production
kubectl get all -n production -l app.kubernetes.io/instance=myapp

# 2. Try rollback with different flags
# Option A: Rollback without hooks
helm rollback myapp <revision> \
  --namespace production \
  --no-hooks \
  --wait

# Option B: Rollback with force recreation
helm rollback myapp <revision> \
  --namespace production \
  --force \
  --recreate-pods \
  --cleanup-on-fail

# Option C: Manual resource cleanup then rollback
kubectl delete pod -n production -l app.kubernetes.io/instance=myapp --force --grace-period=0
kubectl delete job -n production -l app.kubernetes.io/instance=myapp
helm rollback myapp <revision> --namespace production --wait

# Option D: Nuclear option - uninstall and reinstall
# Get current values first
helm get values myapp -n production --all > backup-values.yaml

# Uninstall
helm uninstall myapp --namespace production

# Reinstall with backed up values
helm install myapp ./chart \
  --namespace production \
  -f backup-values.yaml \
  --atomic --wait
```

### Scenario 6: Cascading Failures Across Environments

**Symptoms:**
- Bad deploy rolled out to multiple environments
- Need to rollback dev, staging, and prod

**Recovery Workflow:**

```bash
# 1. Identify last known good revision (check one environment)
helm history myapp --namespace production

# 2. Stop any ongoing deployments
# Cancel CI/CD pipelines, ArgoCD syncs, etc.

# 3. Rollback in reverse order (prod → staging → dev)
# Production (highest priority)
helm rollback myapp <good-revision> \
  --namespace production \
  --wait \
  --timeout 10m

# Verify prod is stable
kubectl get pods -n production -l app.kubernetes.io/instance=myapp
# Run smoke tests

# Staging
helm rollback myapp <good-revision> \
  --namespace staging \
  --wait

# Dev (lowest priority, optional)
helm rollback myapp <good-revision> \
  --namespace dev

# 4. Update deployment configs to prevent re-deploy
# Pin version in values files
# Update ArgoCD target revision
# Tag git commit as known-good

# 5. Post-mortem
# Document what went wrong
# Update CI/CD to prevent similar issues
```

## History Management

### Limit Revision History

```bash
# Set max revisions during upgrade/install
helm upgrade myapp ./chart \
  --namespace production \
  --history-max 10  # Keep only last 10 revisions

# Default is 10 revisions
# Set to 0 for unlimited (not recommended)
```

### Clean Up Old Revisions

```bash
# Revisions are automatically pruned based on --history-max

# Manual cleanup (advanced):
# Find old Helm secrets
kubectl get secrets -n production \
  -l owner=helm,name=myapp \
  --sort-by=.metadata.creationTimestamp

# Delete specific revision secret (DANGEROUS)
kubectl delete secret sh.helm.release.v1.myapp.v1 -n production
```

### Preserve History on Uninstall

```bash
# Keep history after uninstall (allows rollback)
helm uninstall myapp \
  --namespace production \
  --keep-history

# List uninstalled releases
helm list --namespace production --uninstalled

# Rollback uninstalled release (recreates it)
helm rollback myapp <revision> --namespace production
```

## Atomic Deployments (Prevention)

### Use Atomic Flag

```bash
# Automatically rollback on failure
helm upgrade myapp ./chart \
  --namespace production \
  --atomic \
  --wait \
  --timeout 5m

# Equivalent to:
# 1. Upgrade
# 2. If fails, automatically: helm rollback myapp
```

**When Atomic Helps:**
- Prevents partial deployments
- Automatic recovery from failed upgrades
- No manual intervention needed
- Maintains release in known-good state

**Atomic Behavior:**
- On success: Release marked as deployed
- On failure: Automatic rollback to previous revision
- On timeout: Automatic rollback
- Cleanup: Failed resources deleted with `--cleanup-on-fail`

### Atomic Best Practices

✅ **DO**: Use atomic for production deployments
```bash
helm upgrade myapp ./chart -n prod --atomic --wait --timeout 10m
```

✅ **DO**: Set appropriate timeout for your application
```bash
# Large database: longer timeout
helm upgrade db ./chart -n prod --atomic --wait --timeout 30m

# Simple API: shorter timeout
helm upgrade api ./chart -n prod --atomic --wait --timeout 5m
```

❌ **DON'T**: Use atomic for debugging (harder to inspect failures)
```bash
# For debugging, use dry-run instead
helm upgrade myapp ./chart -n dev --dry-run --debug
```

## Recovery Best Practices

### Pre-Upgrade Backup

✅ **DO**: Capture state before upgrades
```bash
# Before upgrade
helm get values myapp -n prod --all > backup-values.yaml
helm get manifest myapp -n prod > backup-manifest.yaml
kubectl get all -n prod -l app.kubernetes.io/instance=myapp -o yaml > backup-resources.yaml

# Upgrade
helm upgrade myapp ./chart -n prod --atomic

# If needed, restore from backups
```

### Progressive Rollout

✅ **DO**: Deploy to lower environments first
```bash
# 1. Dev
helm upgrade myapp ./chart -n dev --atomic
# Test thoroughly

# 2. Staging
helm upgrade myapp ./chart -n staging --atomic
# More testing

# 3. Production (with caution)
helm upgrade myapp ./chart -n prod --atomic --timeout 10m
```

### Monitor During Deployment

✅ **DO**: Watch deployment progress
```bash
# Terminal 1: Upgrade
helm upgrade myapp ./chart -n prod --atomic --wait --timeout 10m

# Terminal 2: Watch pods
watch -n 2 kubectl get pods -n prod -l app.kubernetes.io/instance=myapp

# Terminal 3: Watch events
kubectl get events -n prod --watch --field-selector involvedObject.kind=Pod

# Terminal 4: Application logs
stern -n prod myapp
```

### Test Rollback Procedures

✅ **DO**: Practice rollback in non-prod
```bash
# In dev/staging:
# 1. Deploy known-good version
helm upgrade myapp ./chart -n dev --atomic

# 2. Deploy bad version intentionally
helm upgrade myapp ./bad-chart -n dev --set breakApp=true

# 3. Practice rollback
helm rollback myapp -n dev --wait

# 4. Verify recovery
helm status myapp -n dev
```

### Document Known-Good Revisions

✅ **DO**: Tag stable releases
```bash
# After successful deploy and verification
helm history myapp -n prod

# Document revision in runbook:
# "Last known good: Revision 5 (v1.2.3) deployed 2025-01-15"

# Use git tags for chart versions
git tag -a v1.2.3 -m "Stable release, Helm revision 5 in prod"
```

## Troubleshooting Recovery Issues

### Issue: Rollback Hangs

```bash
# Increase timeout
helm rollback myapp <revision> -n prod --wait --timeout 15m

# Skip waiting
helm rollback myapp <revision> -n prod --no-hooks

# Force recreation
helm rollback myapp <revision> -n prod --force --recreate-pods
```

### Issue: Resources Not Reverting

```bash
# Check what's actually deployed
helm get manifest myapp -n prod | kubectl diff -f -

# Force delete stuck resources
kubectl delete pod <pod> -n prod --force --grace-period=0

# Then retry rollback
helm rollback myapp <revision> -n prod --force
```

### Issue: Hook Failures Blocking Rollback

```bash
# Check hook status
kubectl get jobs -n prod -l helm.sh/hook
kubectl get pods -n prod -l helm.sh/hook

# Delete failed hooks
kubectl delete job <hook-job> -n prod

# Rollback without hooks
helm rollback myapp <revision> -n prod --no-hooks
```

### Issue: Can't Determine Good Revision

```bash
# List all revisions with details
helm history myapp -n prod --output yaml

# Check each revision's values
helm get values myapp -n prod --revision 1
helm get values myapp -n prod --revision 2
helm get values myapp -n prod --revision 3

# Check manifest differences
diff \
  <(helm get manifest myapp -n prod --revision 2) \
  <(helm get manifest myapp -n prod --revision 3)

# Check git history for chart changes
git log --oneline charts/myapp/
```

## Integration with CI/CD

### Automated Rollback on Failure

```yaml
# GitHub Actions example
- name: Deploy to Production
  id: deploy
  run: |
    helm upgrade myapp ./chart \
      --namespace production \
      --atomic \
      --wait \
      --timeout 10m
  continue-on-error: true

- name: Verify Deployment
  id: verify
  if: steps.deploy.outcome == 'success'
  run: |
    # Run smoke tests
    ./scripts/smoke-tests.sh production

- name: Rollback on Test Failure
  if: steps.verify.outcome == 'failure'
  run: |
    echo "Smoke tests failed, rolling back"
    helm rollback myapp --namespace production --wait
```

### ArgoCD Auto-Sync with Rollback

```yaml
# ArgoCD Application with auto-rollback
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
spec:
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

## Related Skills

- **Helm Release Management** - Install, upgrade operations
- **Helm Debugging** - Troubleshooting deployment failures
- **Helm Values Management** - Managing configuration
- **Kubernetes Operations** - Managing deployed resources

## References

- [Helm Rollback Documentation](https://helm.sh/docs/helm/helm_rollback/)
- [Helm Release Management](https://helm.sh/docs/topics/advanced/#managing-a-release)
- [Helm History Documentation](https://helm.sh/docs/helm/helm_history/)
- [Helm Storage Backends](https://helm.sh/docs/topics/advanced/#storage-backends)
