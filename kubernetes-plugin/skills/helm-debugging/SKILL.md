---
model: haiku
created: 2025-12-16
modified: 2026-02-06
reviewed: 2025-12-16
name: helm-debugging
description: |
  Debug and troubleshoot Helm deployment failures, template errors, and configuration
  issues. Covers helm template, helm lint, dry-run, debugging YAML parse errors,
  value type errors, and resource conflicts. Use when user mentions Helm errors,
  debugging Helm, template rendering issues, or troubleshooting Helm deployments.
allowed-tools: Bash, Read, Grep, Glob
---

# Helm Debugging & Troubleshooting

Comprehensive guidance for diagnosing and fixing Helm deployment failures, template errors, and configuration issues.

## When to Use

Use this skill automatically when:
- User reports Helm deployment failures or errors
- User mentions debugging, troubleshooting, or fixing Helm issues
- Template rendering problems occur
- Value validation or type errors
- Resource conflicts or API errors
- Image pull failures or pod crashes
- User needs to inspect deployed resources

## Context Safety (CRITICAL)

**Always specify `--context`** explicitly in all kubectl and helm commands. Never rely on the current context.

```bash
# CORRECT: Explicit context
kubectl --context=prod-cluster get pods -n prod
helm --kube-context=prod-cluster status myapp -n prod

# WRONG: Relying on current context
kubectl get pods -n prod  # Which cluster?
```

This prevents accidental operations on the wrong cluster.

---

## Layered Validation Approach

**ALWAYS follow this progression** for robust deployments:

```bash
# 1. LINT - Static analysis (local charts only)
helm lint ./mychart --strict

# 2. TEMPLATE - Render templates locally
helm template myapp ./mychart \
  --debug \
  --values values.yaml

# 3. DRY-RUN - Server-side validation
helm install myapp ./mychart \
  --namespace prod \
  --values values.yaml \
  --dry-run --debug

# 4. INSTALL - Actual deployment
helm install myapp ./mychart \
  --namespace prod \
  --values values.yaml \
  --atomic --wait

# 5. TEST - Post-deployment validation (if chart has tests)
helm test myapp --namespace prod --logs
```

## Core Debugging Commands

### Template Rendering & Inspection

```bash
# Render all templates locally
helm template myapp ./mychart \
  --debug \
  --values values.yaml

# Render specific template file
helm template myapp ./mychart \
  --show-only templates/deployment.yaml \
  --values values.yaml

# Render with debug output (shows computed values)
helm template myapp ./mychart \
  --debug \
  --values values.yaml \
  2>&1 | less

# Validate against Kubernetes API (dry-run)
helm install myapp ./mychart \
  --namespace prod \
  --values values.yaml \
  --dry-run \
  --debug
```

### Inspect Deployed Resources

```bash
# Get deployed manifest (actual YAML in cluster)
helm get manifest myapp --namespace prod

# Get deployed values (what was actually used)
helm get values myapp --namespace prod

# Get ALL values (including defaults)
helm get values myapp --namespace prod --all

# Get release status with resources
helm status myapp --namespace prod --show-resources

# Get everything about a release
helm get all myapp --namespace prod
```

### Chart Validation

```bash
# Lint chart structure and templates
helm lint ./mychart

# Lint with strict mode (treats warnings as errors)
helm lint ./mychart --strict

# Lint with specific values
helm lint ./mychart --values values.yaml --strict

# Validate chart against Kubernetes API
helm install myapp ./mychart \
  --dry-run --validate --namespace prod
```

### Verbose Debugging

```bash
# Enable Helm debug logging
helm install myapp ./mychart \
  --namespace prod \
  --debug \
  --dry-run

# Enable Kubernetes client logging
helm install myapp ./mychart \
  --namespace prod \
  --v=6  # Verbosity level 0-9
```

## Common Failure Scenarios

| Scenario | Symptom | Quick Fix |
|----------|---------|-----------|
| YAML parse error | `error converting YAML to JSON` | Check indentation, use `{{- ... }}` for whitespace chomping |
| Template rendering error | `nil pointer evaluating interface` | Add defaults: `{{ .Values.key \| default "value" }}` |
| Value type error | `cannot unmarshal string into Go value of type int` | Use `{{ .Values.port \| int }}` in template |
| Resource already exists | `resource that already exists` | `helm uninstall` conflicting release or adopt resource |
| Image pull failure | `ImagePullBackOff` | Fix image name/tag, create pull secret |
| CRD not found | `no matches for kind` | Install CRDs first: `kubectl apply -f crds/` |
| Timeout | `timed out waiting for the condition` | Increase `--timeout`, check readiness probes |
| Hook failure | `pre-upgrade hooks failed` | Delete failed hook job, retry with `--no-hooks` |

For detailed debugging steps, fixes, and examples for each failure scenario, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Release status (JSON) | `helm status <release> -n <ns> -o json` |
| All values (JSON) | `helm get values <release> -n <ns> --all -o json` |
| Pod status (compact) | `kubectl get pods -n <ns> -l app.kubernetes.io/instance=<release> -o wide` |
| Events (sorted) | `kubectl get events -n <ns> --sort-by='.lastTimestamp' -o json` |
| Render + validate | `helm template <release> ./chart --debug 2>&1 \| head -100` |

## Related Skills

- **Helm Release Management** - Install, upgrade, uninstall operations
- **Helm Values Management** - Advanced configuration management
- **Helm Release Recovery** - Rollback and recovery strategies
- **Kubernetes Operations** - Managing and debugging K8s resources
- **ArgoCD CLI Login** - GitOps debugging with ArgoCD

## References

- [Helm Debugging Documentation](https://helm.sh/docs/chart_template_guide/debugging/)
- [Helm Troubleshooting Guide](https://helm.sh/docs/faq/troubleshooting/)
- [Kubernetes Debugging](https://kubernetes.io/docs/tasks/debug/)
- [Template Function Reference](https://helm.sh/docs/chart_template_guide/function_list/)
