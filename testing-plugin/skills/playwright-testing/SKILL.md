---
model: haiku
created: 2025-12-16
modified: 2026-02-14
reviewed: 2025-12-16
name: playwright-testing
description: |
  Playwright end-to-end testing for web applications. Cross-browser testing (Chromium, Firefox, WebKit),
  visual regression, API testing, mobile emulation. Use when writing E2E tests, testing across browsers,
  or setting up automated UI testing workflows.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Playwright Testing

Playwright is a modern end-to-end testing framework for web applications. It provides reliable, fast, and cross-browser testing with excellent developer experience.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Writing E2E browser tests | Writing unit tests (use vitest-testing) |
| Testing across Chromium, Firefox, WebKit | Testing Python code (use python-testing) |
| Setting up visual regression testing | Analyzing test quality (use test-quality-analysis) |
| Mocking network requests in E2E tests | Generating property-based tests (use property-based-testing) |
| Testing mobile viewports | Testing API contracts only (use api-testing) |

## Core Expertise

- **Cross-browser**: Test on Chromium, Firefox, WebKit (Safari)
- **Reliable**: Auto-wait, auto-retry, no flaky tests
- **Fast**: Parallel execution, browser context isolation
- **Modern**: TypeScript-first, async/await, auto-complete
- **Multi-platform**: Windows, macOS, Linux

## Installation

```bash
bun create playwright                  # Initialize (recommended)
bun add --dev @playwright/test         # Or install manually
bunx playwright install                # Install browsers
bunx playwright install --with-deps    # With system deps (Linux)
bunx playwright --version              # Verify
```

## Configuration (playwright.config.ts)

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30000,
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
```

## Essential Commands

```bash
bunx playwright test                           # Run all tests
bunx playwright test tests/login.spec.ts       # Specific file
bunx playwright test --headed                  # See browser
bunx playwright test --debug                   # Debug mode
bunx playwright test --project=chromium        # Specific browser
bunx playwright test --ui                      # UI mode
bunx playwright codegen http://localhost:3000  # Record tests
bunx playwright show-report                    # Last report
bunx playwright show-trace trace.zip           # Trace viewer
bunx playwright test --update-snapshots        # Update snapshots
```

## Writing Tests

### Basic Test Structure

```typescript
import { test, expect } from '@playwright/test';

test('basic test', async ({ page }) => {
  await page.goto('https://example.com');
  await expect(page).toHaveTitle(/Example/);
});

test.describe('login flow', () => {
  test('should login successfully', async ({ page }) => {
    await page.goto('/login');
    await page.fill('input[name="email"]', 'user@example.com');
    await page.fill('input[name="password"]', 'password123');
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/dashboard');
  });
});
```

### Selectors and Locators

```typescript
// Text/Role selectors (recommended)
await page.getByText('Sign in').click();
await page.getByRole('button', { name: 'Submit' }).click();
await page.getByLabel('Email').fill('user@example.com');
await page.getByPlaceholder('Enter your name').fill('John');
await page.getByTestId('login-button').click();

// CSS/XPath selectors
await page.locator('.button-primary').click();
await page.locator('xpath=//button[text()="Submit"]').click();

// Chaining
await page.locator('.card').filter({ hasText: 'Product' }).getByRole('button').click();
```

### Key Assertions

| Assertion | Description |
|-----------|-------------|
| `toHaveTitle(title)` | Page title |
| `toHaveURL(url)` | Page URL |
| `toBeVisible()` | Element visible |
| `toBeEnabled()` | Element enabled |
| `toHaveText(text)` | Element text |
| `toContainText(text)` | Partial text |
| `toHaveAttribute(name, value)` | Attribute value |
| `toHaveClass(class)` | CSS class |
| `toHaveValue(value)` | Input value |
| `toBeEmpty()` | Empty input |
| `toHaveCount(n)` | Element count |
| `not.toBeDisabled()` | Negation |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick test | `bunx playwright test --reporter=line --bail` |
| CI test | `bunx playwright test --reporter=github` |
| Single browser | `bunx playwright test --project=chromium --reporter=line` |
| Debug failing | `bunx playwright test --trace on --reporter=line` |
| Headed debug | `bunx playwright test --headed --debug` |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- Official docs: https://playwright.dev
- Configuration: https://playwright.dev/docs/test-configuration
- API reference: https://playwright.dev/docs/api/class-test
- Best practices: https://playwright.dev/docs/best-practices
- CI/CD: https://playwright.dev/docs/ci
- Trace viewer: https://playwright.dev/docs/trace-viewer
