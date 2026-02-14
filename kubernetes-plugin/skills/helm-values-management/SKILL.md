---
model: haiku
created: 2025-12-16
modified: 2026-02-06
reviewed: 2025-12-16
name: helm-values-management
description: |
  Manage Helm values across environments with override precedence, multi-environment
  configurations, and secret management. Covers values files, --set, --set-string,
  values schema validation. Use when user mentions Helm values, environment-specific
  configs, values.yaml, --set overrides, or Helm configuration.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
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
```

### View Deployed Values

```bash
# Get values used in deployed release
helm get values <release> --namespace <namespace>

# Get ALL values (including defaults)
helm get values <release> --namespace <namespace> --all

# Get values in different formats
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
  --set-string version="1.0"

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
```

### Setting Values via CLI

```bash
# Simple value
--set name=myapp

# Nested value (use dot notation)
--set image.tag=v2.0.0
--set ingress.annotations."cert-manager\.io/cluster-issuer"=letsencrypt

# List values (use array index or {})
--set tags={api,web,prod}

# Complex JSON structures
--set-json 'nodeSelector={"disk":"ssd","region":"us-west"}'

# Force string (prevents numeric conversion)
--set-string version="1.0"

# Read value from file
--set-file cert=./tls.crt
```

## Value Validation & Testing

### Template with Values

```bash
# Render templates with values
helm template myapp ./chart --values values.yaml

# Validate against Kubernetes API
helm install myapp ./chart \
  --values values.yaml \
  --dry-run --validate
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
helm template myapp ./chart --set image.tag=test

# Test with full production values
helm template myapp ./chart \
  -f values/common.yaml \
  -f values/production.yaml
```

For detailed environment value examples, schema validation JSON, secret management options, template value handling patterns, best practices, and troubleshooting, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View values (JSON) | `helm get values <release> -n <ns> -o json` |
| All values (JSON) | `helm get values <release> -n <ns> --all -o json` |
| Computed values | `helm template myapp ./chart -f values.yaml --debug 2>&1 \| grep -A 50 "COMPUTED VALUES"` |
| Validate schema | `helm install myapp ./chart -f values.yaml --dry-run 2>&1 \| head -50` |

## Related Skills

- **Helm Release Management** - Using values during install/upgrade
- **Helm Debugging** - Troubleshooting value errors
- **Helm Chart Development** - Creating charts with good value design

## References

- [Helm Values Files](https://helm.sh/docs/chart_template_guide/values_files/)
- [Helm Schema Validation](https://helm.sh/docs/topics/charts/#schema-files)
- [Helm Secrets Plugin](https://github.com/jkroepke/helm-secrets)
- [External Secrets Operator](https://external-secrets.io/)
