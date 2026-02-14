---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: helm-release-recovery
description: |
  Recover from failed Helm deployments, rollback releases, fix stuck states
  (pending-install, pending-upgrade). Covers helm rollback, release history,
  atomic deployments. Use when user mentions rollback, failed Helm upgrade,
  stuck release, or recovering from Helm deployment failures.
allowed-tools: Bash, Read, Grep, Glob
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

For additional recovery scenarios (partial deployments, corrupted history, failed rollbacks, cascading failures), history management, atomic deployment patterns, recovery best practices, troubleshooting, and CI/CD integration, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Release history (JSON) | `helm history <release> -n <ns> --output json` |
| Release status (JSON) | `helm status <release> -n <ns> -o json` |
| Revision values (JSON) | `helm get values <release> -n <ns> --revision <N> -o json` |
| Pod status (compact) | `kubectl get pods -n <ns> -l app.kubernetes.io/instance=<release> -o wide` |
| Helm secrets (list) | `kubectl get secrets -n <ns> -l owner=helm,name=<release> -o json` |

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
