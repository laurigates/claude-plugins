# Helm Chart Development - Reference

Detailed reference material for helm chart development.

## Full Values.yaml Design

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

## Template Best Practices

**Use Named Templates:**
```yaml
# Reusable labels
labels:
{{- include "mychart.labels" . | nindent 2 }}

# Avoid duplicate label definitions
```

**Quote String Values:**
```yaml
# Quoted to prevent YAML issues
env:
- name: APP_NAME
  value: {{ .Values.appName | quote }}

# Unquoted strings can break if value is "true" or "123"
```

**Use Required for Mandatory Values:**
```yaml
# Fails fast with clear error
database:
  host: {{ required "database.host is required" .Values.database.host }}
```

**Handle Whitespace Properly:**
```yaml
# Proper indentation and chomping
labels:
{{- include "mychart.labels" . | nindent 2 }}
```

**Conditional Resources:**
```yaml
# Clean conditional
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  ...
{{- end }}
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

## Chart Documentation Templates

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

### README.md Template

```markdown
# MyChart

A Helm chart for deploying MyApp to Kubernetes.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installation

helm install myapp oci://registry.example.com/charts/mychart

## Configuration

See `values.yaml` in your chart directory for configuration options.

Key parameters:
- `replicaCount` - Number of replicas (default: 1)
- `image.repository` - Image repository
- `image.tag` - Image tag

## Upgrading

helm upgrade myapp oci://registry.example.com/charts/mychart

## Uninstallation

helm uninstall myapp
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
Use SemVer for chart and app versions:
```yaml
# Chart.yaml
version: 1.2.3        # Chart version
appVersion: "2.5.0"   # Application version
```

### Naming
Use consistent naming functions:
```yaml
name: {{ include "mychart.fullname" . }}
labels:
{{- include "mychart.labels" . | nindent 2 }}
```

### Defaults
Provide sensible defaults in values.yaml:
```yaml
replicaCount: 1  # Safe default for testing
resources:
  limits:
    cpu: 100m
    memory: 128Mi  # Reasonable defaults
```

### Documentation
Comment values.yaml extensively:
```yaml
# Number of replicas to deploy
# Recommended: 3+ for production
replicaCount: 1
```

### Testing
Include chart tests:
```bash
# Always include templates/tests/
helm test <release>
```
