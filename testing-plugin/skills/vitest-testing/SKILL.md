---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: vitest-testing
description: |
  Vitest test runner for JavaScript and TypeScript. Fast, modern alternative to Jest.
  Vite-native, ESM support, watch mode, UI mode, coverage, mocking, snapshot testing.
  Use when setting up tests for Vite projects, migrating from Jest, or needing fast test execution.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Vitest Testing

Vitest is a modern test runner designed for Vite projects. It's fast, ESM-native, and provides a Jest-compatible API with better TypeScript support and instant HMR-powered watch mode.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Setting up or configuring Vitest | Writing E2E browser tests (use playwright-testing) |
| Writing unit/integration tests in TS/JS | Testing Python code (use python-testing) |
| Migrating from Jest to Vitest | Analyzing test quality (use test-quality-analysis) |
| Configuring coverage thresholds | Generating property-based tests (use property-based-testing) |
| Using mocks, spies, or fake timers | Validating test effectiveness (use mutation-testing) |

## Core Expertise

- **Vite-native**: Reuses Vite config, transforms, and plugins
- **Fast**: Instant feedback with HMR-powered watch mode
- **Jest-compatible**: Drop-in replacement with similar API
- **TypeScript**: First-class TypeScript support
- **ESM**: Native ESM support, no transpilation needed

## Installation

```bash
bun add --dev vitest
bun add --dev @vitest/coverage-v8      # Coverage (recommended)
bun add --dev happy-dom                # DOM testing (optional)
bunx vitest --version                  # Verify
```

## Configuration (vitest.config.ts)

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
  },
});
```

## Essential Commands

```bash
bunx vitest                            # Watch mode (default)
bunx vitest run                        # Run once (CI mode)
bunx vitest --coverage                 # With coverage
bunx vitest src/utils.test.ts          # Specific file
bunx vitest -t "should add numbers"    # Filter by name
bunx vitest related src/utils.ts       # Related tests
bunx vitest -u                         # Update snapshots
bunx vitest bench                      # Benchmarks
bunx vitest --ui                       # UI mode
```

## Writing Tests

### Basic Test Structure

```typescript
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

### Key Assertions

| Assertion | Description |
|-----------|-------------|
| `toBe(value)` | Strict equality |
| `toEqual(value)` | Deep equality |
| `toStrictEqual(value)` | Deep strict equality |
| `toBeTruthy()` / `toBeFalsy()` | Truthiness |
| `toBeNull()` / `toBeUndefined()` | Null checks |
| `toBeGreaterThan(n)` / `toBeLessThan(n)` | Numeric comparison |
| `toBeCloseTo(n)` | Float comparison |
| `toMatch(regex)` / `toContain(str)` | String matching |
| `toHaveLength(n)` | Array/string length |
| `toHaveProperty(key)` | Object property |
| `toMatchObject(obj)` | Partial object match |
| `toThrow(msg)` | Error throwing |

### Async Tests

```typescript
test('async test', async () => {
  const data = await fetchData();
  expect(data).toBe('expected');
});

test('promise resolves', async () => {
  await expect(fetchData()).resolves.toBe('expected');
});

test('promise rejects', async () => {
  await expect(fetchBadData()).rejects.toThrow('error');
});
```

## Mocking (Essential Patterns)

```typescript
import { vi, test, expect } from 'vitest';

// Mock function
const mockFn = vi.fn();
mockFn.mockReturnValue(42);

// Mock module
vi.mock('./api', () => ({
  fetchUser: vi.fn(() => Promise.resolve({ id: 1, name: 'John' })),
}));

// Mock timers
vi.useFakeTimers();
vi.advanceTimersByTime(1000);
vi.restoreAllMocks();

// Spy on method
const spy = vi.spyOn(object, 'method');
```

## Snapshot Testing

```typescript
test('snapshot test', () => {
  expect(data).toMatchSnapshot();
});

test('inline snapshot', () => {
  expect(result).toMatchInlineSnapshot('5');
});
// Update snapshots: bunx vitest -u
```

## Coverage

```bash
bun add --dev @vitest/coverage-v8
bunx vitest --coverage
```

Key config options: `provider`, `reporter`, `include`, `exclude`, `thresholds`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test | `bunx vitest --reporter=dot --bail=1` |
| CI test | `bunx vitest run --reporter=junit` |
| Coverage check | `bunx vitest --coverage --reporter=dot` |
| Single file | `bunx vitest run src/utils.test.ts --reporter=dot` |
| Failed only | `bunx vitest --changed --bail=1` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- Official docs: https://vitest.dev
- Configuration: https://vitest.dev/config/
- API reference: https://vitest.dev/api/
- Migration from Jest: https://vitest.dev/guide/migration.html
- Coverage: https://vitest.dev/guide/coverage.html
