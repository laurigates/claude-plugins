# Load Testing Configuration Reference

Detailed k6 test scripts, CI workflow templates, directory structure, and reporting configuration.

## k6 Installation

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

**TypeScript support:**
```bash
bun add --dev @types/k6
```

## Directory Structure

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

## Base Configuration

**`tests/load/config/base.js`:**
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

## Test Scenarios

### Smoke Test

**`tests/load/scenarios/smoke.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, thresholds, headers } from '../config/base.js';

export const options = {
  vus: 1,
  duration: '30s',
  thresholds: {
    ...thresholds,
    http_req_duration: ['p(95)<200'],
    http_req_failed: ['rate<0.001'],
  },
  tags: { test_type: 'smoke' },
};

export default function () {
  const healthRes = http.get(`${BASE_URL}/health`, { headers });
  check(healthRes, {
    'health check status is 200': (r) => r.status === 200,
    'health check response time < 100ms': (r) => r.timings.duration < 100,
  });

  const usersRes = http.get(`${BASE_URL}/api/users`, { headers });
  check(usersRes, {
    'users endpoint status is 200': (r) => r.status === 200,
    'users endpoint returns array': (r) => Array.isArray(r.json()),
  });

  sleep(1);
}

export function setup() {
  console.log(`Starting smoke test against ${BASE_URL}`);
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

### Load Test

**`tests/load/scenarios/load.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';
import { BASE_URL, thresholds, headers, getAuthHeaders } from '../config/base.js';

const apiErrors = new Counter('api_errors');
const successRate = new Rate('success_rate');
const userCreationTime = new Trend('user_creation_time');

export const options = {
  stages: [
    { duration: '2m', target: 50 },   // Ramp up
    { duration: '5m', target: 50 },   // Steady state
    { duration: '2m', target: 0 },    // Ramp down
  ],
  thresholds: {
    ...thresholds,
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    success_rate: ['rate>0.95'],
    api_errors: ['count<100'],
  },
  tags: { test_type: 'load' },
};

export default function () {
  group('Browse Products', () => {
    const listRes = http.get(`${BASE_URL}/api/products`, { headers });
    const listSuccess = check(listRes, {
      'products list status is 200': (r) => r.status === 200,
      'products list has items': (r) => r.json().length > 0,
    });
    successRate.add(listSuccess);
    if (!listSuccess) apiErrors.add(1);
    sleep(1);

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

  sleep(Math.random() * 3 + 1);
}

export function handleSummary(data) {
  return {
    'results/load-test-summary.json': JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: '  ', enableColors: true }),
  };
}

import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';
```

### Stress Test

**`tests/load/scenarios/stress.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

export const options = {
  stages: [
    { duration: '2m', target: 50 },
    { duration: '5m', target: 50 },
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 200 },
    { duration: '5m', target: 200 },
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.10'],
    http_req_duration: ['p(95)<2000'],
  },
  tags: { test_type: 'stress' },
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

### Spike Test

**`tests/load/scenarios/spike.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

export const options = {
  stages: [
    { duration: '1m', target: 10 },
    { duration: '30s', target: 500 },
    { duration: '1m', target: 500 },
    { duration: '30s', target: 10 },
    { duration: '2m', target: 10 },
    { duration: '30s', target: 500 },
    { duration: '1m', target: 500 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.15'],
    http_req_duration: ['p(95)<3000'],
  },
  tags: { test_type: 'spike' },
};

export default function () {
  const res = http.get(`${BASE_URL}/api/products`, { headers });
  check(res, {
    'status is 200 or 503': (r) => [200, 503].includes(r.status),
    'response time acceptable': (r) => r.timings.duration < 5000,
  });
  sleep(0.5);
}
```

### Soak Test

**`tests/load/scenarios/soak.k6.js`:**
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { BASE_URL, headers } from '../config/base.js';

export const options = {
  stages: [
    { duration: '5m', target: 100 },
    { duration: '2h', target: 100 },
    { duration: '5m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
    http_req_duration: ['p(99)<1000'],
  },
  tags: { test_type: 'soak' },
};

export default function () {
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

  sleep(Math.random() * 5 + 2);
}
```

## CI/CD Workflow

**`.github/workflows/load-tests.yml`:**

```yaml
name: Load Tests

on:
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

  pull_request:
    paths:
      - 'src/**'
      - 'tests/load/**'

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
          sleep 30

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
```

## npm Scripts

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

## HTML Reporting

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

## Compliance Report Template

```
Load Testing Compliance Report
===============================
Project: [name]
Framework: k6

Installation:
  k6 binary               /usr/local/bin/k6          [INSTALLED | MISSING]
  k6 version              0.50+                      [CURRENT | OUTDATED]
  TypeScript support      @types/k6                  [INSTALLED | OPTIONAL]

Test Scenarios:
  Smoke tests             tests/load/smoke.k6.js     [EXISTS | MISSING]
  Load tests              tests/load/load.k6.js      [EXISTS | MISSING]
  Stress tests            tests/load/stress.k6.js    [EXISTS | OPTIONAL]
  Spike tests             tests/load/spike.k6.js     [EXISTS | OPTIONAL]

Configuration:
  Thresholds              response time, error rate  [CONFIGURED | MISSING]
  Environments            staging, production        [CONFIGURED | MISSING]
  Data files              test-data.json             [EXISTS | N/A]

CI/CD Integration:
  GitHub Actions          load-test.yml              [CONFIGURED | MISSING]
  Scheduled runs          weekly/nightly             [CONFIGURED | OPTIONAL]
  PR gate                 smoke test on PR           [CONFIGURED | OPTIONAL]

Reporting:
  Console output          default                    [ENABLED | DEFAULT]
  JSON export             results.json               [CONFIGURED | MISSING]
  HTML report             k6-reporter                [CONFIGURED | OPTIONAL]

Overall: [X issues found]
```

## Load Testing Types

| Type | Purpose | VUs | Duration |
|------|---------|-----|----------|
| Smoke | Verify system works under minimal load | 1 | 30s |
| Load | Expected normal load | 50 | ~9m |
| Stress | Find breaking points | 50-200 | ~26m |
| Spike | Sudden traffic bursts | 10-500 | ~7m |
| Soak | Extended duration stability | 100 | ~2h10m |
