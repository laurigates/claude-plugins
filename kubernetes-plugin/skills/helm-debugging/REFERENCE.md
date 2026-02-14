# Helm Debugging & Troubleshooting - Reference

Detailed reference material for Helm debugging and troubleshooting.

## Common Failure Scenarios - Detailed Steps

### YAML Parse Errors

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
# WRONG: Inconsistent whitespace
spec:
  containers:
  - name: {{ .Values.name }}
      image: {{ .Values.image }}  # Too much indent

# CORRECT: Consistent 2-space indent
spec:
  containers:
  - name: {{ .Values.name }}
    image: {{ .Values.image }}

# WRONG: Missing whitespace chomping
labels:
{{ toYaml .Values.labels }}  # Adds extra newlines

# CORRECT: Chomp whitespace
labels:
{{- toYaml .Values.labels | nindent 2 }}
```

### Template Rendering Errors

**Symptom:**
```
Error: template: mychart/templates/deployment.yaml:15:8: executing "mychart/templates/deployment.yaml" at <.Values.foo>: nil pointer evaluating interface {}.foo
```

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
# WRONG: No default or check
image: {{ .Values.image.tag }}  # Fails if .Values.image is nil

# CORRECT: Use default
image: {{ .Values.image.tag | default "latest" }}

# CORRECT: Check before accessing
{{- if .Values.image }}
image: {{ .Values.image.tag | default "latest" }}
{{- end }}

# CORRECT: Use required for mandatory values
image: {{ required "image.repository is required" .Values.image.repository }}
```

### Value Type Errors

**Symptom:**
```
Error: json: cannot unmarshal string into Go value of type int
```

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
# WRONG: String in values.yaml
replicaCount: "3"  # String

# CORRECT: Number in values.yaml
replicaCount: 3  # Int

# Template: Always convert to correct type
replicas: {{ .Values.replicaCount | int }}
port: {{ .Values.service.port | int }}
enabled: {{ .Values.feature.enabled | ternary "true" "false" }}
```

### Resource Already Exists

**Symptom:**
```
Error: rendered manifests contain a resource that already exists
```

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

# Option 3: Adopt existing resources (advanced)
kubectl annotate <resource-type> <name> \
  meta.helm.sh/release-name=<release> \
  meta.helm.sh/release-namespace=<namespace> \
  -n <namespace>
kubectl label <resource-type> <name> \
  app.kubernetes.io/managed-by=Helm \
  -n <namespace>
```

### Image Pull Failures

**Symptom:**
```
Pod status: ImagePullBackOff or ErrImagePull
```

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
```

### CRD Issues

**Symptom:**
```
Error: unable to recognize "": no matches for kind "MyCustomResource" in version "mygroup/v1"
```

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
helm upgrade myapp ./chart --namespace prod --skip-crds

# Option 3: Manually install CRDs
kubectl apply -f crds/
```

### Timeout Errors

**Symptom:**
```
Error: timed out waiting for the condition
```

**Debugging Steps:**

```bash
# 1. Check pod status
kubectl get pods -n <namespace> -l app.kubernetes.io/instance=myapp

# 2. Check pod events and logs
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>

# 3. Check init containers
kubectl logs <pod-name> -n <namespace> -c <init-container-name>
```

**Solutions:**

```bash
# Option 1: Increase timeout
helm upgrade myapp ./chart --namespace prod --timeout 10m --wait

# Option 2: Fix readiness probe
# Adjust in values.yaml or chart templates:
readinessProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6

# Option 3: Increase resource limits
resources:
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

### Hook Failures

**Symptom:**
```
Error: pre-upgrade hooks failed: job failed
```

**Debugging Steps:**

```bash
# 1. Check hook jobs/pods
kubectl get jobs -n <namespace>
kubectl get pods -n <namespace> -l helm.sh/hook

# 2. Check hook logs
kubectl logs job/<hook-job-name> -n <namespace>

# 3. Get hook definitions
helm get hooks myapp -n <namespace>
```

**Solutions:**

```bash
# Option 1: Delete failed hook resources
kubectl delete job <hook-job> -n <namespace>
helm upgrade myapp ./chart --namespace prod

# Option 2: Skip hooks temporarily (debugging only)
helm upgrade myapp ./chart --namespace prod --no-hooks

# Option 3: Fix hook in template
annotations:
  "helm.sh/hook": pre-upgrade
  "helm.sh/hook-weight": "0"
  "helm.sh/hook-delete-policy": hook-succeeded,hook-failed
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
Use `--debug` to see what's happening:
```bash
helm install myapp ./chart --namespace prod --debug
```

### Dry-Run Everything
Always dry-run before applying changes:
```bash
helm upgrade myapp ./chart -n prod --dry-run --debug
```

### Layer Your Validation
Progress through validation layers:
```bash
helm lint ./chart --strict
helm template myapp ./chart -f values.yaml
helm install myapp ./chart -n prod --dry-run --debug
helm install myapp ./chart -n prod --atomic --wait
```

### Capture State
Save release state before changes:
```bash
helm get values myapp -n prod --all > values-before.yaml
helm get manifest myapp -n prod > manifest-before.yaml
kubectl get pods -n prod -o yaml > pods-before.yaml
```

### Use Atomic Deployments
Enable automatic rollback:
```bash
helm upgrade myapp ./chart -n prod --atomic --wait
```

### Check Kubernetes Resources
Inspect deployed resources directly:
```bash
kubectl get all -n prod -l app.kubernetes.io/instance=myapp
kubectl describe pod <pod> -n prod
kubectl logs <pod> -n prod
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
