# GO Feature Flag Reference

Detailed reference material for GO Feature Flag (GOFF) configuration and deployment.

## Flag Type Examples

### String Flags

```yaml
# Theme selection
app-theme:
  variations:
    light: "light"
    dark: "dark"
    system: "system"
  defaultRule:
    variation: system
```

### Number Flags

```yaml
# Configuration value
rate-limit:
  variations:
    low: 100
    medium: 500
    high: 1000
  defaultRule:
    variation: medium
```

### Object/JSON Flags

```yaml
# Complex configuration
feature-config:
  variations:
    v1:
      maxItems: 10
      enableCache: true
      timeout: 5000
    v2:
      maxItems: 50
      enableCache: true
      timeout: 3000
  defaultRule:
    variation: v1
```

## Advanced Rollout Strategies

### Progressive Rollout

```yaml
api-v2:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
  experimentation:
    start: 2024-11-01T00:00:00Z
    end: 2024-12-01T00:00:00Z
    progressiveRollout:
      initial:
        variation: enabled
        percentage: 0
      end:
        variation: enabled
        percentage: 100
```

### Scheduled Changes

```yaml
holiday-theme:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
  scheduledRollout:
    - date: 2024-12-01T00:00:00Z
      variation: enabled
    - date: 2025-01-02T00:00:00Z
      variation: disabled
```

### A/B Testing

```yaml
button-color:
  variations:
    blue: "#0066CC"
    green: "#00CC66"
    red: "#CC0066"
  defaultRule:
    percentage:
      blue: 34
      green: 33
      red: 33
  experimentation:
    start: 2024-11-01T00:00:00Z
    end: 2024-11-15T00:00:00Z
```

## Kubernetes Deployment

```yaml
# k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: goff-relay
  labels:
    app: goff-relay
spec:
  replicas: 2
  selector:
    matchLabels:
      app: goff-relay
  template:
    metadata:
      labels:
        app: goff-relay
    spec:
      containers:
        - name: relay
          image: gofeatureflag/go-feature-flag:v1.25.0
          ports:
            - name: api
              containerPort: 1031
            - name: admin
              containerPort: 1032
          env:
            - name: RETRIEVER_KIND
              value: "file"
            - name: RETRIEVER_PATH
              value: "/config/flags.yaml"
          volumeMounts:
            - name: flags
              mountPath: /config
          livenessProbe:
            httpGet:
              path: /health
              port: admin
            initialDelaySeconds: 5
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: admin
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "500m"
      volumes:
        - name: flags
          configMap:
            name: feature-flags
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
data:
  flags.yaml: |
    new-feature:
      variations:
        enabled: true
        disabled: false
      defaultRule:
        variation: disabled
---
apiVersion: v1
kind: Service
metadata:
  name: goff-relay
spec:
  selector:
    app: goff-relay
  ports:
    - name: api
      port: 1031
      targetPort: api
    - name: admin
      port: 1032
      targetPort: admin
```

## Exporter Configuration

Export flag evaluation data for analytics:

```yaml
# Environment variables
EXPORTER_KIND=webhook|s3|googlecloud|kafka|pubsub|log

# Webhook exporter
EXPORTER_ENDPOINT_URL=https://analytics.example.com/events
EXPORTER_FLUSH_INTERVAL_MS=60000
EXPORTER_MAX_EVENTS_IN_MEMORY=10000

# S3 exporter
EXPORTER_BUCKET=my-analytics-bucket
EXPORTER_PATH=flag-events/
```

## Notifier Configuration

Send notifications on flag changes:

```yaml
# Slack
NOTIFIER_KIND=slack
NOTIFIER_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx

# Discord
NOTIFIER_KIND=discord
NOTIFIER_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx

# Microsoft Teams
NOTIFIER_KIND=teams
NOTIFIER_TEAMS_WEBHOOK_URL=https://outlook.office.com/webhook/xxx
```

## Best Practices: GitOps Workflow

### CI/CD Flag Deployment

```yaml
# Store flags in git, sync to S3/ConfigMap
# .github/workflows/deploy-flags.yaml
on:
  push:
    paths:
      - 'flags/**'
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate flags
        run: goff lint --config flags/production.yaml
      - name: Sync to S3
        run: aws s3 cp flags/production.yaml s3://flags-bucket/
```

### Environment-Specific Flags

```yaml
# flags/base.yaml - shared defaults
# flags/development.yaml - dev overrides
# flags/production.yaml - production config

# Use includes (if using file retriever with multiple files)
# Or separate retrievers per environment
```
