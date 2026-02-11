# configure-ux-testing Reference

## Compliance Report Format

```
UX Testing Compliance Report
=============================
Project: [name]
Framework: Playwright

Playwright Core:
  @playwright/test        package.json               [INSTALLED | MISSING]
  playwright.config.ts    configuration              [EXISTS | MISSING]
  Desktop browsers        chromium, firefox, webkit  [ALL | PARTIAL]
  Mobile viewports        iPhone, Pixel              [CONFIGURED | OPTIONAL]
  WebServer config        auto-start dev server      [CONFIGURED | MISSING]
  Trace on failure        debugging support          [ENABLED | DISABLED]

Accessibility Testing:
  @axe-core/playwright    package.json               [INSTALLED | MISSING]
  a11y test files         tests/a11y/                [FOUND | NONE]
  WCAG level              AA (recommended)           [CONFIGURED | NOT SET]
  Violations threshold    0 (strict)                 [STRICT | LENIENT]

Visual Regression:
  Screenshot tests        toHaveScreenshot()         [FOUND | OPTIONAL]
  Snapshot directory      __snapshots__              [CONFIGURED | N/A]
  CI handling             GitHub Actions artifact    [CONFIGURED | MISSING]

MCP Integration:
  Playwright MCP          .mcp.json                  [CONFIGURED | OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Install @axe-core/playwright for accessibility testing
  - Add mobile viewport configurations
  - Configure visual regression workflow
```

## Playwright Configuration Template (`playwright.config.ts`)

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { open: 'never' }],
    ['json', { outputFile: 'test-results/results.json' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
  ],
  timeout: 30000,
  expect: {
    timeout: 5000,
    toHaveScreenshot: {
      maxDiffPixels: 100,
      threshold: 0.2,
    },
  },
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 10000,
    navigationTimeout: 30000,
  },
  projects: [
    // Desktop browsers
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    // Mobile viewports
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'mobile-safari',
      use: { ...devices['iPhone 13'] },
    },
    // Accessibility tests (single browser)
    {
      name: 'a11y',
      testMatch: /.*\.a11y\.spec\.ts/,
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: {
    command: 'bun run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
});
```

## Accessibility Test Helper (`tests/e2e/helpers/a11y.ts`)

```typescript
import { Page, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

export interface A11yOptions {
  /** WCAG conformance level: 'wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa' */
  level?: 'wcag2a' | 'wcag2aa' | 'wcag21aa' | 'wcag22aa';
  /** Specific rules to include */
  includeRules?: string[];
  /** Specific rules to exclude */
  excludeRules?: string[];
  /** Selectors to exclude from analysis */
  excludeSelectors?: string[];
}

/**
 * Run accessibility scan on page and assert no violations
 */
export async function expectNoA11yViolations(
  page: Page,
  options: A11yOptions = {}
): Promise<void> {
  const {
    level = 'wcag21aa',
    includeRules = [],
    excludeRules = [],
    excludeSelectors = [],
  } = options;

  let builder = new AxeBuilder({ page })
    .withTags([level, 'best-practice']);

  if (includeRules.length > 0) {
    builder = builder.include(includeRules);
  }

  if (excludeRules.length > 0) {
    builder = builder.disableRules(excludeRules);
  }

  if (excludeSelectors.length > 0) {
    for (const selector of excludeSelectors) {
      builder = builder.exclude(selector);
    }
  }

  const results = await builder.analyze();

  // Format violations for readable output
  const violationSummary = results.violations.map((v) => ({
    rule: v.id,
    impact: v.impact,
    description: v.description,
    nodes: v.nodes.length,
    elements: v.nodes.map((n) => n.html).slice(0, 3),
  }));

  expect(
    results.violations,
    `Found ${results.violations.length} accessibility violation(s):\n${JSON.stringify(violationSummary, null, 2)}`
  ).toHaveLength(0);
}

/**
 * Run accessibility scan and return detailed report
 */
export async function getA11yReport(
  page: Page,
  options: A11yOptions = {}
): Promise<{
  violations: number;
  passes: number;
  incomplete: number;
  details: unknown;
}> {
  const { level = 'wcag21aa' } = options;

  const results = await new AxeBuilder({ page })
    .withTags([level, 'best-practice'])
    .analyze();

  return {
    violations: results.violations.length,
    passes: results.passes.length,
    incomplete: results.incomplete.length,
    details: results,
  };
}
```

## Example Accessibility Test (`tests/e2e/homepage.a11y.spec.ts`)

```typescript
import { test, expect } from '@playwright/test';
import { expectNoA11yViolations, getA11yReport } from './helpers/a11y';

test.describe('Homepage Accessibility', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should have no WCAG 2.1 AA violations', async ({ page }) => {
    await expectNoA11yViolations(page, {
      level: 'wcag21aa',
    });
  });

  test('should have no violations after interaction', async ({ page }) => {
    // Interact with page elements
    await page.getByRole('button', { name: /menu/i }).click();

    // Check accessibility after state change
    await expectNoA11yViolations(page);
  });

  test('should generate full accessibility report', async ({ page }) => {
    const report = await getA11yReport(page);

    console.log(`Accessibility Report:
      - Violations: ${report.violations}
      - Passes: ${report.passes}
      - Incomplete: ${report.incomplete}
    `);

    expect(report.violations).toBe(0);
  });
});

test.describe('Form Accessibility', () => {
  test('login form should be accessible', async ({ page }) => {
    await page.goto('/login');

    // Check form has proper labels
    await expect(page.getByLabel('Email')).toBeVisible();
    await expect(page.getByLabel('Password')).toBeVisible();

    // Check submit button is accessible
    await expect(page.getByRole('button', { name: /sign in/i })).toBeEnabled();

    // Run full a11y scan
    await expectNoA11yViolations(page);
  });
});
```

## Example Visual Regression Test (`tests/e2e/visual.spec.ts`)

```typescript
import { test, expect } from '@playwright/test';

test.describe('Visual Regression', () => {
  test('homepage matches snapshot', async ({ page }) => {
    await page.goto('/');

    // Wait for dynamic content to load
    await page.waitForLoadState('networkidle');

    // Full page screenshot
    await expect(page).toHaveScreenshot('homepage.png', {
      fullPage: true,
    });
  });

  test('header matches snapshot', async ({ page }) => {
    await page.goto('/');

    // Component screenshot
    const header = page.locator('header');
    await expect(header).toHaveScreenshot('header.png');
  });

  test('responsive layouts match snapshots', async ({ page }) => {
    await page.goto('/');

    // Desktop
    await page.setViewportSize({ width: 1920, height: 1080 });
    await expect(page).toHaveScreenshot('homepage-desktop.png');

    // Tablet
    await page.setViewportSize({ width: 768, height: 1024 });
    await expect(page).toHaveScreenshot('homepage-tablet.png');

    // Mobile
    await page.setViewportSize({ width: 375, height: 667 });
    await expect(page).toHaveScreenshot('homepage-mobile.png');
  });

  test('dark mode matches snapshot', async ({ page }) => {
    await page.goto('/');

    // Enable dark mode (adjust selector for your app)
    await page.emulateMedia({ colorScheme: 'dark' });

    await expect(page).toHaveScreenshot('homepage-dark.png', {
      fullPage: true,
    });
  });
});
```

## CI/CD Workflow Template (`.github/workflows/e2e.yml`)

```yaml
name: E2E Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  e2e:
    timeout-minutes: 60
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Install Playwright Browsers
        run: bunx playwright install --with-deps

      - name: Run E2E tests
        run: bunx playwright test

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30

      - name: Upload screenshots
        uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: test-screenshots
          path: test-results/
          retention-days: 7

  a11y:
    timeout-minutes: 30
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Install Playwright Browsers
        run: bunx playwright install chromium --with-deps

      - name: Run accessibility tests
        run: bunx playwright test --project=a11y

      - name: Upload a11y report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: a11y-report
          path: playwright-report/
          retention-days: 30
```

## Results Report Format

```
UX Testing Configuration Complete
===================================

Framework: Playwright
Accessibility: axe-core (WCAG 2.1 AA)
Visual: Screenshot comparisons

Configuration Applied:
  @playwright/test installed
  @axe-core/playwright installed
  playwright.config.ts created
  Desktop and mobile projects configured
  WebServer auto-start configured

Accessibility Testing:
  a11y helper functions created
  Example accessibility tests added
  WCAG 2.1 AA level configured

Visual Regression:
  Screenshot test examples created
  Responsive breakpoint tests included
  Dark mode test included

Scripts Added:
  bun run test:e2e (run all E2E tests)
  bun run test:a11y (accessibility only)
  bun run test:visual (visual regression)
  bun run test:visual:update (update snapshots)

CI/CD:
  GitHub Actions workflow created
  Parallel E2E and a11y jobs
  Artifact upload for reports

Next Steps:
  1. Start dev server:
     bun run dev

  2. Run E2E tests:
     bun run test:e2e

  3. Run accessibility scan:
     bun run test:a11y

  4. Update visual snapshots:
     bun run test:visual:update

  5. Open interactive UI:
     bun run test:e2e:ui

Documentation:
  - Playwright: https://playwright.dev
  - axe-core: https://www.deque.com/axe
  - Skill: playwright-testing, accessibility-implementation
```
