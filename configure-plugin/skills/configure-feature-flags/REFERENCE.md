# configure-feature-flags Reference

Code templates, flag configuration patterns, and infrastructure manifests for feature flag setup.

## Node.js / TypeScript (Server-Side)

### Install Dependencies

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

### Feature Flag Client (`src/featureFlags.ts`)

```typescript
import { OpenFeature, EvaluationContext } from '@openfeature/server-sdk';
import { GoFeatureFlagProvider } from '@openfeature/go-feature-flag-provider';

export async function initializeFeatureFlags(): Promise<void> {
  const provider = new GoFeatureFlagProvider({
    endpoint: process.env.GOFF_RELAY_URL || 'http://localhost:1031',
  });

  await OpenFeature.setProviderAndWait(provider);
}

export function getFeatureFlagClient(name = 'default') {
  return OpenFeature.getClient(name);
}

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
```

### Express Middleware (`src/middleware/featureFlags.ts`)

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

## React (Client-Side)

### Install Dependencies

```bash
npm install @openfeature/react-sdk @openfeature/web-sdk @openfeature/go-feature-flag-web-provider
```

### Provider Component (`src/providers/FeatureFlagProvider.tsx`)

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

export { useFlag };
```

## Python

### Install Dependencies

```bash
uv add openfeature-sdk openfeature-provider-go-feature-flag
```

### Feature Flag Client (`src/feature_flags.py`)

```python
from openfeature import api
from openfeature.provider.go_feature_flag import GoFeatureFlagProvider
from openfeature.evaluation_context import EvaluationContext
import os


def initialize_feature_flags() -> None:
    provider = GoFeatureFlagProvider(
        endpoint=os.getenv("GOFF_RELAY_URL", "http://localhost:1031"),
    )
    api.set_provider(provider)


def get_client(name: str = "default"):
    return api.get_client(name)


def create_evaluation_context(
    user_id: str | None = None,
    email: str | None = None,
    groups: list[str] | None = None,
    **attributes,
) -> EvaluationContext:
    return EvaluationContext(
        targeting_key=user_id or "anonymous",
        attributes={
            "email": email,
            "groups": groups or [],
            **attributes,
        },
    )
```

## Go

### Install Dependencies

```bash
go get github.com/open-feature/go-sdk
go get github.com/open-feature/go-sdk-contrib/providers/go-feature-flag
```

### Feature Flag Client (`pkg/featureflags/featureflags.go`)

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

## Flag Configuration (`flags.goff.yaml`)

```yaml
# Feature Flags Configuration
# Documentation: https://gofeatureflag.org/docs/configure_flag/flag_format

# Simple boolean flag
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

# Percentage rollout
new-checkout-flow:
  variations:
    enabled: true
    disabled: false
  defaultRule:
    percentage:
      enabled: 20
      disabled: 80

# Multi-variant flag (A/B test)
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

# Environment-specific flag
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

# User-specific override
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

# Scheduled rollout
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

# Progressive rollout
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

## Infrastructure

### Docker Compose (Relay Proxy)

```yaml
services:
  goff-relay:
    image: gofeatureflag/go-feature-flag:latest
    ports:
      - "1031:1031"
      - "1032:1032"
    volumes:
      - ./flags.goff.yaml:/goff/flags.yaml:ro
    environment:
      - RETRIEVER_KIND=file
      - RETRIEVER_PATH=/goff/flags.yaml
      - POLLING_INTERVAL_MS=10000
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:1032/health"]
      interval: 10s
      timeout: 5s
      retries: 3
```

### Kubernetes Deployment

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
```

## Testing Configuration

### In-Memory Provider Test (`tests/featureFlags.test.ts`)

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { OpenFeature } from '@openfeature/server-sdk';
import { InMemoryProvider } from '@openfeature/in-memory-provider';

describe('Feature Flags', () => {
  beforeAll(async () => {
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
    expect(value).toBe(false);
  });

  it('should evaluate string flag', async () => {
    const client = OpenFeature.getClient();
    const value = await client.getStringValue('button-color', '#000000');
    expect(value).toBe('#0066CC');
  });

  it('should use fallback for missing flag', async () => {
    const client = OpenFeature.getClient();
    const value = await client.getBooleanValue('non-existent', true);
    expect(value).toBe(true);
  });
});
```

## CI/CD Integration

### Environment Variable

```yaml
env:
  GOFF_RELAY_URL: ${{ secrets.GOFF_RELAY_URL }}
```

### Flag Validation Step

```yaml
- name: Validate feature flags
  run: |
    go install github.com/thomaspoignant/go-feature-flag/cmd/goff@latest
    goff lint --config flags.goff.yaml
```
