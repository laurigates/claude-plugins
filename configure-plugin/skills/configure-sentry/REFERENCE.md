# Sentry Configuration Reference

## Configuration Check Tables

### Frontend Configuration Checks

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `import.meta.env.VITE_SENTRY_DSN` | FAIL if hardcoded |
| Source maps | Vite plugin configured | WARN if missing |
| Tracing | `tracesSampleRate` set | WARN if missing |
| Session replay | Replay integration | INFO (optional) |
| Release | Auto-injected by build | WARN if missing |

### Node.js Configuration Checks

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `process.env.SENTRY_DSN` | FAIL if hardcoded |
| Init location | Before other imports | WARN if late |
| Tracing | `tracesSampleRate` set | WARN if missing |
| Profiling | Profiling integration | INFO (optional) |
| Release | Auto-set by CI/CD | WARN if missing |

### Python Configuration Checks

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `os.getenv('SENTRY_DSN')` | FAIL if hardcoded |
| Framework | Correct integration enabled | WARN if missing |
| Tracing | `traces_sample_rate` set | WARN if missing |
| Release | Auto-set by CI/CD | WARN if missing |

## Report Template

```
Sentry Compliance Report
============================
Project Type: <type> (detected)
SDK: <sdk-name> <version>

Installation Status:
  <sdk-package>          <version>       PASS/FAIL
  <plugin-package>       <version>       PASS/FAIL

Configuration Checks:
  DSN from environment     PASS/FAIL
  Source maps enabled      PASS/WARN
  Tracing configured       PASS/WARN
  Session replay           PASS/SKIP
  Release auto-injection   PASS/WARN

Security Checks:
  No hardcoded DSN         PASS/FAIL
  No DSN in git history    PASS/FAIL
  Sample rates reasonable  PASS/WARN

Missing Configuration:
  - <item>

Recommendations:
  - <recommendation>

Overall: <N> warnings, <N> failures
```

## Initialization Templates

### Frontend (Vue)

```typescript
// src/sentry.ts
import * as Sentry from '@sentry/vue'
import type { App } from 'vue'

export function initSentry(app: App) {
  Sentry.init({
    app,
    dsn: import.meta.env.VITE_SENTRY_DSN,
    environment: import.meta.env.MODE,
    release: import.meta.env.VITE_SENTRY_RELEASE,
    integrations: [
      Sentry.browserTracingIntegration(),
    ],
    tracesSampleRate: import.meta.env.PROD ? 0.1 : 1.0,
  })
}
```

### Python

```python
# sentry_init.py
import os
import sentry_sdk

def init_sentry():
    sentry_sdk.init(
        dsn=os.getenv('SENTRY_DSN'),
        environment=os.getenv('SENTRY_ENVIRONMENT', 'development'),
        release=os.getenv('SENTRY_RELEASE'),
        traces_sample_rate=0.1 if os.getenv('SENTRY_ENVIRONMENT') == 'production' else 1.0,
    )
```

### Node.js

```javascript
// instrument.js (must be first import)
import * as Sentry from '@sentry/node'

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.SENTRY_RELEASE,
  tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1.0,
})
```

## CI/CD Integration

### Recommended GitHub Actions Workflow Addition

```yaml
- name: Create Sentry Release
  uses: getsentry/action-release@v1
  env:
    SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_AUTH_TOKEN }}
    SENTRY_ORG: your-org
    SENTRY_PROJECT: your-project
  with:
    environment: production
    sourcemaps: './dist'
```
