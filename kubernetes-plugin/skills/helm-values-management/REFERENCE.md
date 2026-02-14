# Helm Values Management - Reference

Detailed reference material for Helm values management.

## Full Environment Value Examples

### Dev Environment (values/dev.yaml)

```yaml
# Development-specific overrides
replicaCount: 1

image:
  tag: latest
  pullPolicy: Always

ingress:
  hostname: myapp-dev.example.com

resources:
  limits:
    cpu: 500m
    memory: 512Mi

# Enable debug mode
debug: true
logLevel: debug
```

### Staging Environment (values/staging.yaml)

```yaml
# Staging-specific overrides
replicaCount: 2

image:
  tag: v1.2.3
  pullPolicy: IfNotPresent

ingress:
  hostname: myapp-staging.example.com

resources:
  limits:
    cpu: 1000m
    memory: 1Gi

# Production-like settings
debug: false
logLevel: info
```

### Production Environment (values/production.yaml)

```yaml
# Production-specific overrides
replicaCount: 5

image:
  tag: v1.2.3
  pullPolicy: IfNotPresent

ingress:
  hostname: myapp.example.com

resources:
  limits:
    cpu: 2000m
    memory: 2Gi

# High availability
podAntiAffinity:
  enabled: true

# Monitoring
monitoring:
  enabled: true
  serviceMonitor: true

# Production hardening
debug: false
logLevel: warn
securityContext:
  readOnlyRootFilesystem: true
  runAsNonRoot: true
```

## Values Schema Validation

### Define Schema (values.schema.json)

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount", "image"],
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
        }
      }
    },
    "enabled": {
      "type": "boolean",
      "description": "Enable feature"
    }
  }
}
```

### Validation Automatically Runs

```bash
# Schema is validated during:
helm install myapp ./chart --values values.yaml
helm upgrade myapp ./chart --values values.yaml
helm template myapp ./chart --values values.yaml --validate

# Errors will show:
# Error: values don't meet the specifications of the schema(s)
```

## Secret Management Options

### Option 1: Separate Secret Files (Gitignored)

```yaml
# values/secrets/production.yaml (GITIGNORED)
database:
  password: super-secret-password

api:
  key: api-key-12345

tls:
  cert: |
    -----BEGIN CERTIFICATE-----
    ...
    -----END CERTIFICATE-----
```

```bash
# Deploy with secrets file
helm upgrade myapp ./chart \
  --namespace prod \
  -f values/common.yaml \
  -f values/production.yaml \
  -f values/secrets/production.yaml
```

### Option 2: Environment Variables

```bash
# Set from environment
helm upgrade myapp ./chart \
  --namespace prod \
  -f values.yaml \
  --set database.password=$DB_PASSWORD \
  --set api.key=$API_KEY
```

### Option 3: Helm Secrets Plugin

```bash
# Install helm-secrets plugin
helm plugin install https://github.com/jkroepke/helm-secrets

# Encrypt secrets file with sops
helm secrets enc values/secrets/production.yaml

# Deploy with encrypted secrets (decrypted on-the-fly)
helm secrets upgrade myapp ./chart \
  --namespace prod \
  -f values/production.yaml \
  -f secrets://values/secrets/production.yaml
```

### Option 4: External Secrets Operator

```yaml
# Use ExternalSecret CRD to fetch from vault/AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  secretStoreRef:
    name: vault-backend
  target:
    name: myapp-secrets
  data:
  - secretKey: database-password
    remoteRef:
      key: myapp/prod/db-password
```

```yaml
# Reference in values.yaml
existingSecret: myapp-secrets
```

## Template Value Handling

### Accessing Values

```yaml
# Simple value
image: {{ .Values.image.repository }}:{{ .Values.image.tag }}

# With default
replicas: {{ .Values.replicaCount | default 1 }}

# Required value (fails if not provided)
database: {{ required "database.host is required" .Values.database.host }}

# Conditional
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
{{- end }}
```

### Type Conversions

```yaml
# Ensure integer
replicas: {{ .Values.replicaCount | int }}

# Ensure string (and quote)
version: {{ .Values.version | quote }}

# Boolean
enabled: {{ .Values.enabled | ternary "true" "false" }}
```

### Complex Value Rendering

```yaml
# Merge labels
labels:
{{- toYaml .Values.labels | nindent 2 }}

# Range over list
env:
{{- range .Values.env }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# Conditional inclusion
{{- if .Values.extraEnv }}
{{- toYaml .Values.extraEnv | nindent 2 }}
{{- end }}
```

## Best Practices

### Value File Organization

Layer values files (base -> environment -> secrets):
```bash
helm install myapp ./chart \
  -f values/base.yaml \
  -f values/prod.yaml \
  -f values/secrets.yaml
```

Use consistent naming conventions:
```
values/
├── base.yaml        # Or common.yaml
├── dev.yaml
├── staging.yaml
├── production.yaml  # Or prod.yaml
└── secrets/
    └── production.yaml
```

### Value Precedence

Understand and document precedence:
```bash
# Explicit precedence (right-most wins):
helm install myapp ./chart \
  -f base.yaml \      # Lowest
  -f prod.yaml \      # Overrides base
  --set replicas=5    # Highest
```

Avoid mixing `--reuse-values` with other value sources (confusing precedence).

### Value Naming

Use clear, hierarchical names:
```yaml
database:
  host: db.example.com
  port: 5432
  name: myapp

cache:
  host: redis.example.com
  port: 6379
```

### Required Values

Mark required values in template:
```yaml
database:
  host: {{ required "database.host is required" .Values.database.host }}
```

Document required values in values.yaml comments:
```yaml
# database.host is REQUIRED
database:
  host: ""  # Set to your database hostname
  port: 5432
```

### Secret Management

Keep secrets in separate, gitignored files:
```
values/
├── production.yaml          # Committed
└── secrets/
    └── production.yaml      # GITIGNORED
```

Use existing secrets when possible:
```yaml
# Reference existing Kubernetes secret
existingSecret: myapp-database-credentials
```

### Value Validation

Create values.schema.json for validation:
```json
{
  "required": ["replicaCount", "image"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    }
  }
}
```

Test value combinations:
```bash
# Test each environment's values
helm template myapp ./chart -f values/dev.yaml
helm template myapp ./chart -f values/staging.yaml
helm template myapp ./chart -f values/production.yaml
```

## Troubleshooting Values

### Debug Value Precedence

```bash
# See computed values
helm install myapp ./chart \
  -f values1.yaml \
  -f values2.yaml \
  --set key=value \
  --debug --dry-run 2>&1 | grep -A 50 "COMPUTED VALUES"
```

### Compare Values

```bash
# Compare deployed vs expected
diff <(helm get values myapp -n prod --all) expected-values.yaml

# Compare environments
diff values/staging.yaml values/production.yaml
```

### Find Missing Values

```bash
# Check for required values
helm template myapp ./chart -f values.yaml 2>&1 | grep "required"

# Validate schema
helm install myapp ./chart -f values.yaml --dry-run
```
