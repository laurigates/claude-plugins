---
description: Check and configure feature flag infrastructure (OpenFeature + providers)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--provider <goff|flagd|launchdarkly|split>]"
---

# /configure:feature-flags

Check and configure feature flag infrastructure using the OpenFeature standard with pluggable providers.

## Context

This command validates feature flag setup and optionally configures OpenFeature with your chosen provider.

**Architecture:**
- **OpenFeature** - Vendor-agnostic API standard for feature flagging
- **Provider** - Backend implementation (GO Feature Flag, flagd, LaunchDarkly, Split, etc.)

**Recommended stack:**
- **OpenFeature SDK** - Standardized API for all languages
- **GO Feature Flag (GOFF)** - Open-source, file-based provider (preferred for self-hosted)
- **flagd** - Lightweight daemon provider for cloud-native deployments

## Version Checking

**CRITICAL**: Before configuring feature flags, verify latest SDK and provider versions:

1. **OpenFeature JS SDK**: Check [npm](https://www.npmjs.com/package/@openfeature/js-sdk)
2. **OpenFeature Python SDK**: Check [PyPI](https://pypi.org/project/openfeature-sdk/)
3. **GO Feature Flag**: Check [GitHub releases](https://github.com/thomaspoignant/go-feature-flag/releases)
4. **flagd**: Check [GitHub releases](https://github.com/open-feature/flagd/releases)

Use WebSearch or WebFetch to verify current SDK versions before configuring feature flags.

## Workflow

### Phase 1: Project Detection

Detect project language and existing feature flag setup:

| Indicator | Language | Detected Provider |
|-----------|----------|-------------------|
| `@openfeature/server-sdk` in package.json | Node.js | OpenFeature (check for provider) |
| `@openfeature/web-sdk` in package.json | Browser JS | OpenFeature Web |
| `@openfeature/react-sdk` in package.json | React | OpenFeature React |
| `openfeature-sdk` in pyproject.toml | Python | OpenFeature Python |
| `OpenFeature` in Cargo.toml | Rust | OpenFeature Rust |
| `dev.openfeature` in pom.xml/build.gradle | Java | OpenFeature Java |
| `@openfeature/go-feature-flag-provider` | Node.js | GO Feature Flag |
| `go-feature-flag-relay-proxy` in docker-compose | Any | GO Feature Flag Relay |
| `flagd` in docker-compose/k8s | Any | flagd provider |
| `launchdarkly-server-sdk` | Any | LaunchDarkly |

### Phase 2: Current State Analysis

Check for complete feature flag setup:

**OpenFeature SDK:**
- [ ] OpenFeature SDK installed for project language
- [ ] Provider package installed
- [ ] Provider initialized in application startup
- [ ] Evaluation context configured
- [ ] Hooks configured (logging, telemetry)

**GO Feature Flag (if selected):**
- [ ] Flag configuration file exists (`flags.goff.yaml` or similar)
- [ ] Relay proxy configured (for production)
- [ ] Retrievers configured (file, S3, GitHub, etc.)
- [ ] Exporters configured for analytics

**flagd (if selected):**
- [ ] flagd container/service configured
- [ ] Flag configuration source defined
- [ ] gRPC/HTTP endpoints configured

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Feature Flag Compliance Report
==============================
Project: [name]
Language: [TypeScript | Python | Go | Java | Rust]
Provider: [GO Feature Flag | flagd | LaunchDarkly | None]

OpenFeature SDK:
  SDK installed            package.json               [✅ FOUND | ❌ MISSING]
  Provider package         @openfeature/goff-provider [✅ FOUND | ❌ MISSING]
  Provider initialized     src/featureFlags.ts        [✅ CONFIGURED | ❌ MISSING]
  Evaluation context       request middleware         [✅ CONFIGURED | ⚠️ BASIC]
  Hooks configured         logging/telemetry          [✅ CONFIGURED | ⏭️ OPTIONAL]

Provider Configuration:
  Flag file                flags.goff.yaml            [✅ EXISTS | ❌ MISSING]
  Environment targeting    targeting rules            [✅ CONFIGURED | ⚠️ BASIC]
  Default values           fallback handling          [✅ CONFIGURED | ❌ MISSING]

Infrastructure:
  Relay proxy              docker-compose.yaml        [✅ CONFIGURED | ⏭️ OPTIONAL]
  Health checks            /health endpoint           [✅ CONFIGURED | ⚠️ MISSING]
  Metrics/Export           telemetry exporter         [✅ CONFIGURED | ⏭️ OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Install OpenFeature SDK and provider package
  - Create flag configuration file with example flags
  - Add evaluation context middleware
```

### Phase 4: Configuration (if --fix or user confirms)

#### Node.js / TypeScript (Server-Side)

**Install dependencies:**
```bash
# OpenFeature SDK
npm install @openfeature/server-sdk

# GO Feature Flag provider (recommended)
npm install @openfeature/go-feature-flag-provider

# OR flagd provider
npm install @openfeature/flagd-provider

# OR in-memory provider for development
npm install @openfeature/in-memory-provider
```

**Create `src/featureFlags.ts`:**
```typescript
import { OpenFeature, EvaluationContext } from '@openfeature/server-sdk';
import { GoFeatureFlagProvider } from '@openfeature/go-feature-flag-provider';

// Initialize OpenFeature with GO Feature Flag provider
export async function initializeFeatureFlags(): Promise<void> {
  const provider = new GoFeatureFlagProvider({
    endpoint: process.env.GOFF_RELAY_URL || 'http://localhost:1031',
    // For local development without relay proxy:
    // flagConfigPath: './flags.goff.yaml',
  });

  await OpenFeature.setProviderAndWait(provider);
}

// Get feature flag client
export function getFeatureFlagClient(name = 'default') {
  return OpenFeature.getClient(name);
}

// Helper for creating evaluation context from request
export function createEvaluationContext(user?: {
  id: string;
  email?: string;
  groups?: string[];
  attributes?: Record<string, unknown>;
}): EvaluationContext {
  if (!user) {
    return { targetingKey: 'anonymous' };
  }

  return {
    targetingKey: user.id,
    email: user.email,
    groups: user.groups,
    ...user.attributes,
  };
}

// Usage example:
// const client = getFeatureFlagClient();
// const context = createEvaluationContext({ id: user.id, email: user.email });
// const isEnabled = await client.getBooleanValue('new-feature', false, context);
```

**Create `src/middleware/featureFlags.ts` (Express example):**
```typescript
import { Request, Response, NextFunction } from 'express';
import { getFeatureFlagClient, createEvaluationContext } from '../featureFlags';

declare global {
  namespace Express {
    interface Request {
      featureFlags: ReturnType<typeof getFeatureFlagClient>;
      evaluationContext: ReturnType<typeof createEvaluationContext>;
    }
  }
}

export function featureFlagMiddleware() {
  return (req: Request, _res: Response, next: NextFunction) => {
    req.featureFlags = getFeatureFlagClient();
    req.evaluationContext = createEvaluationContext(
      req.user ? {
        id: req.user.id,
        email: req.user.email,
        groups: req.user.roles,
      } : undefined
    );
    next();
  };
}
```

#### React (Client-Side)

**Install dependencies:**
```bash
npm install @openfeature/react-sdk @openfeature/web-sdk @openfeature/go-feature-flag-web-provider
```

**Create `src/providers/FeatureFlagProvider.tsx`:**
```tsx
import { OpenFeatureProvider, useFlag } from '@openfeature/react-sdk';
import { GoFeatureFlagWebProvider } from '@openfeature/go-feature-flag-web-provider';

const provider = new GoFeatureFlagWebProvider({
  endpoint: import.meta.env.VITE_GOFF_RELAY_URL || 'http://localhost:1031',
});

export function FeatureFlagProvider({ children }: { children: React.ReactNode }) {
  return (
    <OpenFeatureProvider provider={provider}>
      {children}
    </OpenFeatureProvider>
  );
}

// Usage in components:
// const { value: isEnabled } = useFlag('new-feature', false);
export { useFlag };
```

#### Python

**Install dependencies:**
```bash
uv add openfeature-sdk openfeature-provider-go-feature-flag
```

**Create `src/feature_flags.py`:**
```python
from openfeature import api
from openfeature.provider.go_feature_flag import GoFeatureFlagProvider
from openfeature.evaluation_context import EvaluationContext
import os


def initialize_feature_flags() -> None:
    """Initialize OpenFeature with GO Feature Flag provider."""
    provider = GoFeatureFlagProvider(
        endpoint=os.getenv("GOFF_RELAY_URL", "http://localhost:1031"),
    )
    api.set_provider(provider)


def get_client(name: str = "default"):
    """Get feature flag client."""
    return api.get_client(name)


def create_evaluation_context(
    user_id: str | None = None,
    email: str | None = None,
    groups: list[str] | None = None,
    **attributes,
) -> EvaluationContext:
    """Create evaluation context from user info."""
    return EvaluationContext(
        targeting_key=user_id or "anonymous",
        attributes={
            "email": email,
            "groups": groups or [],
            **attributes,
        },
    )


# Usage example:
# client = get_client()
# context = create_evaluation_context(user_id="123", email="user@example.com")
# is_enabled = client.get_boolean_value("new-feature", False, context)
```

#### Go

**Install dependencies:**
```bash
go get github.com/open-feature/go-sdk
go get github.com/open-feature/go-sdk-contrib/providers/go-feature-flag
```

**Create `pkg/featureflags/featureflags.go`:**
```go
package featureflags

import (
    "context"
    "os"

    "github.com/open-feature/go-sdk/openfeature"
    gofeatureflag "github.com/open-feature/go-sdk-contrib/providers/go-feature-flag/pkg"
)

func Initialize() error {
    endpoint := os.Getenv("GOFF_RELAY_URL")
    if endpoint == "" {
        endpoint = "http://localhost:1031"
    }

    provider, err := gofeatureflag.NewProvider(gofeatureflag.ProviderOptions{
        Endpoint: endpoint,
    })
    if err != nil {
        return err
    }

    return openfeature.SetProviderAndWait(provider)
}

func GetClient(name string) openfeature.Client {
    if name == "" {
        name = "default"
    }
    return *openfeature.NewClient(name)
}

func CreateContext(userID, email string, groups []string) openfeature.EvaluationContext {
    return openfeature.NewEvaluationContext(
        userID,
        map[string]interface{}{
            "email":  email,
            "groups": groups,
        },
    )
}
```

### Phase 5: Flag Configuration

Create flag configuration file for GO Feature Flag:

**Create `flags.goff.yaml`:**
```yaml
# Feature Flags Configuration
# Documentation: https://gofeatureflag.org/docs/configure_flag/flag_format

# Example: Simple boolean flag
new-dashboard:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
  targeting:
    - name: beta-users
      query: 'groups co "beta"'
      variation: enabled

# Example: Percentage rollout
new-checkout-flow:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    percentage:
      enabled: 20
      disabled: 80

# Example: Multi-variant flag (A/B test)
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

# Example: Environment-specific flag
debug-mode:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
  targeting:
    - name: development
      query: 'env eq "development"'
      variation: enabled

# Example: User-specific override
admin-features:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    variation: disabled
  targeting:
    - name: admins
      query: 'groups co "admin"'
      variation: enabled

# Example: Scheduled rollout
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

# Example: Progressive rollout
new-api-v2:
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

### Phase 6: Infrastructure (Optional - Production)

**Create `docker-compose.yaml` (for relay proxy):**
```yaml
services:
  goff-relay:
    image: gofeatureflag/go-feature-flag:latest
    ports:
      - "1031:1031"  # API
      - "1032:1032"  # Health/metrics
    volumes:
      - ./flags.goff.yaml:/goff/flags.yaml:ro
    environment:
      # Local file retriever
      - RETRIEVER_KIND=file
      - RETRIEVER_PATH=/goff/flags.yaml
      # Poll interval for flag updates
      - POLLING_INTERVAL_MS=10000
      # Optional: Export to webhook/analytics
      # - EXPORTER_KIND=webhook
      # - EXPORTER_ENDPOINT=http://analytics:8080/events
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:1032/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

**Kubernetes deployment (`k8s/goff-relay.yaml`):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: goff-relay
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
        - name: goff-relay
          image: gofeatureflag/go-feature-flag:latest
          ports:
            - containerPort: 1031
            - containerPort: 1032
          env:
            - name: RETRIEVER_KIND
              value: "configmap"
            - name: RETRIEVER_CONFIGMAP_NAME
              value: "feature-flags"
            - name: RETRIEVER_CONFIGMAP_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          livenessProbe:
            httpGet:
              path: /health
              port: 1032
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /health
              port: 1032
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
    - name: health
      port: 1032
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
data:
  flags.yaml: |
    # Your flag configuration here
```

### Phase 7: Testing Configuration

**Create `tests/featureFlags.test.ts`:**
```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { OpenFeature } from '@openfeature/server-sdk';
import { InMemoryProvider } from '@openfeature/in-memory-provider';

describe('Feature Flags', () => {
  beforeAll(async () => {
    // Use in-memory provider for tests
    const testProvider = new InMemoryProvider({
      'new-feature': {
        variants: { on: true, off: false },
        defaultVariant: 'off',
        disabled: false,
      },
      'button-color': {
        variants: { blue: '#0066CC', green: '#00CC66' },
        defaultVariant: 'blue',
        disabled: false,
      },
    });
    await OpenFeature.setProviderAndWait(testProvider);
  });

  afterAll(async () => {
    await OpenFeature.close();
  });

  it('should evaluate boolean flag', async () => {
    const client = OpenFeature.getClient();
    const value = await client.getBooleanValue('new-feature', false);
    expect(value).toBe(false); // default variant is 'off'
  });

  it('should evaluate string flag', async () => {
    const client = OpenFeature.getClient();
    const value = await client.getStringValue('button-color', '#000000');
    expect(value).toBe('#0066CC'); // default variant is 'blue'
  });

  it('should use fallback for missing flag', async () => {
    const client = OpenFeature.getClient();
    const value = await client.getBooleanValue('non-existent', true);
    expect(value).toBe(true); // fallback value
  });
});
```

### Phase 8: CI/CD Integration

**Add environment variable to CI:**
```yaml
env:
  GOFF_RELAY_URL: ${{ secrets.GOFF_RELAY_URL }}
```

**Add flag validation step:**
```yaml
- name: Validate feature flags
  run: |
    # Install goff CLI
    go install github.com/thomaspoignant/go-feature-flag/cmd/goff@latest

    # Validate flag configuration
    goff lint --config flags.goff.yaml
```

### Phase 9: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  feature_flags: "2025.1"
  feature_flags_sdk: "openfeature"
  feature_flags_provider: "[goff|flagd|launchdarkly]"
  feature_flags_config: true
  feature_flags_relay: true  # if applicable
```

### Phase 10: Updated Compliance Report

```
Feature Flag Configuration Complete
=====================================

SDK: OpenFeature (vendor-agnostic standard)
Provider: GO Feature Flag (self-hosted)
Language: TypeScript

Configuration Applied:
  ✅ OpenFeature SDK installed
  ✅ GO Feature Flag provider configured
  ✅ Feature flag client wrapper created
  ✅ Evaluation context helper added
  ✅ Express middleware configured

Flag Configuration:
  ✅ flags.goff.yaml created with examples
  ✅ Boolean, percentage, and targeting examples
  ✅ Scheduled rollout example included

Infrastructure:
  ✅ Docker Compose for local development
  ⏭️ Kubernetes manifests (run with --k8s for production)

Testing:
  ✅ In-memory provider for tests
  ✅ Example test file created

Next Steps:
  1. Start relay proxy:
     docker-compose up goff-relay

  2. Initialize in your app:
     import { initializeFeatureFlags } from './featureFlags';
     await initializeFeatureFlags();

  3. Use flags in code:
     const client = getFeatureFlagClient();
     const isEnabled = await client.getBooleanValue('new-feature', false, context);

  4. Add new flags:
     Edit flags.goff.yaml and restart relay (or use S3/GitHub retriever)

Documentation:
  - OpenFeature: https://openfeature.dev/docs
  - GO Feature Flag: https://gofeatureflag.org/docs
  - Skill: openfeature, go-feature-flag
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--provider <provider>` | Override provider detection (goff, flagd, launchdarkly, split) |

## Examples

```bash
# Check compliance and offer fixes
/configure:feature-flags

# Check only, no modifications
/configure:feature-flags --check-only

# Auto-fix with GO Feature Flag provider
/configure:feature-flags --fix --provider goff

# Configure for LaunchDarkly
/configure:feature-flags --fix --provider launchdarkly
```

## Error Handling

- **No package manager found**: Cannot install SDK, provide manual steps
- **Provider not supported**: List supported providers, suggest alternatives
- **Relay proxy unreachable**: Check Docker/K8s configuration
- **Invalid flag syntax**: Validate with `goff lint` before deployment

## See Also

- `/configure:all` - Run all FVH compliance checks
- `/configure:sentry` - Error tracking (often used with feature flags for rollback)
- **Skills**: `openfeature`, `go-feature-flag`
- **OpenFeature documentation**: https://openfeature.dev
- **GO Feature Flag documentation**: https://gofeatureflag.org
