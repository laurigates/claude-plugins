---
description: Check and configure load and performance testing with k6, Artillery, or Locust
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--framework <k6|artillery|locust>]"
---

# /configure:load-tests

Check and configure load and performance testing infrastructure for stress testing, benchmarking, and capacity planning.

## Context

This command validates load testing setup and optionally configures frameworks for performance testing.

**Load Testing Frameworks:**
- **k6** (recommended) - Modern load testing with JavaScript, excellent DX
- **Artillery** - YAML-based, good for quick tests
- **Locust** - Python-based, distributed testing

**When to Use Each:**
| Framework | Best For |
|-----------|----------|
| k6 | Complex scenarios, CI/CD integration, TypeScript support |
| Artillery | Quick YAML configs, simple API testing |
| Locust | Python teams, distributed testing, custom behavior |

**Load Testing Types:**
- **Smoke Test**: Verify system works under minimal load
- **Load Test**: Expected normal load
- **Stress Test**: Find breaking points
- **Spike Test**: Sudden traffic bursts
- **Soak Test**: Extended duration stability

## Workflow

### Phase 1: Project Detection

Detect existing load testing infrastructure:

| Indicator | Component | Status |
|-----------|-----------|--------|
| `k6` binary or `@grafana/k6` | k6 | Installed |
| `*.k6.js` or `load-tests/` | k6 tests | Present |
| `artillery.yml` | Artillery config | Present |
| `locustfile.py` | Locust tests | Present |
| `.github/workflows/*load*` | CI integration | Configured |

### Phase 2: Current State Analysis

Check for complete load testing setup:

**k6 Setup:**
- [ ] k6 installed (binary or npm)
- [ ] Test scenarios defined
- [ ] Thresholds configured
- [ ] Environment-specific configs
- [ ] CI/CD integration

**Test Coverage:**
- [ ] Smoke tests (minimal load)
- [ ] Load tests (normal load)
- [ ] Stress tests (peak load)
- [ ] Spike tests (burst traffic)
- [ ] Soak tests (endurance)

**Reporting:**
- [ ] Console output configured
- [ ] JSON/HTML reports
- [ ] Grafana Cloud k6 (optional)
- [ ] Trend tracking

### Phase 3: Compliance Report

Generate formatted compliance report:

```
Load Testing Compliance Report
===============================
Project: [name]
Framework: k6

Installation:
  k6 binary               /usr/local/bin/k6          [✅ INSTALLED | ❌ MISSING]
  k6 version              0.50+                      [✅ CURRENT | ⚠️ OUTDATED]
  TypeScript support      @types/k6                  [✅ INSTALLED | ⏭️ OPTIONAL]

Test Scenarios:
  Smoke tests             tests/load/smoke.k6.js     [✅ EXISTS | ❌ MISSING]
  Load tests              tests/load/load.k6.js      [✅ EXISTS | ❌ MISSING]
  Stress tests            tests/load/stress.k6.js    [✅ EXISTS | ⏭️ OPTIONAL]
  Spike tests             tests/load/spike.k6.js     [✅ EXISTS | ⏭️ OPTIONAL]

Configuration:
  Thresholds              response time, error rate  [✅ CONFIGURED | ⚠️ MISSING]
  Environments            staging, production        [✅ CONFIGURED | ⚠️ MISSING]
  Data files              test-data.json             [✅ EXISTS | ⏭️ N/A]

CI/CD Integration:
  GitHub Actions          load-test.yml              [✅ CONFIGURED | ❌ MISSING]
  Scheduled runs          weekly/nightly             [✅ CONFIGURED | ⏭️ OPTIONAL]
  PR gate                 smoke test on PR           [✅ CONFIGURED | ⏭️ OPTIONAL]

Reporting:
  Console output          default                    [✅ ENABLED | ✅ DEFAULT]
  JSON export             results.json               [✅ CONFIGURED | ⚠️ MISSING]
  HTML report             k6-reporter                [✅ CONFIGURED | ⏭️ OPTIONAL]
  Grafana Cloud           k6 cloud                   [✅ CONFIGURED | ⏭️ OPTIONAL]

Overall: [X issues found]

Recommendations:
  - Add response time thresholds
  - Configure CI pipeline for smoke tests
  - Add stress test scenario
```

### Phase 4: Configuration (if --fix or user confirms)

#### k6 Installation

**Install k6:**
```bash
# macOS
brew install k6

# Linux (Debian/Ubuntu)
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Docker
docker pull grafana/k6

# Or via npm (for CI)
npm install -g @grafana/k6
```

**Install TypeScript support:**
```bash
bun add --dev @types/k6
```

#### Create Directory Structure

```
tests/
└── load/
    ├── config/
    │   ├── base.js           # Shared configuration
    │   ├── staging.js        # Staging environment
    │   └── production.js     # Production environment
    ├── scenarios/
    │   ├── smoke.k6.js       # Minimal load validation
    │   ├── load.k6.js        # Normal load testing
    │   ├── stress.k6.js      # Find breaking points
    │   ├── spike.k6.js       # Burst traffic
    │   └── soak.k6.js        # Endurance testing
    ├── helpers/
    │   ├── auth.js           # Authentication helpers
    │   └── data.js           # Test data generation
    └── data/
        └── users.json        # Test data files
```

#### Create Base Configuration

**Create `tests/load/config/base.js`:**
```javascript
// Base configuration shared across all load tests

export const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';

// Standard thresholds
export const thresholds = {
  // HTTP errors should be less than 1%
  http_req_failed: ['rate<0.01'],

  // 95% of requests should be below 500ms
  http_req_duration: ['p(95)<500'],

  // 99% of requests should be below 1500ms
  'http_req_duration{expected_response:true}': ['p(99)<1500'],
};

// Default headers
export const headers = {
  'Content-Type': 'application/json',
  'Accept': 'application/json',
};

// Authentication helper
export function getAuthHeaders(token) {
  return {
    ...headers,
    'Authorization': `Bearer ${token}`,
  };
}
```

#### Create Smoke Test

**Create `tests/load/scenarios/smoke.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, thresholds, headers } from '../config/base.js';

/**
 * Smoke Test
 *
 * Purpose: Verify the system works correctly under minimal load.
 * Run this before other load tests to ensure basic functionality.
 *
 * Usage: k6 run tests/load/scenarios/smoke.k6.js
 */

export const options = {
  // Minimal load: 1 user for 30 seconds
  vus: 1,
  duration: '30s',

  thresholds: {
    ...thresholds,
    // Stricter thresholds for smoke test
    http_req_duration: ['p(95)<200'],
    http_req_failed: ['rate<0.001'], // Basically zero errors
  },

  // Tags for filtering in reports
  tags: {
    test_type: 'smoke',
  },
};

export default function () {
  // Test health endpoint
  const healthRes = http.get(`${BASE_URL}/health`, { headers });

  check(healthRes, {
    'health check status is 200': (r) => r.status === 200,
    'health check response time < 100ms': (r) => r.timings.duration < 100,
  });

  // Test main API endpoint
  const usersRes = http.get(`${BASE_URL}/api/users`, { headers });

  check(usersRes, {
    'users endpoint status is 200': (r) => r.status === 200,
    'users endpoint returns array': (r) => Array.isArray(r.json()),
  });

  sleep(1);
}

// Lifecycle hooks for setup/teardown
export function setup() {
  console.log(`Starting smoke test against ${BASE_URL}`);

  // Verify target is reachable
  const res = http.get(`${BASE_URL}/health`);
  if (res.status !== 200) {
    throw new Error(`Target not reachable: ${res.status}`);
  }

  return { startTime: new Date().toISOString() };
}

export function teardown(data) {
  console.log(`Smoke test completed. Started at: ${data.startTime}`);
}
```

#### Create Load Test

**Create `tests/load/scenarios/load.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import { BASE_URL, thresholds, headers, getAuthHeaders } from '../config/base.js';

/**
 * Load Test
 *
 * Purpose: Test system under expected normal load.
 * Simulates typical production traffic patterns.
 *
 * Usage: k6 run tests/load/scenarios/load.k6.js
 * With env: k6 run -e BASE_URL=https://staging.example.com tests/load/scenarios/load.k6.js
 */

// Custom metrics
const apiErrors = new Counter('api_errors');
const successRate = new Rate('success_rate');
const userCreationTime = new Trend('user_creation_time');

export const options = {
  // Ramp up to 50 users over 2 minutes, hold for 5 minutes, ramp down
  stages: [
    { duration: '2m', target: 50 },   // Ramp up
    { duration: '5m', target: 50 },   // Steady state
    { duration: '2m', target: 0 },    // Ramp down
  ],

  thresholds: {
    ...thresholds,
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    success_rate: ['rate>0.95'],      // 95% success rate
    api_errors: ['count<100'],        // Less than 100 total errors
  },

  tags: {
    test_type: 'load',
  },
};

export default function () {
  // Simulate realistic user journey
  group('Browse Products', () => {
    const listRes = http.get(`${BASE_URL}/api/products`, { headers });

    const listSuccess = check(listRes, {
      'products list status is 200': (r) => r.status === 200,
      'products list has items': (r) => r.json().length > 0,
    });

    successRate.add(listSuccess);
    if (!listSuccess) apiErrors.add(1);

    sleep(1);

    // Get product details
    if (listRes.status === 200 && listRes.json().length > 0) {
      const productId = listRes.json()[0].id;
      const detailRes = http.get(`${BASE_URL}/api/products/${productId}`, { headers });

      check(detailRes, {
        'product detail status is 200': (r) => r.status === 200,
      });
    }

    sleep(2);
  });

  group('User Authentication', () => {
    const loginRes = http.post(
      `${BASE_URL}/api/auth/login`,
      JSON.stringify({
        email: `user${__VU}@example.com`,
        password: 'testpassword123',
      }),
      { headers }
    );

    const loginSuccess = check(loginRes, {
      'login status is 200 or 401': (r) => [200, 401].includes(r.status),
    });

    successRate.add(loginSuccess);

    sleep(1);
  });

  group('API Operations', () => {
    // Create a resource
    const startTime = Date.now();

    const createRes = http.post(
      `${BASE_URL}/api/items`,
      JSON.stringify({
        name: `Test Item ${Date.now()}`,
        description: 'Created by load test',
      }),
      { headers }
    );

    userCreationTime.add(Date.now() - startTime);

    const createSuccess = check(createRes, {
      'create status is 201': (r) => r.status === 201,
    });

    successRate.add(createSuccess);
    if (!createSuccess) apiErrors.add(1);

    sleep(1);
  });

  // Think time between iterations
  sleep(Math.random() * 3 + 1);
}

export function handleSummary(data) {
  return {
    'results/load-test-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

// Helper for text summary (built-in)
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
```

#### Create Stress Test

**Create `tests/load/scenarios/stress.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

/**
 * Stress Test
 *
 * Purpose: Find the breaking point of the system.
 * Gradually increase load until performance degrades or errors occur.
 *
 * Usage: k6 run tests/load/scenarios/stress.k6.js
 */

export const options = {
  stages: [
    { duration: '2m', target: 50 },    // Below normal load
    { duration: '5m', target: 50 },    // Normal load
    { duration: '2m', target: 100 },   // Around breaking point
    { duration: '5m', target: 100 },   // Hold at breaking point
    { duration: '2m', target: 200 },   // Beyond breaking point
    { duration: '5m', target: 200 },   // Hold beyond breaking point
    { duration: '5m', target: 0 },     // Recovery
  ],

  thresholds: {
    // More lenient thresholds - we expect degradation
    http_req_failed: ['rate<0.10'],     // Up to 10% errors acceptable
    http_req_duration: ['p(95)<2000'],  // 2s at p95 during stress
  },

  tags: {
    test_type: 'stress',
  },
};

export default function () {
  const responses = http.batch([
    ['GET', `${BASE_URL}/api/products`, null, { headers }],
    ['GET', `${BASE_URL}/api/users`, null, { headers }],
    ['GET', `${BASE_URL}/api/orders`, null, { headers }],
  ]);

  responses.forEach((res, i) => {
    check(res, {
      [`batch request ${i} succeeded`]: (r) => r.status === 200,
    });
  });

  sleep(1);
}
```

#### Create Spike Test

**Create `tests/load/scenarios/spike.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

/**
 * Spike Test
 *
 * Purpose: Test system behavior under sudden traffic bursts.
 * Simulates viral content, flash sales, or attack scenarios.
 *
 * Usage: k6 run tests/load/scenarios/spike.k6.js
 */

export const options = {
  stages: [
    { duration: '1m', target: 10 },    // Warm up
    { duration: '30s', target: 500 },  // Spike to 500 users
    { duration: '1m', target: 500 },   // Hold spike
    { duration: '30s', target: 10 },   // Scale down
    { duration: '2m', target: 10 },    // Recovery period
    { duration: '30s', target: 500 },  // Second spike
    { duration: '1m', target: 500 },   // Hold second spike
    { duration: '1m', target: 0 },     // Scale down to 0
  ],

  thresholds: {
    http_req_failed: ['rate<0.15'],     // Up to 15% errors during spike
    http_req_duration: ['p(95)<3000'],  // 3s at p95 during spike
  },

  tags: {
    test_type: 'spike',
  },
};

export default function () {
  // Simple request during spike
  const res = http.get(`${BASE_URL}/api/products`, { headers });

  check(res, {
    'status is 200 or 503': (r) => [200, 503].includes(r.status),
    'response time acceptable': (r) => r.timings.duration < 5000,
  });

  // Minimal sleep during spike test
  sleep(0.5);
}
```

#### Create Soak Test

**Create `tests/load/scenarios/soak.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

/**
 * Soak Test (Endurance Test)
 *
 * Purpose: Test system stability over extended period.
 * Identifies memory leaks, resource exhaustion, and degradation over time.
 *
 * Usage: k6 run tests/load/scenarios/soak.k6.js
 * Note: This test runs for 2+ hours
 */

export const options = {
  stages: [
    { duration: '5m', target: 100 },    // Ramp up
    { duration: '2h', target: 100 },    // Hold for 2 hours
    { duration: '5m', target: 0 },      // Ramp down
  ],

  thresholds: {
    http_req_failed: ['rate<0.01'],     // Very strict - 1% error rate
    http_req_duration: ['p(95)<500'],   // Consistent performance
    http_req_duration: ['p(99)<1000'],  // No degradation over time
  },

  tags: {
    test_type: 'soak',
  },
};

export default function () {
  // Realistic user journey
  const endpoints = [
    '/api/products',
    '/api/users',
    '/api/orders',
    '/api/categories',
  ];

  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  const res = http.get(`${BASE_URL}${endpoint}`, { headers });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'consistent response time': (r) => r.timings.duration < 500,
  });

  // Realistic think time
  sleep(Math.random() * 5 + 2);
}
```

### Phase 5: CI/CD Integration

**Create `.github/workflows/load-tests.yml`:**

```yaml
name: Load Tests

on:
  # Manual trigger for full load tests
  workflow_dispatch:
    inputs:
      test_type:
        description: 'Test type to run'
        required: true
        default: 'smoke'
        type: choice
        options:
          - smoke
          - load
          - stress
          - spike
      environment:
        description: 'Target environment'
        required: true
        default: 'staging'
        type: choice
        options:
          - staging
          - production

  # Run smoke tests on PRs
  pull_request:
    paths:
      - 'src/**'
      - 'tests/load/**'

  # Scheduled load tests
  schedule:
    - cron: '0 3 * * 1'  # Weekly on Monday at 3 AM

jobs:
  smoke-test:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Start application
        run: |
          docker compose up -d
          sleep 30  # Wait for services

      - name: Run smoke test
        run: k6 run tests/load/scenarios/smoke.k6.js
        env:
          BASE_URL: http://localhost:3000

      - name: Upload results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: smoke-test-results
          path: results/

  load-test:
    if: github.event_name == 'workflow_dispatch' || github.event_name == 'schedule'
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'staging' }}
    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run load test
        run: |
          TEST_TYPE=${{ github.event.inputs.test_type || 'load' }}
          k6 run tests/load/scenarios/${TEST_TYPE}.k6.js \
            --out json=results/${TEST_TYPE}-results.json
        env:
          BASE_URL: ${{ vars.LOAD_TEST_URL }}

      - name: Upload results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: load-test-results
          path: results/

      - name: Post summary to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const results = JSON.parse(fs.readFileSync('results/load-test-summary.json'));

            const summary = `## Load Test Results

            | Metric | Value |
            |--------|-------|
            | Total Requests | ${results.metrics.http_reqs.values.count} |
            | Failed Requests | ${results.metrics.http_req_failed.values.rate.toFixed(4)} |
            | Avg Response Time | ${results.metrics.http_req_duration.values.avg.toFixed(2)}ms |
            | P95 Response Time | ${results.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms |
            | P99 Response Time | ${results.metrics.http_req_duration.values['p(99)'].toFixed(2)}ms |
            `;

            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: summary
            });

  # Optional: Run with k6 Cloud for distributed testing
  k6-cloud:
    if: github.event_name == 'workflow_dispatch' && github.event.inputs.test_type == 'stress'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          sudo gpg -k
          sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
          echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update
          sudo apt-get install k6

      - name: Run on k6 Cloud
        run: k6 cloud tests/load/scenarios/stress.k6.js
        env:
          K6_CLOUD_TOKEN: ${{ secrets.K6_CLOUD_TOKEN }}
          BASE_URL: ${{ vars.LOAD_TEST_URL }}
```

**Add npm scripts to `package.json`:**
```json
{
  "scripts": {
    "test:load:smoke": "k6 run tests/load/scenarios/smoke.k6.js",
    "test:load": "k6 run tests/load/scenarios/load.k6.js",
    "test:load:stress": "k6 run tests/load/scenarios/stress.k6.js",
    "test:load:spike": "k6 run tests/load/scenarios/spike.k6.js",
    "test:load:soak": "k6 run tests/load/scenarios/soak.k6.js",
    "test:load:all": "k6 run tests/load/scenarios/smoke.k6.js && k6 run tests/load/scenarios/load.k6.js"
  }
}
```

### Phase 6: HTML Reporting

**Install k6 HTML reporter:**
```bash
# The reporter is used via import in k6 scripts
# No installation needed, it's loaded from jslib
```

**Add to test scripts:**
```javascript
import { htmlReport } from 'https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js';

export function handleSummary(data) {
  return {
    'results/summary.html': htmlReport(data),
    'results/summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}
```

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  load_tests: "2025.1"
  load_tests_framework: "k6"
  load_tests_scenarios: ["smoke", "load", "stress"]
  load_tests_ci: true
  load_tests_thresholds: true
```

### Phase 8: Updated Compliance Report

```
Load Testing Configuration Complete
====================================

Framework: k6
Version: 0.50+

Configuration Applied:
  ✅ k6 installed
  ✅ TypeScript types configured
  ✅ Test directory structure created
  ✅ Base configuration created

Test Scenarios:
  ✅ smoke.k6.js - Minimal load validation
  ✅ load.k6.js - Normal load testing
  ✅ stress.k6.js - Breaking point detection
  ✅ spike.k6.js - Burst traffic simulation

Scripts Added:
  ✅ bun run test:load:smoke (quick validation)
  ✅ bun run test:load (normal load)
  ✅ bun run test:load:stress (find limits)
  ✅ bun run test:load:spike (burst traffic)

CI/CD:
  ✅ Smoke tests on PRs
  ✅ Scheduled weekly load tests
  ✅ Manual workflow dispatch
  ✅ Results artifact upload

Thresholds:
  ✅ http_req_failed < 1%
  ✅ http_req_duration p(95) < 500ms
  ✅ http_req_duration p(99) < 1000ms

Next Steps:
  1. Run smoke test locally:
     bun run test:load:smoke

  2. Run full load test:
     BASE_URL=https://staging.example.com bun run test:load

  3. View results:
     open results/summary.html

  4. Trigger CI load test:
     Use workflow_dispatch in GitHub Actions

Documentation:
  - k6: https://k6.io/docs
  - Grafana k6 Cloud: https://grafana.com/products/cloud/k6
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--framework <framework>` | Override framework (k6, artillery, locust) |

## Examples

```bash
# Check compliance and offer fixes
/configure:load-tests

# Check only, no modifications
/configure:load-tests --check-only

# Auto-fix all issues
/configure:load-tests --fix

# Force specific framework
/configure:load-tests --fix --framework artillery
```

## Error Handling

- **k6 not installed**: Provide installation instructions for platform
- **No target URL**: Prompt for BASE_URL configuration
- **Docker not available**: Suggest local app startup
- **CI secrets missing**: Provide setup instructions for k6 Cloud

## See Also

- `/configure:tests` - Unit testing configuration
- `/configure:integration-tests` - Integration testing
- `/configure:api-tests` - API contract testing
- `/configure:all` - Run all FVH compliance checks
- **k6 documentation**: https://k6.io/docs
- **k6 examples**: https://github.com/grafana/k6/tree/master/examples
- **Grafana k6 Cloud**: https://grafana.com/products/cloud/k6
