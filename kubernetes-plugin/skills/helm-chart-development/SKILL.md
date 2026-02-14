---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: helm-chart-development
description: |
  Create, test, and package Helm charts for Kubernetes. Covers helm create, Chart.yaml,
  values.yaml, template development, chart dependencies, packaging, and repository publishing.
  Use when user mentions Helm charts, helm create, Chart.yaml, values.yaml, helm lint,
  helm template, helm package, or Kubernetes packaging.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
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

## Chart Validation & Testing

### Lint Chart

```bash
# Basic linting
helm lint ./mychart

# Strict linting (warnings as errors)
helm lint ./mychart --strict

# Lint with specific values
helm lint ./mychart --values values.yaml --strict

# Lint with multiple value files
helm lint ./mychart \
  --values values/common.yaml \
  --values values/production.yaml \
  --strict
```

### Render Templates Locally

```bash
# Render all templates
helm template mychart ./mychart

# Render with custom release name and namespace
helm template myrelease ./mychart --namespace production

# Render with values
helm template myrelease ./mychart --values values.yaml

# Render specific template
helm template myrelease ./mychart \
  --show-only templates/deployment.yaml

# Validate against Kubernetes API
helm template myrelease ./mychart --validate
```

### Dry-Run Installation

```bash
# Dry-run with server-side validation
helm install myrelease ./mychart \
  --namespace production \
  --dry-run \
  --debug
```

### Run Chart Tests

```bash
# Install chart, run tests, cleanup
helm install myrelease ./mychart --namespace test
helm test myrelease --namespace test --logs
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

## Chart Dependencies

### Define Dependencies (Chart.yaml)

```yaml
# Chart.yaml
dependencies:
- name: postgresql
  version: "12.1.9"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled

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

# Build from existing Chart.lock
helm dependency build ./mychart

# List dependencies
helm dependency list ./mychart
```

### Configure Subchart Values

```yaml
# values.yaml - Parent chart
postgresql:
  enabled: true
  auth:
    username: myapp
    database: myapp
    existingSecret: myapp-db-secret
  primary:
    persistence:
      size: 10Gi

redis:
  enabled: true
  auth:
    enabled: false
  master:
    persistence:
      size: 5Gi
```

## Chart Packaging & Distribution

### Package Chart

```bash
# Package chart into .tgz
helm package ./mychart

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

# Push to OCI registry (Helm 3.8+)
helm push mychart-0.1.0.tgz oci://registry.example.com/charts
```

For detailed examples of values.yaml design, schema validation, chart documentation templates, testing workflows, common chart patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Lint (strict) | `helm lint ./mychart --strict` |
| Render specific template | `helm template myapp ./mychart --show-only templates/deployment.yaml` |
| Dry-run validation | `helm install myapp ./mychart --dry-run --debug 2>&1 \| head -100` |
| Package chart | `helm package ./mychart --dependency-update` |

## Related Skills

- **Helm Release Management** - Using charts to deploy
- **Helm Debugging** - Troubleshooting chart issues
- **Helm Values Management** - Configuring charts

## References

- [Helm Chart Development Guide](https://helm.sh/docs/topics/charts/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Helm Template Guide](https://helm.sh/docs/chart_template_guide/)
- [Chart Testing](https://github.com/helm/chart-testing)
