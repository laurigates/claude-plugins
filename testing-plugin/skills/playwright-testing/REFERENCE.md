# Playwright Testing - Reference

Detailed reference material for Playwright E2E testing configuration, patterns, and CI/CD integration.

## Recommended Production Configuration

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html'],
    ['json', { outputFile: 'test-results/results.json' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
  ],
  timeout: 30000,
  expect: {
    timeout: 5000,
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
    {
      name: 'mobile-chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'mobile-safari',
      use: { ...devices['iPhone 13'] },
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

## Page Object Model

```typescript
// page-objects/login-page.ts
import { Page, Locator } from '@playwright/test';

export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel('Email');
    this.passwordInput = page.getByLabel('Password');
    this.submitButton = page.getByRole('button', { name: 'Sign in' });
  }

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }
}

// tests/login.spec.ts
import { test, expect } from '@playwright/test';
import { LoginPage } from '../page-objects/login-page';

test('login with page object', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('user@example.com', 'password123');
  await expect(page).toHaveURL('/dashboard');
});
```

## Fixtures

### Built-in Fixtures

```typescript
import { test } from '@playwright/test';

test('built-in fixtures', async ({ page, context, browser }) => {
  // page - isolated browser page
  await page.goto('/');

  // context - browser context (cookies, storage)
  await context.clearCookies();

  // browser - browser instance
  const newPage = await browser.newPage();
});
```

### Custom Fixtures

```typescript
// fixtures/auth-fixture.ts
import { test as base } from '@playwright/test';
import { LoginPage } from '../page-objects/login-page';

type AuthFixtures = {
  authenticatedPage: Page;
};

export const test = base.extend<AuthFixtures>({
  authenticatedPage: async ({ page }, use) => {
    const loginPage = new LoginPage(page);
    await loginPage.goto();
    await loginPage.login('user@example.com', 'password123');
    await use(page);
  },
});

// tests/dashboard.spec.ts
import { test } from '../fixtures/auth-fixture';

test('access dashboard', async ({ authenticatedPage }) => {
  await authenticatedPage.goto('/dashboard');
  // User is already logged in
});
```

## Authentication State

### Save Authentication State

```typescript
// tests/auth.setup.ts
import { test as setup } from '@playwright/test';

const authFile = 'playwright/.auth/user.json';

setup('authenticate', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('user@example.com');
  await page.getByLabel('Password').fill('password123');
  await page.getByRole('button', { name: 'Sign in' }).click();

  await page.waitForURL('/dashboard');

  await page.context().storageState({ path: authFile });
});
```

### Use Saved State

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    { name: 'setup', testMatch: /.*\.setup\.ts/ },
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: 'playwright/.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

## API Testing

```typescript
import { test, expect } from '@playwright/test';

test('api testing', async ({ request }) => {
  // GET request
  const response = await request.get('https://api.example.com/users');
  expect(response.ok()).toBeTruthy();
  expect(response.status()).toBe(200);

  const users = await response.json();
  expect(users).toHaveLength(10);

  // POST request
  const createResponse = await request.post('https://api.example.com/users', {
    data: {
      name: 'John Doe',
      email: 'john@example.com',
    },
  });
  expect(createResponse.ok()).toBeTruthy();

  // With authentication
  const authResponse = await request.get('https://api.example.com/profile', {
    headers: {
      Authorization: 'Bearer token123',
    },
  });
  expect(authResponse.ok()).toBeTruthy();
});
```

## Network Interception

```typescript
import { test, expect } from '@playwright/test';

test('mock api response', async ({ page }) => {
  // Mock API response
  await page.route('**/api/users', (route) => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify([
        { id: 1, name: 'John' },
        { id: 2, name: 'Jane' },
      ]),
    });
  });

  await page.goto('/users');
  await expect(page.getByText('John')).toBeVisible();
});

test('block images', async ({ page }) => {
  // Block image requests
  await page.route('**/*.{png,jpg,jpeg}', (route) => route.abort());

  await page.goto('/');
  // Page loads faster without images
});

test('intercept and modify', async ({ page }) => {
  await page.route('**/api/config', async (route) => {
    const response = await route.fetch();
    const json = await response.json();
    json.feature_flag = true;
    await route.fulfill({ json });
  });

  await page.goto('/');
});
```

## Visual Regression Testing

```typescript
import { test, expect } from '@playwright/test';

test('visual regression', async ({ page }) => {
  await page.goto('/');

  // Full page screenshot
  await expect(page).toHaveScreenshot('homepage.png');

  // Element screenshot
  const header = page.locator('header');
  await expect(header).toHaveScreenshot('header.png');

  // With options
  await expect(page).toHaveScreenshot('homepage-mobile.png', {
    fullPage: true,
    maxDiffPixels: 100,
  });
});

// Update snapshots with:
// bunx playwright test --update-snapshots
```

## Mobile Emulation

```typescript
import { test, devices } from '@playwright/test';

test.use({
  ...devices['iPhone 13'],
});

test('mobile test', async ({ page }) => {
  await page.goto('/');
  // Test runs in iPhone 13 viewport
});

// Or configure in playwright.config.ts:
// projects: [
//   {
//     name: 'mobile',
//     use: { ...devices['Pixel 5'] },
//   },
// ]
```

## Parallel Execution

```typescript
// playwright.config.ts
export default defineConfig({
  fullyParallel: true,
  workers: process.env.CI ? 1 : undefined, // All cores locally, 1 in CI
});

// Force serial execution for specific tests
test.describe.serial('checkout flow', () => {
  test('add to cart', async ({ page }) => {
    // ...
  });

  test('proceed to checkout', async ({ page }) => {
    // Runs after previous test
  });
});
```

## Debugging

### Debug Mode

```bash
# Run with debugger
bunx playwright test --debug

# Debug specific test
bunx playwright test tests/login.spec.ts --debug

# Pause on failure
bunx playwright test --headed --pause-on-failure
```

### Trace Viewer

```typescript
// playwright.config.ts
export default defineConfig({
  use: {
    trace: 'on-first-retry', // or 'on', 'off', 'retain-on-failure'
  },
});
```

```bash
# View trace
bunx playwright show-trace trace.zip
```

**Trace viewer shows:**
- Timeline of actions
- Screenshots at each step
- Network activity
- Console logs
- Source code

## CI/CD Integration

### GitHub Actions

```yaml
name: Playwright Tests
on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
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

      - name: Run Playwright tests
        run: bunx playwright test

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 30
```

### GitLab CI

```yaml
playwright:
  image: mcr.microsoft.com/playwright:v1.40.0-jammy
  stage: test
  script:
    - bun install --frozen-lockfile
    - bunx playwright test
  artifacts:
    when: always
    paths:
      - playwright-report/
      - test-results/
    expire_in: 1 week
```

## WebGL Apps in GPU-less CI

GitHub-hosted runners have no GPU. A WebGL app (CesiumJS, three.js, MapLibre) renders there on SwiftShader, Chrome's CPU rasterizer, and the defaults are fragile.

### Force the renderer explicitly

On current Chrome (155), `--disable-gpu` alone leaves **no WebGL at all**: the automatic SwiftShader fallback is deprecated, so the app's 3D view never starts and anything measured afterwards (scores, timings, screenshots) describes a page without it. Opt in explicitly:

| Flag | Why |
|---|---|
| `--use-gl=angle --use-angle=swiftshader` | WebGL on SwiftShader |
| `--enable-unsafe-swiftshader` | The opt-in Chromium documents for the deprecated fallback |
| `--disable-gpu-compositing` | Keeps page compositing on the CPU. Composited through SwiftShader, DOM paints queue behind WebGL frames in the GPU process (measured: LCP 9 s vs 2.9 s) |

```ts
// playwright.config.ts
use: {
  launchOptions: {
    args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-gpu-compositing'],
  },
},
```

Verify the renderer from inside the page rather than trusting the config: read `UNMASKED_RENDERER_WEBGL` from `WEBGL_debug_renderer_info`, and fail the run when it is missing or unexpected. Locally SwiftShader uses its LLVM backend; on Linux CI it reports `SwiftShader Device (Subzero)` and is several times slower, so local and CI timings are separate series.

### Lighthouse CI: `chromeFlags` must be a string

lhci 0.15 builds the flag string as `chromeFlags + ' --headless=new'`. An array in `lighthouserc` `settings.chromeFlags` is therefore comma-joined into **one bogus switch, and no flag applies**: Chrome silently uses the host GPU locally and its own default on CI. Pass one space-separated string (`[...].join(' ')`) and pin that with a test. To prove the renderer inside Lighthouse, have the app emit `performance.mark('<name> renderer=<UNMASKED_RENDERER>')`. The mark shows up in the `user-timings` audit without affecting any score, so a script can check every `lhr-*.json`.

### Software frames can starve loading

At ~140 ms (local) to ~500 ms (CI) per frame, a render loop that redraws while tiles stream in keeps the main thread busy and slows the loading that would let it stop. TBT and TTI then measure the rasterizer, not the app, and the run can hit Lighthouse's load timeout. In a CesiumJS measurement:

- `resolutionScale` 0.5 and MSAA off changed per-frame cost by under 15% locally (cost is per draw call, not per pixel), though on CI's slower backend half resolution did cut TBT from 33 s to 8 s.
- A frame-rate cap (`viewer.targetFrameRate`) broke the cycle, but **only below 1 / frame-cost**: on CI 2 fps changed nothing (frames already took ~500 ms) and 0.5 fps cut TBT from 33 s to 1.9 s.

Apply such a cap only in the CI measurement build, record it alongside the renderer, and treat the resulting performance numbers as a CI-to-CI trend, not as what users with a GPU see.

## Best Practices

### Use Built-in Locators

```typescript
// Good: Resilient to UI changes
await page.getByRole('button', { name: 'Submit' }).click();
await page.getByLabel('Email').fill('user@example.com');
await page.getByText('Welcome').click();

// Bad: Fragile selectors
await page.locator('#submit-btn-123').click();
await page.locator('div > div > input').fill('user@example.com');
```

### Auto-waiting

```typescript
// Good: Playwright waits automatically
await page.getByRole('button').click();

// Bad: Manual waits
await page.waitForTimeout(1000);
await page.getByRole('button').click();
```

### Isolate Tests

```typescript
// Good: Independent tests
test('test 1', async ({ page }) => {
  await page.goto('/');
  // Test logic
});

test('test 2', async ({ page }) => {
  await page.goto('/');
  // Independent test logic
});

// Bad: Tests depend on each other
```

### Use Test IDs for Dynamic Content

```html
<!-- HTML -->
<button data-testid="submit-btn">Submit</button>
```

```typescript
// Test
await page.getByTestId('submit-btn').click();
```

## Troubleshooting

### Tests Timing Out

```typescript
// Increase timeout for specific test
test('slow test', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto('/slow-page');
});

// Or in config:
export default defineConfig({
  timeout: 60000,
  expect: {
    timeout: 10000,
  },
});
```

### Flaky Tests

```bash
# Run test multiple times
bunx playwright test --repeat-each=10

# Retry failed tests
bunx playwright test --retries=3
```

### Element Not Found

```typescript
// Wait for element explicitly
await page.waitForSelector('.element');

// Or use auto-wait assertions
await expect(page.locator('.element')).toBeVisible();
```

### Browser Not Found

```bash
# Reinstall browsers
bunx playwright install

# Verify installation
bunx playwright install --help
```
