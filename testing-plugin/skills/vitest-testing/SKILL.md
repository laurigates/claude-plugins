---
name: Vitest Testing
description: |
  Vitest test runner for JavaScript and TypeScript. Fast, modern alternative to Jest.
  Vite-native, ESM support, watch mode, UI mode, coverage, mocking, snapshot testing.
  Use when setting up tests for Vite projects, migrating from Jest, or needing fast test execution.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Vitest Testing

Vitest is a modern test runner designed for Vite projects. It's fast, ESM-native, and provides a Jest-compatible API with better TypeScript support and instant HMR-powered watch mode.

## Core Expertise

**What is Vitest?**
- **Vite-native**: Reuses Vite config, transforms, and plugins
- **Fast**: Instant feedback with HMR-powered watch mode
- **Jest-compatible**: Drop-in replacement with similar API
- **TypeScript**: First-class TypeScript support
- **ESM**: Native ESM support, no transpilation needed

**Key Capabilities**
- Unit and integration testing
- Mocking (functions, modules, timers, globals)
- Snapshot testing
- Coverage reporting (v8 or istanbul)
- Watch mode with instant feedback
- UI mode with visual test browser
- Parallel test execution
- Built-in benchmarking

## Installation

```bash
# Core Vitest
bun add --dev vitest

# TypeScript support (usually automatic)
bun add --dev @vitest/ui

# Coverage (choose one)
bun add --dev @vitest/coverage-v8      # Recommended (faster)
bun add --dev @vitest/coverage-istanbul

# DOM testing
bun add --dev happy-dom
# or
bun add --dev jsdom

# Verify installation
bunx vitest --version
```

## Configuration (vitest.config.ts)

### Minimal Setup

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
  },
});
```

### Recommended Production Setup

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node', // or 'happy-dom' for browser-like environment
    setupFiles: ['./test/setup.ts'],
    include: ['**/*.{test,spec}.{js,ts,jsx,tsx}'],
    exclude: ['node_modules', 'dist', 'build', '.next'],
    coverage: {
      provider: 'v8', // or 'istanbul'
      reporter: ['text', 'json', 'html', 'lcov'],
      exclude: [
        'node_modules/',
        'test/',
        '**/*.config.{js,ts}',
        '**/*.d.ts',
      ],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },
    testTimeout: 10000,
    mockReset: true,
    restoreMocks: true,
    clearMocks: true,
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

### With Vite Project

```typescript
// vitest.config.ts
import { defineConfig, mergeConfig } from 'vitest/config';
import viteConfig from './vite.config';

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      globals: true,
      environment: 'happy-dom',
      setupFiles: ['./test/setup.ts'],
      coverage: {
        provider: 'v8',
        reporter: ['text', 'html'],
      },
    },
  })
);
```

## Essential Commands

```bash
# Run all tests
bunx vitest

# Run tests once (CI mode)
bunx vitest run

# Watch mode (default)
bunx vitest watch

# UI mode
bunx vitest --ui

# Coverage
bunx vitest --coverage

# Run specific tests
bunx vitest src/utils.test.ts

# Filter tests by name
bunx vitest -t "should add numbers"

# Run related tests (changed files)
bunx vitest related src/utils.ts

# Update snapshots
bunx vitest -u

# Benchmarks
bunx vitest bench
```

## Writing Tests

### Basic Test Structure

```typescript
// src/math.test.ts
import { describe, it, expect } from 'vitest';
import { add, multiply } from './math';

describe('math utils', () => {
  it('should add two numbers', () => {
    expect(add(2, 3)).toBe(5);
  });

  it('should multiply two numbers', () => {
    expect(multiply(2, 3)).toBe(6);
  });
});
```

### Assertions

```typescript
import { expect, test } from 'vitest';

test('assertions', () => {
  // Equality
  expect(2 + 2).toBe(4);
  expect({ a: 1 }).toEqual({ a: 1 });
  expect([1, 2]).toStrictEqual([1, 2]);

  // Truthiness
  expect(true).toBeTruthy();
  expect(false).toBeFalsy();
  expect(null).toBeNull();
  expect(undefined).toBeUndefined();

  // Numbers
  expect(10).toBeGreaterThan(5);
  expect(5).toBeLessThan(10);
  expect(0.1 + 0.2).toBeCloseTo(0.3);

  // Strings
  expect('hello world').toMatch(/world/);
  expect('hello').toContain('ell');

  // Arrays/Iterables
  expect([1, 2, 3]).toContain(2);
  expect([1, 2, 3]).toHaveLength(3);

  // Objects
  expect({ a: 1, b: 2 }).toHaveProperty('a');
  expect({ a: 1, b: 2 }).toMatchObject({ a: 1 });

  // Errors
  expect(() => {
    throw new Error('oops');
  }).toThrow('oops');
});
```

### Async Tests

```typescript
import { test, expect } from 'vitest';

// Async/await
test('async test', async () => {
  const data = await fetchData();
  expect(data).toBe('expected');
});

// Promise chaining
test('promise test', () => {
  return fetchData().then((data) => {
    expect(data).toBe('expected');
  });
});

// Resolves/Rejects
test('promise resolves', async () => {
  await expect(fetchData()).resolves.toBe('expected');
});

test('promise rejects', async () => {
  await expect(fetchBadData()).rejects.toThrow('error');
});
```

## Mocking

### Mock Functions

```typescript
import { vi, test, expect } from 'vitest';

test('mock function', () => {
  const mockFn = vi.fn();

  mockFn('hello');
  mockFn('world');

  expect(mockFn).toHaveBeenCalledTimes(2);
  expect(mockFn).toHaveBeenCalledWith('hello');
  expect(mockFn).toHaveBeenLastCalledWith('world');
});

// Mock implementation
test('mock implementation', () => {
  const mockFn = vi.fn((x: number) => x * 2);

  expect(mockFn(5)).toBe(10);
  expect(mockFn).toHaveBeenCalledWith(5);
});

// Mock return values
test('mock return values', () => {
  const mockFn = vi.fn();

  mockFn.mockReturnValue(42);
  expect(mockFn()).toBe(42);

  mockFn.mockReturnValueOnce(1).mockReturnValueOnce(2);
  expect(mockFn()).toBe(1);
  expect(mockFn()).toBe(2);
  expect(mockFn()).toBe(42); // Returns default
});
```

### Mock Modules

```typescript
import { vi, beforeEach, test, expect } from 'vitest';

// Mock entire module
vi.mock('./api', () => ({
  fetchUser: vi.fn(() => Promise.resolve({ id: 1, name: 'John' })),
  createUser: vi.fn(),
}));

import { fetchUser, createUser } from './api';

beforeEach(() => {
  vi.clearAllMocks();
});

test('uses mocked api', async () => {
  const user = await fetchUser(1);
  expect(user).toEqual({ id: 1, name: 'John' });
  expect(fetchUser).toHaveBeenCalledWith(1);
});
```

### Partial Mocking

```typescript
import { vi, test, expect } from 'vitest';

// Mock only specific exports
vi.mock('./utils', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    add: vi.fn(() => 999), // Mock only 'add'
  };
});

import { add, multiply } from './utils';

test('partial mock', () => {
  expect(add(1, 2)).toBe(999); // Mocked
  expect(multiply(2, 3)).toBe(6); // Real implementation
});
```

### Mock Timers

```typescript
import { vi, beforeEach, afterEach, test, expect } from 'vitest';

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.restoreAllMocks();
});

test('timer mocking', () => {
  const callback = vi.fn();

  setTimeout(callback, 1000);
  expect(callback).not.toHaveBeenCalled();

  vi.advanceTimersByTime(1000);
  expect(callback).toHaveBeenCalledTimes(1);
});

test('fast-forward time', () => {
  const callback = vi.fn();

  setInterval(callback, 1000);

  vi.advanceTimersByTime(3500);
  expect(callback).toHaveBeenCalledTimes(3);
});
```

### Mock Globals

```typescript
import { vi, test, expect } from 'vitest';

test('mock fetch', async () => {
  global.fetch = vi.fn(() =>
    Promise.resolve({
      json: () => Promise.resolve({ data: 'mocked' }),
    })
  );

  const response = await fetch('https://api.example.com');
  const data = await response.json();

  expect(data).toEqual({ data: 'mocked' });
  expect(fetch).toHaveBeenCalledWith('https://api.example.com');
});
```

## Snapshot Testing

```typescript
import { test, expect } from 'vitest';

test('snapshot test', () => {
  const data = {
    id: 1,
    name: 'John',
    email: 'john@example.com',
  };

  expect(data).toMatchSnapshot();
});

// Inline snapshots
test('inline snapshot', () => {
  const result = add(2, 3);
  expect(result).toMatchInlineSnapshot('5');
});

// Update snapshots with: bunx vitest -u
```

## Coverage

### v8 Provider (Recommended)

```bash
# Install
bun add --dev @vitest/coverage-v8

# Run with coverage
bunx vitest --coverage
```

**Configuration:**
```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.ts'],
      exclude: [
        'node_modules/',
        'test/',
        '**/*.config.ts',
        '**/*.d.ts',
      ],
      thresholds: {
        lines: 80,
        functions: 80,
        branches: 80,
        statements: 80,
      },
    },
  },
});
```

### Istanbul Provider

```bash
# Install
bun add --dev @vitest/coverage-istanbul

# Run with coverage
bunx vitest --coverage
```

**When to use:**
- ✅ Need specific Istanbul features
- ✅ Migrating from Jest (Istanbul is default)
- ⚠️ Slower than v8

## Watch Mode

```bash
# Start watch mode (default)
bunx vitest

# Commands in watch mode:
# - r: rerun all tests
# - f: rerun only failed tests
# - u: update snapshots
# - p: filter by filename
# - t: filter by test name
# - q: quit
```

**Configuration:**
```typescript
export default defineConfig({
  test: {
    watch: true,
    watchExclude: ['node_modules/**', 'dist/**'],
  },
});
```

## UI Mode

```bash
# Start UI mode
bunx vitest --ui

# Opens browser at http://localhost:51204
```

**Features:**
- Visual test browser
- Click to run specific tests
- View test results and logs
- Filter and search tests
- Inspect coverage

## Setup Files

```typescript
// test/setup.ts
import { beforeAll, afterAll, beforeEach, afterEach } from 'vitest';

beforeAll(() => {
  // Setup once before all tests
  console.log('Starting tests');
});

afterAll(() => {
  // Cleanup once after all tests
  console.log('Tests complete');
});

beforeEach(() => {
  // Setup before each test
  vi.clearAllMocks();
});

afterEach(() => {
  // Cleanup after each test
  vi.restoreAllMocks();
});
```

**Reference in config:**
```typescript
export default defineConfig({
  test: {
    setupFiles: ['./test/setup.ts'],
  },
});
```

## Migration from Jest

### API Compatibility

Vitest provides a Jest-compatible API:

```typescript
// Works in both Jest and Vitest
import { describe, it, expect, beforeEach, afterEach } from 'vitest';

describe('my tests', () => {
  beforeEach(() => {
    // Setup
  });

  it('should work', () => {
    expect(true).toBe(true);
  });
});
```

### Migration Steps

1. **Replace Jest with Vitest:**
```bash
bun remove jest @types/jest
bun add --dev vitest
```

2. **Update scripts in package.json:**
```json
{
  "scripts": {
    "test": "vitest",
    "test:ci": "vitest run",
    "test:coverage": "vitest --coverage"
  }
}
```

3. **Convert jest.config.js to vitest.config.ts:**
```typescript
// jest.config.js → vitest.config.ts
export default defineConfig({
  test: {
    globals: true,
    environment: 'jsdom', // was testEnvironment in Jest
    setupFiles: ['./test/setup.ts'], // was setupFilesAfterEnv
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
    },
  },
});
```

4. **Update imports:**
```typescript
// Before (Jest)
import { describe, it, expect } from '@jest/globals';

// After (Vitest)
import { describe, it, expect } from 'vitest';
```

5. **Update mocking syntax:**
```typescript
// Jest
jest.mock('./api');
const mockFn = jest.fn();

// Vitest
vi.mock('./api');
const mockFn = vi.fn();
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Test
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Run tests
        run: bunx vitest run --coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          files: ./coverage/lcov.info
```

### GitLab CI

```yaml
test:
  image: oven/bun:latest
  stage: test
  script:
    - bun install --frozen-lockfile
    - bunx vitest run --coverage
  coverage: '/Lines\s*:\s*(\d+\.\d+)%/'
  artifacts:
    reports:
      coverage_report:
        coverage_format: cobertura
        path: coverage/cobertura-coverage.xml
```

## Troubleshooting

### Tests Not Running

```bash
# Verify config is detected
bunx vitest --config vitest.config.ts

# Check test file patterns
bunx vitest --reporter=verbose

# Debug configuration
bunx vitest --help
```

### ESM Import Errors

```typescript
// vitest.config.ts
export default defineConfig({
  test: {
    environment: 'node',
    globals: true,
  },
  resolve: {
    conditions: ['import', 'node'],
  },
});
```

### Coverage Thresholds Failing

```bash
# View detailed coverage report
bunx vitest --coverage

# Open HTML report
open coverage/index.html

# Adjust thresholds
# In vitest.config.ts:
coverage: {
  thresholds: {
    lines: 70,      // Lower threshold
    functions: 70,
    branches: 70,
    statements: 70,
  },
}
```

### Slow Tests

```bash
# Run tests in parallel (default)
bunx vitest --threads

# Limit parallelism
bunx vitest --maxWorkers=4

# Profile slow tests
bunx vitest --reporter=verbose
```

## Performance Comparison

| Tool | Startup | Watch Mode | Coverage |
|------|---------|------------|----------|
| Vitest | ~100ms | Instant HMR | v8 (fast) |
| Jest | ~3-5s | Polling | Istanbul (slower) |

**Vitest is 5-10x faster than Jest in watch mode.**

## References

- Official docs: https://vitest.dev
- Configuration: https://vitest.dev/config/
- API reference: https://vitest.dev/api/
- Migration from Jest: https://vitest.dev/guide/migration.html
- Coverage: https://vitest.dev/guide/coverage.html
