---
name: openfeature
description: |
  OpenFeature vendor-agnostic feature flag SDK with standardized API across
  languages. Covers SDK installation, flag evaluation, providers, and hooks.
  Use when implementing feature flags, A/B testing, canary releases, or when
  user mentions OpenFeature, feature toggles, or progressive rollouts.
---

# OpenFeature SDK Integration

Vendor-agnostic feature flag SDK providing standardized API across languages and providers. Use when implementing feature flags, A/B testing, canary releases, or progressive rollouts with any feature flag backend.

## When to Use

**Automatic activation triggers:**
- User mentions "feature flags", "feature toggles", or "feature management"
- User asks about A/B testing or canary releases
- User wants to implement progressive rollouts
- Project has OpenFeature SDK dependencies
- User mentions OpenFeature, flagd, or vendor-agnostic flags

**Related skills:**
- `go-feature-flag` - Specific GO Feature Flag provider details
- `launchdarkly` - LaunchDarkly provider integration

## Core Concepts

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Code                          │
├─────────────────────────────────────────────────────────────┤
│                  OpenFeature SDK (API)                       │
│  ┌─────────────┬──────────────┬─────────────┬─────────────┐ │
│  │  getBool()  │  getString() │  getNumber()│  getObject()│ │
│  └─────────────┴──────────────┴─────────────┴─────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                       Provider                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  GO Feature Flag │ flagd │ LaunchDarkly │ Split │ etc  │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Flag Source                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │   File   │   S3   │  GitHub  │  API  │  ConfigMap      │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

1. **API** - Standardized interface for flag evaluation
2. **Provider** - Backend-specific implementation
3. **Evaluation Context** - User/request data for targeting
4. **Hooks** - Lifecycle extensions for logging, telemetry

## SDK Installation

### Node.js (Server)

```bash
# Core SDK
npm install @openfeature/server-sdk

# Providers (choose one)
npm install @openfeature/go-feature-flag-provider  # GO Feature Flag
npm install @openfeature/flagd-provider            # flagd
npm install @openfeature/in-memory-provider        # Testing
```

### Node.js (Browser/React)

```bash
# Web SDK
npm install @openfeature/web-sdk

# React integration
npm install @openfeature/react-sdk

# Web providers
npm install @openfeature/go-feature-flag-web-provider
```

### Python

```bash
uv add openfeature-sdk
uv add openfeature-provider-go-feature-flag  # GO Feature Flag provider
```

### Go

```bash
go get github.com/open-feature/go-sdk
go get github.com/open-feature/go-sdk-contrib/providers/go-feature-flag
```

### Java

```xml
<dependency>
    <groupId>dev.openfeature</groupId>
    <artifactId>sdk</artifactId>
    <version>1.7.0</version>
</dependency>
```

### Rust

```toml
[dependencies]
open-feature = "0.2"
```

## Basic Usage Patterns

### Initialization

```typescript
// TypeScript/Node.js
import { OpenFeature } from '@openfeature/server-sdk';
import { GoFeatureFlagProvider } from '@openfeature/go-feature-flag-provider';

// Initialize provider
const provider = new GoFeatureFlagProvider({
  endpoint: process.env.GOFF_RELAY_URL || 'http://localhost:1031',
});

// Set provider (awaitable for ready state)
await OpenFeature.setProviderAndWait(provider);

// Get client
const client = OpenFeature.getClient('my-app');
```

### Flag Evaluation

```typescript
// Boolean flag
const isEnabled = await client.getBooleanValue('new-feature', false);

// String flag
const buttonColor = await client.getStringValue('button-color', '#000000');

// Number flag
const maxItems = await client.getNumberValue('max-items', 10);

// Object/JSON flag
const config = await client.getObjectValue('feature-config', {});

// With evaluation context
const context = { targetingKey: userId, email: userEmail, groups: ['beta'] };
const isEnabled = await client.getBooleanValue('new-feature', false, context);
```

### Evaluation Context

```typescript
// Creating context
const context: EvaluationContext = {
  // Required: unique identifier for targeting
  targetingKey: user.id,

  // Optional: additional attributes for targeting rules
  email: user.email,
  groups: user.roles,
  plan: user.subscription,

  // Custom attributes
  country: request.geoip.country,
  browser: request.headers['user-agent'],
};

// Set global context (applies to all evaluations)
OpenFeature.setContext(context);

// Or per-evaluation context
await client.getBooleanValue('feature', false, context);
```

### Hooks

```typescript
import { Hook, HookContext, EvaluationDetails } from '@openfeature/server-sdk';

// Logging hook
const loggingHook: Hook = {
  before: (hookContext: HookContext) => {
    console.log(`Evaluating flag: ${hookContext.flagKey}`);
  },
  after: (hookContext: HookContext, details: EvaluationDetails<unknown>) => {
    console.log(`Flag ${hookContext.flagKey} = ${details.value}`);
  },
  error: (hookContext: HookContext, error: Error) => {
    console.error(`Error evaluating ${hookContext.flagKey}:`, error);
  },
};

// Register globally
OpenFeature.addHooks(loggingHook);

// Or per-client
client.addHooks(loggingHook);
```

### React Integration

```tsx
import { OpenFeatureProvider, useFlag, useBooleanFlagValue } from '@openfeature/react-sdk';
import { GoFeatureFlagWebProvider } from '@openfeature/go-feature-flag-web-provider';

// Provider setup
const provider = new GoFeatureFlagWebProvider({
  endpoint: import.meta.env.VITE_GOFF_RELAY_URL,
});

function App() {
  return (
    <OpenFeatureProvider provider={provider}>
      <MyComponent />
    </OpenFeatureProvider>
  );
}

// Using flags in components
function MyComponent() {
  // Simple boolean value
  const isEnabled = useBooleanFlagValue('new-feature', false);

  // Full flag details
  const { value, isLoading, error } = useFlag('button-color', '#000');

  if (isLoading) return <Spinner />;

  return (
    <div>
      {isEnabled && <NewFeature />}
      <Button color={value}>Click me</Button>
    </div>
  );
}
```

## Testing

### In-Memory Provider

```typescript
import { OpenFeature } from '@openfeature/server-sdk';
import { InMemoryProvider } from '@openfeature/in-memory-provider';

// Configure test flags
const testProvider = new InMemoryProvider({
  'new-feature': {
    variants: {
      on: true,
      off: false,
    },
    defaultVariant: 'off',
    disabled: false,
  },
  'button-color': {
    variants: {
      blue: '#0066CC',
      green: '#00CC66',
    },
    defaultVariant: 'blue',
    disabled: false,
  },
});

// Use in tests
beforeAll(async () => {
  await OpenFeature.setProviderAndWait(testProvider);
});

afterAll(async () => {
  await OpenFeature.close();
});
```

### Mocking in Unit Tests

```typescript
import { vi } from 'vitest';
import { OpenFeature } from '@openfeature/server-sdk';

// Mock the entire SDK
vi.mock('@openfeature/server-sdk', () => ({
  OpenFeature: {
    getClient: vi.fn().mockReturnValue({
      getBooleanValue: vi.fn().mockResolvedValue(true),
      getStringValue: vi.fn().mockResolvedValue('test-value'),
    }),
  },
}));
```

## Best Practices

### 1. Initialize Early

```typescript
// Initialize before app starts handling requests
async function bootstrap() {
  await initializeFeatureFlags();  // First
  await initializeDatabase();
  await startServer();
}
```

### 2. Use Meaningful Flag Names

```typescript
// Good: descriptive, namespaced
'checkout.new-payment-flow'
'dashboard.beta-analytics'
'api.rate-limit-v2'

// Bad: vague, unclear
'feature1'
'test-flag'
'enabled'
```

### 3. Always Provide Defaults

```typescript
// Good: safe default that works if provider fails
const isEnabled = await client.getBooleanValue('risky-feature', false);

// Consider: what's the safe behavior if flags fail?
const maxItems = await client.getNumberValue('max-items', 100); // Safe limit
```

### 4. Handle Provider Errors

```typescript
try {
  const value = await client.getBooleanValue('feature', false);
} catch (error) {
  // Log but don't crash - use default
  logger.error('Feature flag evaluation failed', { error });
  return defaultBehavior();
}
```

### 5. Clean Up Old Flags

```typescript
// Track flag usage with hooks
const flagUsageHook: Hook = {
  after: (context, details) => {
    metrics.increment(`feature_flag.${context.flagKey}.evaluations`);
  },
};

// Regularly review and remove flags with 100% rollout
// or flags that haven't been evaluated in months
```

## Documentation

- **OpenFeature Specification**: https://openfeature.dev/specification
- **SDK Reference**: https://openfeature.dev/docs/reference/concepts/evaluation-api
- **Providers List**: https://openfeature.dev/ecosystem
- **Hooks Guide**: https://openfeature.dev/docs/reference/concepts/hooks

## Related Commands

- `/configure:feature-flags` - Set up feature flag infrastructure
- `/configure:sentry` - Error tracking (for feature flag rollback monitoring)
