---
name: helm-values-management
description: |
  Manage Helm values across environments with override precedence, multi-environment
  configurations, and secret management. Covers values files, --set, --set-string,
  values schema validation. Use when user mentions Helm values, environment-specific
  configs, values.yaml, --set overrides, or Helm configuration.
---

# Helm Values Management

Comprehensive guidance for managing Helm values across environments, understanding override precedence, and advanced configuration strategies.

## When to Use

Use this skill automatically when:
- User needs to configure Helm deployments with custom values
- User mentions environment-specific configurations (dev/staging/prod)
- User asks about value override precedence or merging
- User needs to manage secrets or sensitive configuration
- User wants to understand what values were deployed
- User needs to validate or inspect values

## Value Override Precedence

Values are merged with **right-most precedence** (last wins):

```
1. Chart defaults (values.yaml in chart)
   ↓
2. Parent chart values (if subchart)
   ↓
3. Previous release values (--reuse-values)
   ↓
4. Values files in order (-f values1.yaml -f values2.yaml)
   ↓
5. Individual overrides (--set, --set-string, --set-json, --set-file)
   ↑
   HIGHEST PRECEDENCE
```

### Example Precedence

```yaml
# Chart values.yaml
replicaCount: 1
image:
  tag: "1.0.0"

# -f base.yaml
replicaCount: 2

# -f production.yaml
image:
  tag: "2.0.0"

# --set replicaCount=5

# RESULT:
# replicaCount: 5        (from --set, highest precedence)
# image.tag: "2.0.0"     (from production.yaml)
```

## Core Value Commands

### View Default Values

```bash
# Show chart default values
helm show values <chart>

# Show values from specific chart version
helm show values <chart> --version 1.2.3

# Save defaults to file
helm show values bitnami/nginx > default-values.yaml

# Show values for local chart
helm show values ./mychart
```

### View Deployed Values

```bash
# Get values used in deployed release
helm get values <release> --namespace <namespace>

# Get ALL values (including defaults)
helm get values <release> --namespace <namespace> --all

# Get values in different formats
helm get values <release> -n <namespace> -o yaml
helm get values <release> -n <namespace> -o json

# Get values from specific revision
helm get values <release> -n <namespace> --revision 2
```

### Set Values During Install/Upgrade

```bash
# Using values file
helm install myapp ./chart \
  --namespace prod \
  --values values.yaml

# Using multiple values files (right-most wins)
helm install myapp ./chart \
  --namespace prod \
  -f values/base.yaml \
  -f values/production.yaml

# Using --set for individual values
helm install myapp ./chart \
  --namespace prod \
  --set replicaCount=3 \
  --set image.tag=v2.0.0

# Using --set-string to force string type
helm install myapp ./chart \
  --namespace prod \
  --set-string version="1.0"  # Keeps as string, not number

# Using --set-json for complex structures
helm install myapp ./chart \
  --namespace prod \
  --set-json 'nodeSelector={"disktype":"ssd","region":"us-west"}'

# Using --set-file to read value from file
helm install myapp ./chart \
  --namespace prod \
  --set-file tlsCert=./certs/tls.crt
```

### Value Reuse Strategies

```bash
# Reuse existing values, merge with new
helm upgrade myapp ./chart \
  --namespace prod \
  --reuse-values \
  --set image.tag=v2.0.0

# Reset to chart defaults, ignore existing values
helm upgrade myapp ./chart \
  --namespace prod \
  --reset-values \
  -f new-values.yaml

# Reset specific values (advanced)
helm upgrade myapp ./chart \
  --namespace prod \
  --reset-values \
  --reuse-values \
  -f values.yaml
```

## Multi-Environment Value Management

### Directory Structure

```
project/
├── charts/
│   └── myapp/           # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml  # Chart defaults
│       └── templates/
└── values/              # Environment-specific values
    ├── common.yaml      # Shared across all environments
    ├── dev.yaml         # Development overrides
    ├── staging.yaml     # Staging overrides
    ├── production.yaml  # Production overrides
    └── secrets/         # Sensitive values (gitignored)
        ├── dev.yaml
        ├── staging.yaml
        └── production.yaml
```

### Common Values (values/common.yaml)

```yaml
# Shared configuration across all environments
app:
  name: myapp
  labels:
    team: platform
    component: api

service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt

resources:
  requests:
    cpu: 100m
    memory: 128Mi
```

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

### Deployment Commands

```bash
# Deploy to dev
helm upgrade --install myapp ./charts/myapp \
  --namespace dev \
  --create-namespace \
  -f values/common.yaml \
  -f values/dev.yaml \
  -f values/secrets/dev.yaml

# Deploy to staging
helm upgrade --install myapp ./charts/myapp \
  --namespace staging \
  --create-namespace \
  -f values/common.yaml \
  -f values/staging.yaml \
  -f values/secrets/staging.yaml \
  --atomic --wait

# Deploy to production
helm upgrade --install myapp ./charts/myapp \
  --namespace production \
  --create-namespace \
  -f values/common.yaml \
  -f values/production.yaml \
  -f values/secrets/production.yaml \
  --atomic --wait --timeout 10m
```

## Value Syntax & Types

### Simple Values

```yaml
# String
name: myapp
tag: "v1.0.0"  # Quote to ensure string

# Number
replicaCount: 3
port: 8080

# Boolean
enabled: true
debug: false

# Null
database: null
```

### Nested Values

```yaml
# Nested objects
image:
  repository: nginx
  tag: "1.21.0"
  pullPolicy: IfNotPresent

# Access in template: {{ .Values.image.repository }}
```

### Lists/Arrays

```yaml
# Simple list
tags:
  - api
  - web
  - production

# List of objects
env:
  - name: DATABASE_URL
    value: postgres://db:5432/myapp
  - name: REDIS_URL
    value: redis://cache:6379

# Access in template:
# {{ range .Values.env }}
# - name: {{ .name }}
#   value: {{ .value }}
# {{ end }}
```

### Setting Values via CLI

```bash
# Simple value
--set name=myapp

# Nested value (use dot notation)
--set image.tag=v2.0.0
--set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt

# List values (use array index or {})
--set tags[0]=api
--set tags[1]=web
--set tags={api,web,prod}

# List of objects (use array syntax)
--set 'env[0].name=DB_URL,env[0].value=postgres://db'

# Complex JSON structures
--set-json 'nodeSelector={"disk":"ssd","region":"us-west"}'
```

### Value Type Coercion

```bash
# Force string (prevents numeric conversion)
--set-string version="1.0"  # Keeps as "1.0", not 1.0

# Force boolean
--set enabled=true

# Force number
--set port=8080

# Read value from file
--set-file cert=./tls.crt
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

## Secret Management

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

## Value Validation & Testing

### Template with Values

```bash
# Render templates with values
helm template myapp ./chart \
  --values values.yaml

# Validate against Kubernetes API
helm install myapp ./chart \
  --values values.yaml \
  --dry-run \
  --validate
```

### Check Computed Values

```bash
# See what values will be used (before install)
helm template myapp ./chart \
  --values values.yaml \
  --debug 2>&1 | grep -A 100 "COMPUTED VALUES"

# See what values were used (after install)
helm get values myapp --namespace prod --all
```

### Test Different Value Combinations

```bash
# Test with minimal values
helm template myapp ./chart \
  --set image.tag=test

# Test with full production values
helm template myapp ./chart \
  -f values/common.yaml \
  -f values/production.yaml

# Test with overrides
helm template myapp ./chart \
  -f values/production.yaml \
  --set replicaCount=10
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

✅ **DO**: Layer values files (base → environment → secrets)
```bash
helm install myapp ./chart \
  -f values/base.yaml \
  -f values/prod.yaml \
  -f values/secrets.yaml
```

✅ **DO**: Use consistent naming conventions
```
values/
├── base.yaml        # Or common.yaml
├── dev.yaml
├── staging.yaml
├── production.yaml  # Or prod.yaml
└── secrets/
    └── production.yaml
```

❌ **DON'T**: Mix concerns in single values file
```yaml
# Bad: Everything in one file
production-with-secrets-and-configs.yaml
```

### Value Precedence

✅ **DO**: Understand and document precedence
```bash
# Explicit precedence (right-most wins):
helm install myapp ./chart \
  -f base.yaml \      # Lowest
  -f prod.yaml \      # Overrides base
  --set replicas=5    # Highest
```

❌ **DON'T**: Mix --reuse-values with other value sources (confusing)
```bash
# Confusing: What values win?
helm upgrade myapp ./chart \
  --reuse-values \
  -f new-values.yaml
```

### Value Naming

✅ **DO**: Use clear, hierarchical names
```yaml
database:
  host: db.example.com
  port: 5432
  name: myapp

cache:
  host: redis.example.com
  port: 6379
```

❌ **DON'T**: Use flat, ambiguous names
```yaml
dbHost: db.example.com
dbPort: 5432
db: myapp
redisHost: redis.example.com
redisPort: 6379
```

### Required Values

✅ **DO**: Mark required values in template
```yaml
database:
  host: {{ required "database.host is required" .Values.database.host }}
```

✅ **DO**: Document required values in values.yaml comments
```yaml
# database.host is REQUIRED
database:
  host: ""  # Set to your database hostname
  port: 5432
```

### Secret Management

✅ **DO**: Keep secrets in separate, gitignored files
```
values/
├── production.yaml          # Committed
└── secrets/
    └── production.yaml      # GITIGNORED
```

✅ **DO**: Use existing secrets when possible
```yaml
# Reference existing Kubernetes secret
existingSecret: myapp-database-credentials
```

❌ **DON'T**: Commit secrets to git
```yaml
# BAD: In committed values file
database:
  password: super-secret-123  # ❌ Visible in git
```

### Value Validation

✅ **DO**: Create values.schema.json for validation
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

✅ **DO**: Test value combinations
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

## Related Skills

- **Helm Release Management** - Using values during install/upgrade
- **Helm Debugging** - Troubleshooting value errors
- **Helm Chart Development** - Creating charts with good value design

## References

- [Helm Values Files](https://helm.sh/docs/chart_template_guide/values_files/)
- [Helm Schema Validation](https://helm.sh/docs/topics/charts/#schema-files)
- [Helm Secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [External Secrets Operator](https://external-secrets.io/)
