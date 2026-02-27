---
model: haiku
created: 2025-12-16
modified: 2026-02-25
reviewed: 2025-12-16
name: go-feature-flag
description: |
  GO Feature Flag (GOFF) self-hosted feature flag solution with OpenFeature
  integration. Covers flag configuration, relay proxy, targeting rules, rollouts.
  Use when user mentions GO Feature Flag, GOFF, gofeatureflag, self-hosted
  feature flags, or flags.goff.yaml configuration.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# GO Feature Flag

Open-source feature flag solution with file-based configuration and OpenFeature integration. Use when setting up self-hosted feature flags, configuring flag files, or deploying the relay proxy.

## When to Use

**Automatic activation triggers:**
- User mentions "GO Feature Flag", "GOFF", or "gofeatureflag"
- Project has `@openfeature/go-feature-flag-provider` dependency
- Project has `flags.goff.yaml` or similar flag configuration
- User asks about self-hosted feature flags
- Docker/K8s configuration includes `gofeatureflag/go-feature-flag` image

**Related skills:**
- `openfeature` - OpenFeature SDK usage patterns
- `container-development` - Docker/K8s deployment

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Application                              │
│                         │                                    │
│                   OpenFeature SDK                            │
│                         │                                    │
│              GO Feature Flag Provider                        │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                 GO Feature Flag Relay Proxy                  │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Retriever                            ││
│  │  (File, S3, GitHub, HTTP, K8s ConfigMap, etc.)         ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    Exporter                             ││
│  │  (Webhook, S3, Kafka, PubSub, etc.)                    ││
│  └─────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   Notifier                              ││
│  │  (Slack, Discord, Teams, Webhook)                      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   Flag Configuration                         │
│                    (flags.goff.yaml)                         │
└─────────────────────────────────────────────────────────────┘
```

## Flag Configuration Format

### Basic Structure

```yaml
# flags.goff.yaml
flag-name:
  variations:       # All possible values
    variation1: value1
    variation2: value2
  defaultRule:      # Rule when no targeting matches
    variation: variation1
  targeting:        # Optional: targeting rules
    - name: rule-name
      query: 'expression'
      variation: variation2
```

### Boolean Flags

```yaml
# Simple on/off flag
new-feature:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
```

For String, Number, and Object/JSON flag examples, see [REFERENCE.md](REFERENCE.md).

## Targeting Rules

### Query Syntax

GO Feature Flag uses a CEL-like query syntax for targeting:

```yaml
targeting:
  - name: beta-users
    query: 'groups co "beta"'  # contains
    variation: enabled

  - name: specific-user
    query: 'targetingKey eq "user-123"'  # equals
    variation: enabled

  - name: email-domain
    query: 'email ew "@company.com"'  # ends with
    variation: enabled

  - name: premium-tier
    query: 'plan in ["pro", "enterprise"]'  # in list
    variation: enabled
```

### Operators

| Operator | Description | Example |
|----------|-------------|---------|
| `eq` | Equals | `email eq "test@example.com"` |
| `ne` | Not equals | `plan ne "free"` |
| `co` | Contains | `groups co "admin"` |
| `sw` | Starts with | `email sw "admin"` |
| `ew` | Ends with | `email ew "@company.com"` |
| `in` | In list | `country in ["US", "CA"]` |
| `gt`, `ge`, `lt`, `le` | Comparisons | `age gt 18` |
| `and`, `or` | Logical | `plan eq "pro" and country eq "US"` |

### Priority

Rules are evaluated top-to-bottom. First matching rule wins:

```yaml
targeting:
  # Highest priority: specific user override
  - name: test-user
    query: 'targetingKey eq "test-user-id"'
    variation: enabled

  # Second: admin group
  - name: admins
    query: 'groups co "admin"'
    variation: enabled

  # Third: beta users
  - name: beta
    query: 'groups co "beta"'
    variation: enabled

  # Fallback is defaultRule
defaultRule:
  variation: disabled
```

## Rollout Strategies

### Percentage Rollout

```yaml
new-checkout:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    percentage:
      enabled: 20   # 20% of users
      disabled: 80  # 80% of users
```

For Progressive Rollout, Scheduled Changes, and A/B Testing patterns, see [REFERENCE.md](REFERENCE.md).

## Relay Proxy Configuration

### Docker Compose (Development)

```yaml
# docker-compose.yaml
services:
  goff-relay:
    image: gofeatureflag/go-feature-flag:latest
    ports:
      - "1031:1031"  # API
      - "1032:1032"  # Health/metrics
    volumes:
      - ./flags.goff.yaml:/goff/flags.yaml:ro
    environment:
      # Retriever configuration
      - RETRIEVER_KIND=file
      - RETRIEVER_PATH=/goff/flags.yaml

      # Polling interval (ms)
      - POLLING_INTERVAL_MS=10000

      # Logging
      - LOG_LEVEL=info
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:1032/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

### Environment Variables

```bash
# Retriever (choose one)
RETRIEVER_KIND=file|s3|http|github|gitlab|googlecloud|azureblob|k8s

# File retriever
RETRIEVER_PATH=/path/to/flags.yaml

# S3 retriever
RETRIEVER_BUCKET=my-bucket
RETRIEVER_ITEM=flags/production.yaml
AWS_REGION=us-east-1

# GitHub retriever
RETRIEVER_REPOSITORY_SLUG=owner/repo
RETRIEVER_FILE_PATH=flags/production.yaml
RETRIEVER_BRANCH=main
GITHUB_TOKEN=ghp_xxxx

# HTTP retriever
RETRIEVER_URL=https://api.example.com/flags.yaml
RETRIEVER_HEADERS=Authorization=Bearer xxx

# Polling
POLLING_INTERVAL_MS=30000

# Server
HTTP_PORT=1031
ADMIN_PORT=1032
LOG_LEVEL=info|debug|warn|error
```

For Kubernetes deployment configuration, see [REFERENCE.md](REFERENCE.md).

## Exporters

Export flag evaluation data for analytics. Supported kinds: `webhook`, `s3`, `googlecloud`, `kafka`, `pubsub`, `log`.

For detailed exporter environment variable configuration, see [REFERENCE.md](REFERENCE.md).

## Notifiers

Send notifications on flag changes. Supported: Slack, Discord, Microsoft Teams, Webhook.

For webhook URL configuration, see [REFERENCE.md](REFERENCE.md).

## CLI Tools

### Validate Configuration

```bash
# Install CLI
go install github.com/thomaspoignant/go-feature-flag/cmd/goff@latest

# Validate flag file
goff lint --config flags.goff.yaml

# Output format
goff lint --config flags.goff.yaml --format json
```

### Testing Flags Locally

```bash
# Start relay in foreground
docker run -p 1031:1031 -p 1032:1032 \
  -v $(pwd)/flags.goff.yaml:/goff/flags.yaml:ro \
  -e RETRIEVER_KIND=file \
  -e RETRIEVER_PATH=/goff/flags.yaml \
  gofeatureflag/go-feature-flag:latest

# Test flag evaluation
curl -X POST http://localhost:1031/v1/feature/new-feature/eval \
  -H "Content-Type: application/json" \
  -d '{"evaluationContext": {"targetingKey": "user-123"}}'
```

## Best Practices

### 1. Flag Naming Convention

```yaml
# Namespace by feature/team
checkout.new-payment-form
dashboard.beta-widgets
api.v2-endpoints

# Use consistent suffixes
*.enabled      # boolean toggles
*.config       # object/JSON config
*.percentage   # rollout percentage
```

### 2. Track Flag Lifecycle

```yaml
# Add metadata comments (YAML supports comments)
new-feature:
  # Created: 2024-11-01
  # Owner: team-checkout
  # Jira: PROJ-123
  # Target removal: 2025-01-15
  variations:
    enabled: true
    disabled: false
```

### 3. Monitor and Clean Up

- Export evaluation data to track usage
- Set up alerts for flags at 100% (ready for removal)
- Review flags quarterly for cleanup

For GitOps CI/CD workflow and environment-specific flag patterns, see [REFERENCE.md](REFERENCE.md).

## Troubleshooting

### Flag Not Evaluating Correctly

```bash
# Check relay logs
docker logs goff-relay

# Test evaluation directly
curl -X POST http://localhost:1031/v1/feature/my-flag/eval \
  -H "Content-Type: application/json" \
  -d '{"evaluationContext": {"targetingKey": "test", "email": "test@example.com"}}'
```

### Provider Connection Issues

```typescript
// Check provider initialization
const provider = new GoFeatureFlagProvider({
  endpoint: process.env.GOFF_RELAY_URL,
  timeout: 5000, // Increase timeout
});

// Handle events
provider.on('PROVIDER_READY', () => console.log('Provider ready'));
provider.on('PROVIDER_ERROR', (e) => console.error('Provider error', e));
```

### Configuration Not Updating

```bash
# Check polling interval
POLLING_INTERVAL_MS=10000  # 10 seconds

# Verify file is readable
docker exec goff-relay cat /goff/flags.yaml

# Check retriever status
curl http://localhost:1032/info
```

## Documentation

- **Official Docs**: https://gofeatureflag.org/docs
- **Flag Format**: https://gofeatureflag.org/docs/configure_flag/flag_format
- **Relay Proxy**: https://gofeatureflag.org/docs/relay-proxy
- **OpenFeature SDKs**: https://gofeatureflag.org/docs/sdk

## Related Commands

- `/configure:feature-flags` - Set up complete feature flag infrastructure
- `/configure:dockerfile` - Container configuration best practices
