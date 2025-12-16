---
name: helm-chart-development
description: |
  Create, test, and package Helm charts for Kubernetes. Covers helm create, Chart.yaml,
  values.yaml, template development, chart dependencies, packaging, and repository publishing.
  Use when user mentions Helm charts, helm create, Chart.yaml, values.yaml, helm lint,
  helm template, helm package, or Kubernetes packaging.
---

# Helm Chart Development

Comprehensive guidance for creating, testing, and packaging custom Helm charts with best practices for maintainability and reusability.

## When to Use

Use this skill automatically when:
- User wants to create a new Helm chart
- User needs to validate chart structure or templates
- User mentions testing charts locally
- User wants to package or publish charts
- User needs to manage chart dependencies
- User asks about chart best practices

## Chart Creation & Structure

### Create New Chart

```bash
# Scaffold new chart with standard structure
helm create mychart

# Creates:
# mychart/
# ├── Chart.yaml          # Chart metadata
# ├── values.yaml         # Default values
# ├── charts/             # Chart dependencies
# ├── templates/          # Kubernetes manifests
# │   ├── NOTES.txt       # Post-install instructions
# │   ├── _helpers.tpl    # Template helpers
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   ├── ingress.yaml
# │   └── tests/
# │       └── test-connection.yaml
# └── .helmignore         # Files to ignore
```

### Chart.yaml Structure

```yaml
# Chart.yaml - Chart metadata
apiVersion: v2                  # Helm 3 uses v2
name: mychart                   # Chart name
version: 0.1.0                  # Chart version (SemVer)
appVersion: "1.0.0"            # Application version
description: A Helm chart for Kubernetes
type: application               # application or library
keywords:
  - api
  - web
home: https://example.com
sources:
  - https://github.com/example/mychart
maintainers:
  - name: John Doe
    email: john@example.com
dependencies:                   # Chart dependencies
  - name: postgresql
    version: "12.1.9"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled  # Optional: enable/disable
    tags:                          # Optional: group dependencies
      - database
```

### Values.yaml Design

```yaml
# values.yaml - Default configuration
# Use clear hierarchy and comments

# Replica configuration
replicaCount: 1

# Image configuration
image:
  repository: nginx
  pullPolicy: IfNotPresent
  tag: ""  # Overrides appVersion

imagePullSecrets: []
nameOverride: ""
fullnameOverride: ""

# Service configuration
service:
  type: ClusterIP
  port: 80

# Ingress configuration
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: ImplementationSpecific
  tls: []

# Resource limits
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 100m
    memory: 128Mi

# Autoscaling
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 100
  targetCPUUtilizationPercentage: 80

# Node selection
nodeSelector: {}
tolerations: []
affinity: {}
```

## Chart Validation & Testing

### Lint Chart

```bash
# Basic linting
helm lint ./mychart

# Strict linting (warnings as errors)
helm lint ./mychart --strict

# Lint with specific values
helm lint ./mychart \
  --values values.yaml \
  --strict

# Lint with multiple value files
helm lint ./mychart \
  --values values/common.yaml \
  --values values/production.yaml \
  --strict
```

**What Lint Checks:**
- Chart.yaml validity
- values.yaml syntax
- Template syntax errors
- Required fields present
- Version format (SemVer)
- Deprecated API versions

### Render Templates Locally

```bash
# Render all templates
helm template mychart ./mychart

# Render with custom release name and namespace
helm template myrelease ./mychart \
  --namespace production

# Render with values
helm template myrelease ./mychart \
  --values values.yaml

# Render specific template
helm template myrelease ./mychart \
  --show-only templates/deployment.yaml

# Render with debug output
helm template myrelease ./mychart \
  --debug

# Validate against Kubernetes API
helm template myrelease ./mychart \
  --validate
```

### Dry-Run Installation

```bash
# Dry-run with server-side validation
helm install myrelease ./mychart \
  --namespace production \
  --dry-run \
  --debug

# Validates:
# - Template rendering
# - Kubernetes API compatibility
# - Resource conflicts
# - RBAC permissions
```

### Run Chart Tests

```bash
# Install chart
helm install myrelease ./mychart --namespace test

# Run tests
helm test myrelease --namespace test

# Run tests with logs
helm test myrelease --namespace test --logs

# Cleanup after tests
helm uninstall myrelease --namespace test
```

**Chart Test Structure:**

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ include "mychart.fullname" . }}-test-connection"
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": hook-succeeded,hook-failed
spec:
  containers:
  - name: wget
    image: busybox
    command: ['wget']
    args: ['{{ include "mychart.fullname" . }}:{{ .Values.service.port }}']
  restartPolicy: Never
```

## Template Development

### Template Helpers (_helpers.tpl)

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a fully qualified app name.
*/}}
{{- define "mychart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mychart.labels" -}}
helm.sh/chart: {{ include "mychart.chart" . }}
{{ include "mychart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### Template Best Practices

**Use Named Templates:**
```yaml
# ✅ GOOD: Reusable labels
labels:
{{- include "mychart.labels" . | nindent 2 }}

# ❌ BAD: Duplicate label definitions
labels:
  app.kubernetes.io/name: mychart
  app.kubernetes.io/instance: {{ .Release.Name }}
```

**Quote String Values:**
```yaml
# ✅ GOOD: Quoted to prevent YAML issues
env:
- name: APP_NAME
  value: {{ .Values.appName | quote }}

# ❌ BAD: Unquoted strings can break
env:
- name: APP_NAME
  value: {{ .Values.appName }}  # Breaks if value is "true" or "123"
```

**Use Required for Mandatory Values:**
```yaml
# ✅ GOOD: Fails fast with clear error
database:
  host: {{ required "database.host is required" .Values.database.host }}

# ❌ BAD: Silent failure or confusing errors
database:
  host: {{ .Values.database.host }}
```

**Handle Whitespace Properly:**
```yaml
# ✅ GOOD: Proper indentation and chomping
labels:
{{- include "mychart.labels" . | nindent 2 }}

# ❌ BAD: Extra newlines or indentation issues
labels:
{{ include "mychart.labels" . }}
```

**Conditional Resources:**
```yaml
# ✅ GOOD: Clean conditional
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  ...
{{- end }}

# ❌ BAD: Always creates resource
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  {{- if .Values.ingress.enabled }}
  ...
  {{- end }}
```

## Chart Dependencies

### Define Dependencies (Chart.yaml)

```yaml
# Chart.yaml
dependencies:
- name: postgresql
  version: "12.1.9"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled       # Enable/disable via values

- name: redis
  version: "17.0.0"
  repository: https://charts.bitnami.com/bitnami
  condition: redis.enabled

- name: common                         # Local dependency
  version: "1.0.0"
  repository: file://../common-library
```

### Manage Dependencies

```bash
# Download/update dependencies
helm dependency update ./mychart

# Creates:
# - Chart.lock          # Locked versions
# - charts/*.tgz        # Downloaded charts

# Build from existing Chart.lock
helm dependency build ./mychart

# List dependencies
helm dependency list ./mychart
```

### Configure Subchart Values

```yaml
# values.yaml - Parent chart
# Configure subcharts using subchart name as key

# PostgreSQL subchart configuration
postgresql:
  enabled: true
  auth:
    username: myapp
    database: myapp
    existingSecret: myapp-db-secret
  primary:
    persistence:
      size: 10Gi

# Redis subchart configuration
redis:
  enabled: true
  auth:
    enabled: false
  master:
    persistence:
      size: 5Gi
```

### Override Subchart Values

```bash
# Override subchart values from CLI
helm install myapp ./mychart \
  --set postgresql.auth.password=secret123 \
  --set redis.enabled=false
```

## Chart Packaging & Distribution

### Package Chart

```bash
# Package chart into .tgz
helm package ./mychart

# Creates: mychart-0.1.0.tgz

# Package with specific destination
helm package ./mychart --destination ./dist/

# Package and update dependencies
helm package ./mychart --dependency-update

# Sign package (requires GPG key)
helm package ./mychart --sign --key mykey --keyring ~/.gnupg/secring.gpg
```

### Chart Repository

```bash
# Create repository index
helm repo index ./repo/

# Creates: index.yaml

# Add local repository
helm repo add myrepo file://$(pwd)/repo

# Update repository index
helm repo update

# Search local repository
helm search repo myrepo/

# Push to ChartMuseum (if using)
curl --data-binary "@mychart-0.1.0.tgz" http://chartmuseum.example.com/api/charts

# Push to OCI registry (Helm 3.8+)
helm push mychart-0.1.0.tgz oci://registry.example.com/charts
```

## Schema Validation

### Create Values Schema (values.schema.json)

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "MyChart Values",
  "type": "object",
  "required": ["image", "service"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1,
      "maximum": 100,
      "description": "Number of replicas"
    },
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": {
          "type": "string",
          "description": "Image repository"
        },
        "tag": {
          "type": "string",
          "pattern": "^v?[0-9]+\\.[0-9]+\\.[0-9]+$",
          "description": "Image tag (SemVer)"
        },
        "pullPolicy": {
          "type": "string",
          "enum": ["Always", "IfNotPresent", "Never"],
          "description": "Image pull policy"
        }
      }
    },
    "service": {
      "type": "object",
      "required": ["port"],
      "properties": {
        "type": {
          "type": "string",
          "enum": ["ClusterIP", "NodePort", "LoadBalancer"],
          "description": "Service type"
        },
        "port": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535,
          "description": "Service port"
        }
      }
    },
    "ingress": {
      "type": "object",
      "properties": {
        "enabled": {
          "type": "boolean",
          "description": "Enable ingress"
        },
        "hosts": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["host"],
            "properties": {
              "host": {
                "type": "string",
                "format": "hostname"
              }
            }
          }
        }
      }
    }
  }
}
```

### Schema Validation

Schema validation runs automatically during:
- `helm install`
- `helm upgrade`
- `helm template --validate`
- `helm lint`

```bash
# Validation errors will show:
Error: values don't meet the specifications of the schema(s)
- replicaCount: Invalid type. Expected: integer, given: string
```

## Chart Documentation

### NOTES.txt Template

```yaml
# templates/NOTES.txt - Post-install instructions
Thank you for installing {{ .Chart.Name }}!

Your release is named {{ .Release.Name }}.

To learn more about the release, try:

  $ helm status {{ .Release.Name }} --namespace {{ .Release.Namespace }}
  $ helm get all {{ .Release.Name }} --namespace {{ .Release.Namespace }}

{{- if .Values.ingress.enabled }}
Application is available at:
{{- range .Values.ingress.hosts }}
  http{{ if $.Values.ingress.tls }}s{{ end }}://{{ .host }}
{{- end }}
{{- else }}
Get the application URL by running:
  export POD_NAME=$(kubectl get pods --namespace {{ .Release.Namespace }} -l "app.kubernetes.io/name={{ include "mychart.name" . }},app.kubernetes.io/instance={{ .Release.Name }}" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace {{ .Release.Namespace }} port-forward $POD_NAME 8080:{{ .Values.service.port }}
  echo "Visit http://127.0.0.1:8080"
{{- end }}
```

### README.md

```markdown
# MyChart

A Helm chart for deploying MyApp to Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installation

```bash
helm install myapp oci://registry.example.com/charts/mychart
```

## Configuration

See `values.yaml` in your chart directory for configuration options.

Key parameters:
- `replicaCount` - Number of replicas (default: 1)
- `image.repository` - Image repository
- `image.tag` - Image tag

## Upgrading

```bash
helm upgrade myapp oci://registry.example.com/charts/mychart
```

## Uninstallation

```bash
helm uninstall myapp
```
```

## Chart Testing Workflow

### Local Development Testing

```bash
# 1. Create chart
helm create testchart

# 2. Modify templates and values
# Edit templates/deployment.yaml, values.yaml

# 3. Lint
helm lint ./testchart --strict

# 4. Render templates
helm template testapp ./testchart \
  --values test-values.yaml \
  --debug

# 5. Dry-run
helm install testapp ./testchart \
  --namespace test \
  --create-namespace \
  --dry-run \
  --debug

# 6. Install to test cluster
helm install testapp ./testchart \
  --namespace test \
  --create-namespace \
  --atomic \
  --wait

# 7. Run tests
helm test testapp --namespace test --logs

# 8. Verify deployment
kubectl get all -n test -l app.kubernetes.io/instance=testapp

# 9. Cleanup
helm uninstall testapp --namespace test
kubectl delete namespace test
```

### CI/CD Testing

```yaml
# GitHub Actions example
name: Chart Testing

on: [pull_request]

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: '3.12.0'

      - name: Lint Chart
        run: helm lint ./charts/mychart --strict

      - name: Template Chart
        run: |
          helm template test ./charts/mychart \
            --values ./charts/mychart/ci/test-values.yaml \
            --validate

      - name: Install Chart Testing
        uses: helm/chart-testing-action@v2

      - name: Run Chart Tests
        run: ct lint-and-install --charts ./charts/mychart
```

## Common Chart Patterns

### ConfigMap from Values

```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "mychart.fullname" . }}
data:
  {{- range $key, $value := .Values.config }}
  {{ $key }}: {{ $value | quote }}
  {{- end }}
```

```yaml
# values.yaml
config:
  app.name: "MyApp"
  log.level: "info"
  feature.enabled: "true"
```

### Secret from Existing Secret

```yaml
# templates/deployment.yaml
env:
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.existingSecret | default (include "mychart.fullname" .) }}
      key: db-password
```

### Multiple Services

```yaml
# values.yaml
services:
  api:
    port: 8080
    type: ClusterIP
  metrics:
    port: 9090
    type: ClusterIP

# templates/services.yaml
{{- range $name, $config := .Values.services }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mychart.fullname" $ }}-{{ $name }}
spec:
  type: {{ $config.type }}
  ports:
  - port: {{ $config.port }}
    targetPort: {{ $config.port }}
  selector:
    {{- include "mychart.selectorLabels" $ | nindent 4 }}
{{- end }}
```

## Chart Best Practices

### Versioning
✅ **DO**: Use SemVer for chart and app versions
```yaml
# Chart.yaml
version: 1.2.3        # Chart version
appVersion: "2.5.0"   # Application version
```

### Naming
✅ **DO**: Use consistent naming functions
```yaml
name: {{ include "mychart.fullname" . }}
labels:
{{- include "mychart.labels" . | nindent 2 }}
```

### Defaults
✅ **DO**: Provide sensible defaults in values.yaml
```yaml
replicaCount: 1  # Safe default for testing
resources:
  limits:
    cpu: 100m
    memory: 128Mi  # Reasonable defaults
```

### Documentation
✅ **DO**: Comment values.yaml extensively
```yaml
# Number of replicas to deploy
# Recommended: 3+ for production
replicaCount: 1
```

### Testing
✅ **DO**: Include chart tests
```bash
# Always include templates/tests/
helm test <release>
```

## Related Skills

- **Helm Release Management** - Using charts to deploy
- **Helm Debugging** - Troubleshooting chart issues
- **Helm Values Management** - Configuring charts

## References

- [Helm Chart Development Guide](https://helm.sh/docs/topics/charts/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helm Template Guide](https://helm.sh/docs/chart_template_guide/)
- [Chart Testing](https://github.com/helm/chart-testing)
