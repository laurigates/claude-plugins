---
created: 2025-12-16
modified: 2026-10-05
reviewed: 2026-04-25
name: go-feature-flag
description: GO Feature Flag (GOFF) self-hosted feature flags with OpenFeature integration — config, relay proxy, targeting, rollouts. Use when working with GOFF or flags.goff.yaml.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# GO Feature Flag

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| You need GOFF-specific configuration — `flags.goff.yaml`, relay proxy, targeting rules | You only need the vendor-agnostic OpenFeature SDK API — use `openfeature` |
| You are deploying or operating the self-hosted GOFF backend | You want to scaffold the full feature-flag stack including provider selection — use `configure-feature-flags` |
| Another skill needs the canonical GOFF flag-file shape | You are evaluating which feature-flag provider to adopt — start with `configure-feature-flags` |

Open-source feature flag solution with file-based configuration and OpenFeature integration. Use when setting up self-hosted feature flags, configuring flag files, or deploying the relay proxy.

### Activation triggers

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

The relay serves the API on port 1031 and health/metrics on 1032. Choose a retriever with `RETRIEVER_KIND` (`file`, `s3`, `http`, `github`, `gitlab`, `googlecloud`, `azureblob`, `k8s`) and tune refresh with `POLLING_INTERVAL_MS`.

For the Docker Compose service definition and the full retriever/polling/server environment variables, see [references/relay-proxy.md](references/relay-proxy.md) — read it when standing up or reconfiguring the relay.

For Kubernetes deployment configuration, see [REFERENCE.md](REFERENCE.md).

## Exporters

Export flag evaluation data for analytics. Supported kinds: `webhook`, `s3`, `googlecloud`, `kafka`, `pubsub`, `log`.

For detailed exporter environment variable configuration, see [REFERENCE.md](REFERENCE.md).

## Notifiers

Send notifications on flag changes. Supported: Slack, Discord, Microsoft Teams, Webhook.

For webhook URL configuration, see [REFERENCE.md](REFERENCE.md).

## CLI Tools

Validate flag files with `goff lint --config flags.goff.yaml` and test evaluation against a local relay via `POST /v1/feature/<flag>/eval`. Install commands, the `docker run` invocation, and the `curl` evaluation call are in [references/cli-and-troubleshooting.md](references/cli-and-troubleshooting.md).

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

For diagnostic commands covering flags not evaluating correctly, provider connection issues (timeout and `PROVIDER_READY`/`PROVIDER_ERROR` events), and configuration not updating, see [references/cli-and-troubleshooting.md](references/cli-and-troubleshooting.md#troubleshooting) — read it when a flag misbehaves at runtime.

## Documentation

- **Official Docs**: https://gofeatureflag.org/docs
- **Flag Format**: https://gofeatureflag.org/docs/configure_flag/flag_format
- **Relay Proxy**: https://gofeatureflag.org/docs/relay-proxy
- **OpenFeature SDKs**: https://gofeatureflag.org/docs/sdk

## Related Commands

- `/configure:feature-flags` - Set up complete feature flag infrastructure
- `/configure:dockerfile` - Container configuration best practices
