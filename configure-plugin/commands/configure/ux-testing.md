---
description: Check and configure UX testing infrastructure (Playwright, accessibility, visual regression)
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--a11y] [--visual]"
---

# /configure:ux-testing

Check and configure UX testing infrastructure with Playwright as the primary tool for E2E, accessibility, and visual regression testing.

## Context

This command validates UX testing setup and optionally configures Playwright with accessibility and visual regression testing.

**UX Testing Stack:**
- **Playwright** - Cross-browser E2E testing (primary tool)
- **axe-core** - Automated accessibility testing (WCAG compliance)
- **Playwright screenshots** - Visual regression testing
- **Playwright MCP** - Browser automation via MCP integration

## Version Checking

**CRITICAL**: Before configuring UX testing tools, verify latest versions:

1. **@playwright/test**: Check [playwright.dev](https://playwright.dev/) or [npm](https://www.npmjs.com/package/@playwright/test)
2. **@axe-core/playwright**: Check [npm](https://www.npmjs.com/package/@axe-core/playwright)
3. **playwright MCP**: Check [npm](https://www.npmjs.com/package/@anthropic/mcp-server-playwright)

Use WebSearch or WebFetch to verify current versions before configuring UX testing infrastructure.

## Workflow

### Phase 1: Project Detection

Detect existing UX testing infrastructure:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `playwright.config.*` | Playwright | Installed |
| `@axe-core/playwright` in package.json | Accessibility testing | Configured |
| `@playwright/test` in package.json | Playwright Test | Installed |
| `tests/e2e/` or `e2e/` directory | E2E tests | Present |
| `*.spec.ts` files with toHaveScreenshot | Visual regression | Configured |
| `.mcp.json` with playwright server | Playwright MCP | Configured |

### Phase 2: Current State Analysis

Check for complete UX testing setup:

**Playwright Core:**
- [ ] `@playwright/test` installed
- [ ] `playwright.config.ts` exists
- [ ] Browser projects configured (Chromium, Firefox, WebKit)
- [ ] Mobile viewports configured (optional)
- [ ] WebServer configuration for local dev
- [ ] Trace/screenshot/video on failure

**Accessibility Testing:**
- [ ] `@axe-core/playwright` installed
- [ ] Accessibility tests created
- [ ] WCAG level configured (A, AA, AAA)
- [ ] Custom rules/exceptions documented

**Visual Regression:**
- [ ] Screenshot assertions configured
- [ ] Snapshot directory configured
- [ ] Update workflow documented
- [ ] CI snapshot handling configured

**MCP Integration:**
- [ ] Playwright MCP server in `.mcp.json`
- [ ] Browser automation available to Claude

### Phase 3: Compliance Report

Generate formatted compliance report:

```
UX Testing Compliance Report
=============================
Project: [name]
Framework: Playwright

Playwright Core:
  @playwright/test        package.json               [✅ INSTALLED | ❌ MISSING]
  playwright.config.ts    configuration              [✅ EXISTS | ❌ MISSING]
  Desktop browsers        chromium, firefox, webkit  [✅ ALL | ⚠️ PARTIAL]
  Mobile viewports        iPhone, Pixel              [✅ CONFIGURED | ⏭️ OPTIONAL]
  WebServer config        auto-start dev server      [✅ CONFIGURED | ⚠️ MISSING]
  Trace on failure        debugging support          [✅ ENABLED | ⚠️ DISABLED]

Accessibility Testing:
  @axe-core/playwright    package.json               [✅ INSTALLED | ❌ MISSING]
  a11y test files         tests/a11y/                [✅ FOUND | ❌ NONE]
  WCAG level              AA (recommended)           [✅ CONFIGURED | ⚠️ NOT SET]
  Violations threshold    0 (strict)                 [✅ STRICT | ⚠️ LENIENT]

Visual Regression:
  Screenshot tests        toHaveScreenshot()         [✅ FOUND | ⏭️ OPTIONAL]
  Snapshot directory      __snapshots__              [✅ CONFIGURED | ⏭️ N/A]
  CI handling             GitHub Actions artifact    [✅ CONFIGURED | ⚠️ MISSING]

MCP Integration:
  Playwright MCP          .mcp.json                  [✅ CONFIGURED | ⏭️ OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Install @axe-core/playwright for accessibility testing
  - Add mobile viewport configurations
  - Configure visual regression workflow
```

### Phase 4: Configuration (if --fix or user confirms)

#### Install Dependencies

```bash
# Core Playwright
bun add --dev @playwright/test

# Accessibility testing
bun add --dev @axe-core/playwright

# Install browsers
bunx playwright install
```

#### Create `playwright.config.ts`

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

#### Create Accessibility Test Helper

**Create `tests/e2e/helpers/a11y.ts`:**

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

#### Create Example Accessibility Test

**Create `tests/e2e/homepage.a11y.spec.ts`:**

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

#### Create Visual Regression Test

**Create `tests/e2e/visual.spec.ts`:**

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

#### Add npm Scripts

**Update `package.json`:**

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:e2e:headed": "playwright test --headed",
    "test:e2e:debug": "playwright test --debug",
    "test:e2e:ui": "playwright test --ui",
    "test:a11y": "playwright test --project=a11y",
    "test:visual": "playwright test visual.spec.ts",
    "test:visual:update": "playwright test visual.spec.ts --update-snapshots",
    "playwright:codegen": "playwright codegen http://localhost:3000",
    "playwright:report": "playwright show-report"
  }
}
```

### Phase 5: MCP Integration (Optional)

**Add to `.mcp.json`:**

```json
{
  "mcpServers": {
    "playwright": {
      "command": "bunx",
      "args": ["-y", "@playwright/mcp@latest"]
    }
  }
}
```

This enables Claude to:
- Navigate and interact with web pages
- Take screenshots for visual debugging
- Fill forms and click elements
- Capture accessibility snapshots

### Phase 6: CI/CD Integration

**Create `.github/workflows/e2e.yml`:**

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

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  ux_testing: "2025.1"
  ux_testing_framework: "playwright"
  ux_testing_a11y: true
  ux_testing_a11y_level: "wcag21aa"
  ux_testing_visual: true
  ux_testing_mcp: true
```

### Phase 8: Updated Compliance Report

```
UX Testing Configuration Complete
===================================

Framework: Playwright
Accessibility: axe-core (WCAG 2.1 AA)
Visual: Screenshot comparisons

Configuration Applied:
  ✅ @playwright/test installed
  ✅ @axe-core/playwright installed
  ✅ playwright.config.ts created
  ✅ Desktop and mobile projects configured
  ✅ WebServer auto-start configured

Accessibility Testing:
  ✅ a11y helper functions created
  ✅ Example accessibility tests added
  ✅ WCAG 2.1 AA level configured

Visual Regression:
  ✅ Screenshot test examples created
  ✅ Responsive breakpoint tests included
  ✅ Dark mode test included

Scripts Added:
  ✅ bun run test:e2e (run all E2E tests)
  ✅ bun run test:a11y (accessibility only)
  ✅ bun run test:visual (visual regression)
  ✅ bun run test:visual:update (update snapshots)

CI/CD:
  ✅ GitHub Actions workflow created
  ✅ Parallel E2E and a11y jobs
  ✅ Artifact upload for reports

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

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--a11y` | Focus on accessibility testing configuration |
| `--visual` | Focus on visual regression testing configuration |

## Examples

```bash
# Check compliance and offer fixes
/configure:ux-testing

# Check only, no modifications
/configure:ux-testing --check-only

# Auto-fix all issues
/configure:ux-testing --fix

# Configure accessibility testing only
/configure:ux-testing --fix --a11y

# Configure visual regression only
/configure:ux-testing --fix --visual
```

## Error Handling

- **No package manager found**: Cannot install dependencies, provide manual steps
- **Dev server not configured**: Warn about manual baseURL configuration
- **Browsers not installed**: Prompt to run `bunx playwright install`
- **Existing config conflicts**: Preserve user config, suggest merge

## See Also

- `/configure:tests` - Unit and integration testing configuration
- `/configure:all` - Run all FVH compliance checks
- **Skills**: `playwright-testing`, `accessibility-implementation`
- **Agents**: `ux-implementation` for implementing UX designs
- **Playwright documentation**: https://playwright.dev
- **axe-core documentation**: https://www.deque.com/axe
