---
name: helm-debugging
description: |
  Debug and troubleshoot Helm deployment failures, template errors, and configuration
  issues. Covers helm template, helm lint, dry-run, debugging YAML parse errors,
  value type errors, and resource conflicts. Use when user mentions Helm errors,
  debugging Helm, template rendering issues, or troubleshooting Helm deployments.
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

# Get release metadata
helm get metadata myapp --namespace prod

# Get release hooks
helm get hooks myapp --namespace prod

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
  --dry-run \
  --validate \
  --namespace prod
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

# Combine debug and verbose
helm upgrade myapp ./mychart \
  --namespace prod \
  --debug \
  --v=6 \
  --wait
```

## Common Failure Scenarios

### 1. YAML Parse Errors

**Symptom:**
```
Error: YAML parse error on <file>: error converting YAML to JSON
```

**Causes:**
- Template whitespace issues (extra spaces, tabs mixed with spaces)
- Incorrect indentation
- Malformed YAML syntax
- Template rendering issues

**Debugging Steps:**

```bash
# 1. Render template locally to see output
helm template myapp ./mychart --debug 2>&1 | grep -A 10 "error"

# 2. Render specific problematic template
helm template myapp ./mychart \
  --show-only templates/deployment.yaml \
  --debug

# 3. Check for whitespace issues
helm template myapp ./mychart | cat -A  # Shows tabs/spaces

# 4. Validate YAML syntax
helm template myapp ./mychart | yq eval '.' -
```

**Common Fixes:**

```yaml
# ❌ WRONG: Inconsistent whitespace
spec:
  containers:
  - name: {{ .Values.name }}
      image: {{ .Values.image }}  # Too much indent

# ✅ CORRECT: Consistent 2-space indent
spec:
  containers:
  - name: {{ .Values.name }}
    image: {{ .Values.image }}

# ❌ WRONG: Missing whitespace chomping
labels:
{{ toYaml .Values.labels }}  # Adds extra newlines

# ✅ CORRECT: Chomp whitespace
labels:
{{- toYaml .Values.labels | nindent 2 }}

# ❌ WRONG: Conditional creates empty lines
{{- if .Values.enabled }}
enabled: true
{{- end }}

# ✅ CORRECT: Chomp trailing whitespace
{{- if .Values.enabled }}
enabled: true
{{- end -}}
```

### 2. Template Rendering Errors

**Symptom:**
```
Error: template: mychart/templates/deployment.yaml:15:8: executing "mychart/templates/deployment.yaml" at <.Values.foo>: nil pointer evaluating interface {}.foo
```

**Causes:**
- Accessing undefined values
- Incorrect value path
- Missing required values
- Type mismatches

**Debugging Steps:**

```bash
# 1. Check what values are available
helm show values ./mychart

# 2. Verify values being passed
helm template myapp ./mychart \
  --debug \
  --values values.yaml \
  2>&1 | grep "COMPUTED VALUES"

# 3. Test with minimal values
helm template myapp ./mychart \
  --set foo=test \
  --debug
```

**Common Fixes:**

```yaml
# ❌ WRONG: No default or check
image: {{ .Values.image.tag }}  # Fails if .Values.image is nil

# ✅ CORRECT: Use default
image: {{ .Values.image.tag | default "latest" }}

# ✅ CORRECT: Check before accessing
{{- if .Values.image }}
image: {{ .Values.image.tag | default "latest" }}
{{- end }}

# ✅ CORRECT: Use required for mandatory values
image: {{ required "image.repository is required" .Values.image.repository }}

# ❌ WRONG: Assuming type
replicas: {{ .Values.replicaCount }}  # May be string "3"

# ✅ CORRECT: Ensure int type
replicas: {{ .Values.replicaCount | int }}
```

### 3. Value Type Errors

**Symptom:**
```
Error: json: cannot unmarshal string into Go value of type int
```

**Causes:**
- String passed where number expected
- Boolean as string
- Incorrect YAML parsing

**Debugging Steps:**

```bash
# 1. Check value types in rendered output
helm template myapp ./mychart --debug | grep -A 5 "replicaCount"

# 2. Verify values file syntax
yq eval '.replicaCount' values.yaml

# 3. Test with explicit type conversion
helm template myapp ./mychart --set-string name="value"
```

**Common Fixes:**

```yaml
# ❌ WRONG: String in values.yaml
replicaCount: "3"  # String

# ✅ CORRECT: Number in values.yaml
replicaCount: 3  # Int

# Template: Always convert to correct type
replicas: {{ .Values.replicaCount | int }}
port: {{ .Values.service.port | int }}
enabled: {{ .Values.feature.enabled | ternary "true" "false" }}

# Use --set-string for forcing strings
helm install myapp ./chart --set-string version="1.0"
```

### 4. Resource Already Exists

**Symptom:**
```
Error: rendered manifests contain a resource that already exists
```

**Causes:**
- Resource from previous failed install
- Resource managed by another release
- Manual resource creation conflict

**Debugging Steps:**

```bash
# 1. Check if resource exists
kubectl get <resource-type> <name> -n <namespace>

# 2. Check resource ownership
kubectl get <resource-type> <name> -n <namespace> -o yaml | grep -A 5 "labels:"

# 3. Check which Helm release owns it
helm list --all-namespaces | grep <resource-name>

# 4. Check for stuck releases
helm list --all-namespaces --failed
helm list --all-namespaces --pending
```

**Solutions:**

```bash
# Option 1: Uninstall conflicting release
helm uninstall <release> --namespace <namespace>

# Option 2: Delete specific resource manually
kubectl delete <resource-type> <name> -n <namespace>

# Option 3: Use different release name
helm install myapp-v2 ./chart --namespace prod

# Option 4: Adopt existing resources (advanced)
kubectl annotate <resource-type> <name> \
  meta.helm.sh/release-name=<release> \
  meta.helm.sh/release-namespace=<namespace> \
  -n <namespace>
kubectl label <resource-type> <name> \
  app.kubernetes.io/managed-by=Helm \
  -n <namespace>
```

### 5. Image Pull Failures

**Symptom:**
```
Pod status: ImagePullBackOff or ErrImagePull
```

**Causes:**
- Wrong image name/tag
- Missing registry credentials
- Private registry authentication
- Network/registry issues

**Debugging Steps:**

```bash
# 1. Check pod events
kubectl describe pod <pod-name> -n <namespace>

# 2. Verify image in manifest
helm get manifest myapp -n prod | grep "image:"

# 3. Check image pull secrets
kubectl get secrets -n <namespace>
kubectl get sa default -n <namespace> -o yaml | grep imagePullSecrets

# 4. Test image pull manually
docker pull <image:tag>
```

**Solutions:**

```bash
# Option 1: Fix image name/tag in values
helm upgrade myapp ./chart \
  --namespace prod \
  --set image.repository=myregistry.io/myapp \
  --set image.tag=v1.0.0

# Option 2: Create image pull secret
kubectl create secret docker-registry regcred \
  --docker-server=<registry> \
  --docker-username=<user> \
  --docker-password=<pass> \
  --namespace <namespace>

# Reference in values.yaml:
imagePullSecrets:
  - name: regcred

# Option 3: Update service account
kubectl patch serviceaccount default -n <namespace> \
  -p '{"imagePullSecrets": [{"name": "regcred"}]}'
```

### 6. CRD Issues

**Symptom:**
```
Error: unable to recognize "": no matches for kind "MyCustomResource" in version "mygroup/v1"
```

**Causes:**
- CRD not installed
- CRD installed in wrong order
- CRD version mismatch
- API version not supported in cluster

**Debugging Steps:**

```bash
# 1. Check if CRD exists
kubectl get crds | grep myresource

# 2. Check CRD version
kubectl get crd myresource.mygroup.io -o yaml | grep "version:"

# 3. Check API versions supported
kubectl api-resources | grep mygroup

# 4. Verify template uses correct API version
helm template myapp ./chart | grep "apiVersion:"
```

**Solutions:**

```bash
# Option 1: Install CRDs first (if separate chart)
helm install myapp-crds ./crds --namespace prod
helm install myapp ./chart --namespace prod

# Option 2: Use --skip-crds if reinstalling
helm upgrade myapp ./chart \
  --namespace prod \
  --skip-crds

# Option 3: Manually install CRDs
kubectl apply -f crds/

# Option 4: Update chart to use correct API version
# Edit templates to use supported apiVersion
```

### 7. Timeout Errors

**Symptom:**
```
Error: timed out waiting for the condition
```

**Causes:**
- Pods not becoming ready (failing health checks)
- Resource limits too low
- Image pull taking too long
- Init containers failing

**Debugging Steps:**

```bash
# 1. Check pod status
kubectl get pods -n <namespace> -l app.kubernetes.io/instance=myapp

# 2. Check pod events and logs
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# 3. Check init containers
kubectl logs <pod-name> -n <namespace> -c <init-container-name>

# 4. Increase timeout and watch
helm upgrade myapp ./chart \
  --namespace prod \
  --wait \
  --timeout 15m \
  --debug &
watch kubectl get pods -n prod
```

**Solutions:**

```bash
# Option 1: Increase timeout
helm upgrade myapp ./chart \
  --namespace prod \
  --timeout 10m \
  --wait

# Option 2: Don't wait (manual verification)
helm upgrade myapp ./chart \
  --namespace prod
# Then manually check: kubectl get pods -n prod

# Option 3: Fix readiness probe
# Adjust in values.yaml or chart templates:
readinessProbe:
  initialDelaySeconds: 30  # Give more time to start
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6  # Allow more failures

# Option 4: Increase resource limits
resources:
  limits:
    memory: "512Mi"  # Was too low at 128Mi
    cpu: "1000m"
```

### 8. Hook Failures

**Symptom:**
```
Error: pre-upgrade hooks failed: job failed
```

**Causes:**
- Hook job failing
- Hook timing issues
- Hook dependencies not met
- Hook timeout

**Debugging Steps:**

```bash
# 1. Check hook jobs/pods
kubectl get jobs -n <namespace>
kubectl get pods -n <namespace> -l helm.sh/hook

# 2. Check hook logs
kubectl logs job/<hook-job-name> -n <namespace>

# 3. Get hook definitions
helm get hooks myapp -n <namespace>

# 4. Check hook status in release
helm get manifest myapp -n <namespace> | grep -A 10 "helm.sh/hook"
```

**Solutions:**

```bash
# Option 1: Delete failed hook resources
kubectl delete job <hook-job> -n <namespace>
helm upgrade myapp ./chart --namespace prod

# Option 2: Skip hooks temporarily (debugging only)
helm upgrade myapp ./chart \
  --namespace prod \
  --no-hooks

# Option 3: Fix hook in template
# Adjust hook annotations:
annotations:
  "helm.sh/hook": pre-upgrade
  "helm.sh/hook-weight": "0"  # Order of execution
  "helm.sh/hook-delete-policy": hook-succeeded,hook-failed  # Cleanup
```

## Debugging Workflow

### Step-by-Step Debugging Process

```bash
# 1. IDENTIFY THE PROBLEM
# Check release status
helm status myapp --namespace prod --show-resources

# Check release history
helm history myapp --namespace prod

# 2. INSPECT CONFIGURATION
# What values were used?
helm get values myapp --namespace prod --all > actual-values.yaml

# What manifests were deployed?
helm get manifest myapp --namespace prod > actual-manifests.yaml

# 3. CHECK KUBERNETES RESOURCES
# Are pods running?
kubectl get pods -n prod -l app.kubernetes.io/instance=myapp

# Any events?
kubectl get events -n prod --sort-by='.lastTimestamp' | tail -20

# Pod details
kubectl describe pod <pod-name> -n prod
kubectl logs <pod-name> -n prod

# 4. VALIDATE LOCALLY
# Re-render templates with same values
helm template myapp ./chart -f actual-values.yaml > local-manifests.yaml

# Compare deployed vs local
diff actual-manifests.yaml local-manifests.yaml

# 5. TEST FIX
# Dry-run with fix
helm upgrade myapp ./chart \
  --namespace prod \
  --set fix.value=true \
  --dry-run --debug

# Apply fix
helm upgrade myapp ./chart \
  --namespace prod \
  --set fix.value=true \
  --atomic --wait
```

## Best Practices for Debugging

### Enable Debug Output
✅ **DO**: Use `--debug` to see what's happening
```bash
helm install myapp ./chart --namespace prod --debug
```

### Dry-Run Everything
✅ **DO**: Always dry-run before applying changes
```bash
helm upgrade myapp ./chart -n prod --dry-run --debug
```

### Layer Your Validation
✅ **DO**: Progress through validation layers
```bash
helm lint ./chart --strict
helm template myapp ./chart -f values.yaml
helm install myapp ./chart -n prod --dry-run --debug
helm install myapp ./chart -n prod --atomic --wait
```

### Capture State
✅ **DO**: Save release state before changes
```bash
# Before upgrade
helm get values myapp -n prod --all > values-before.yaml
helm get manifest myapp -n prod > manifest-before.yaml
kubectl get pods -n prod -o yaml > pods-before.yaml
```

### Use Atomic Deployments
✅ **DO**: Enable automatic rollback
```bash
helm upgrade myapp ./chart -n prod --atomic --wait
```

### Check Kubernetes Resources
✅ **DO**: Inspect deployed resources directly
```bash
kubectl get all -n prod -l app.kubernetes.io/instance=myapp
kubectl describe pod <pod> -n prod
kubectl logs <pod> -n prod
```

### Understand Value Precedence
✅ **DO**: Know override order
```bash
# Lowest to highest precedence:
# 1. Chart defaults (values.yaml)
# 2. --reuse-values (previous release)
# 3. -f values1.yaml
# 4. -f values2.yaml (overrides values1.yaml)
# 5. --set key=value (overrides everything)
```

## Debugging Tools & Utilities

### yq - YAML Processor
```bash
# Validate YAML syntax
helm template myapp ./chart | yq eval '.' -

# Extract specific values
helm get values myapp -n prod -o yaml | yq eval '.image.tag' -

# Pretty print
helm get manifest myapp -n prod | yq eval '.' -
```

### kubectl Plugin: stern
```bash
# Tail logs from multiple pods
stern -n prod myapp

# Follow logs with timestamps
stern -n prod myapp --timestamps
```

### kubectl Plugin: neat
```bash
# Clean kubectl output (remove clutter)
kubectl get pod <pod> -n prod -o yaml | kubectl neat
```

### k9s - Kubernetes CLI
```bash
# Interactive cluster management
k9s -n prod

# Features:
# - Live resource updates
# - Log viewing
# - Resource editing
# - Port forwarding
```

## Integration with Other Tools

### ArgoCD Debugging
```bash
# When managed by ArgoCD:

# 1. Check ArgoCD Application status
argocd app get <app-name>

# 2. Still use helm for inspection
helm get values <release> -n <namespace> --all
helm get manifest <release> -n <namespace>

# 3. Sync with debugging
argocd app sync <app-name> --dry-run
argocd app sync <app-name> --prune --force
```

### CI/CD Debugging
```yaml
# Add debugging to pipeline
- name: Debug Helm Install
  run: |
    set -x  # Enable bash debugging
    helm template myapp ./chart \
      -f values.yaml \
      --debug
    helm install myapp ./chart \
      --namespace prod \
      --dry-run \
      --debug
  continue-on-error: true  # Don't fail pipeline

- name: Capture State on Failure
  if: failure()
  run: |
    helm list --all-namespaces
    kubectl get all -n prod
    kubectl describe pods -n prod
    kubectl logs -n prod --all-containers --tail=100
```

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
