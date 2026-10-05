# Testing with OpenFeature

Read when writing tests for flag-gated code: in-memory provider fixtures or mocking the SDK in unit tests.

## In-Memory Provider

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

## Mocking in Unit Tests

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
