---
description: Check and configure Sentry error tracking for FVH standards
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite, WebSearch, WebFetch
argument-hint: "[--check-only] [--fix] [--type <frontend|python|node>]"
---

# /configure:sentry

Check and configure Sentry error tracking integration against FVH (Forum Virium Helsinki) standards.

## Context

This command validates Sentry SDK integration and configuration against FVH standards.

**Skills referenced**: `sentry` (MCP server for Sentry API)

## Version Checking

**CRITICAL**: Before configuring Sentry SDKs, verify latest versions:

1. **@sentry/vue** / **@sentry/react**: Check [npm](https://www.npmjs.com/package/@sentry/vue)
2. **@sentry/node**: Check [npm](https://www.npmjs.com/package/@sentry/node)
3. **sentry-sdk** (Python): Check [PyPI](https://pypi.org/project/sentry-sdk/)
4. **@sentry/vite-plugin**: Check [npm](https://www.npmjs.com/package/@sentry/vite-plugin)

Use WebSearch or WebFetch to verify current SDK versions before configuring Sentry.

## Workflow

### Phase 1: Project Type Detection

Determine project type to select appropriate SDK and configuration:

1. Check for `.fvh-standards.yaml` with `project_type` field
2. If not found, auto-detect:
   - **frontend**: Has `package.json` with vue/react dependencies
   - **node**: Has `package.json` with Node.js backend (express, fastify, etc.)
   - **python**: Has `pyproject.toml` or `requirements.txt`
3. Allow override via `--type` flag

### Phase 2: SDK Detection

Check for Sentry SDK installation:

**Frontend (Vue/React):**
- `@sentry/vue` or `@sentry/react` in package.json dependencies
- Check for `@sentry/vite-plugin` for source maps

**Node.js Backend:**
- `@sentry/node` in package.json dependencies
- Check for `@sentry/profiling-node` (recommended)

**Python:**
- `sentry-sdk` in pyproject.toml or requirements.txt
- Check for framework integrations (django, flask, fastapi)

### Phase 3: Configuration Analysis

**Environment Variable Checks:**
- `SENTRY_DSN` - Required, must be set via environment
- `SENTRY_ENVIRONMENT` - Recommended (development, staging, production)
- `SENTRY_RELEASE` - Recommended (auto-set by build)

**Frontend Configuration Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `import.meta.env.VITE_SENTRY_DSN` | FAIL if hardcoded |
| Source maps | Vite plugin configured | WARN if missing |
| Tracing | `tracesSampleRate` set | WARN if missing |
| Session replay | Replay integration | INFO (optional) |
| Release | Auto-injected by build | WARN if missing |

**Node.js Configuration Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `process.env.SENTRY_DSN` | FAIL if hardcoded |
| Init location | Before other imports | WARN if late |
| Tracing | `tracesSampleRate` set | WARN if missing |
| Profiling | Profiling integration | INFO (optional) |
| Release | Auto-set by CI/CD | WARN if missing |

**Python Configuration Checks:**

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env | `os.getenv('SENTRY_DSN')` | FAIL if hardcoded |
| Framework | Correct integration enabled | WARN if missing |
| Tracing | `traces_sample_rate` set | WARN if missing |
| Release | Auto-set by CI/CD | WARN if missing |

### Phase 4: Security Analysis

**Critical Security Checks:**

1. **No hardcoded DSN** - DSN must come from environment variables
2. **No DSN in git** - Verify DSN not committed in source files
3. **No secret in client** - Frontend DSN is public, but verify no auth tokens
4. **Sample rates** - Verify production sample rates are reasonable (not 1.0)

### Phase 5: Report Generation

```
FVH Sentry Compliance Report
============================
Project Type: frontend (detected)
SDK: @sentry/vue v8.30.0

Installation Status:
  @sentry/vue          v8.30.0       ✅ PASS
  @sentry/vite-plugin  v2.22.0       ✅ PASS

Configuration Checks:
  DSN from environment     ✅ PASS
  Source maps enabled      ✅ PASS
  Tracing configured       ⚠️ WARN (sample rate 0.0)
  Session replay           ⏭️ SKIP (optional)
  Release auto-injection   ✅ PASS

Security Checks:
  No hardcoded DSN         ✅ PASS
  No DSN in git history    ✅ PASS
  Sample rates reasonable  ⚠️ WARN (0.0 in production)

Missing Configuration:
  - tracesSampleRate should be > 0 for tracing

Recommendations:
  - Set tracesSampleRate: 0.1 for 10% sampling

Overall: 2 warnings
```

### Phase 6: Configuration (If Requested)

If `--fix` flag or user confirms:

1. **Missing SDK**: Add appropriate Sentry SDK to dependencies
2. **Missing Vite plugin**: Add `@sentry/vite-plugin` for source maps
3. **Missing config file**: Create Sentry initialization file
4. **Hardcoded DSN**: Replace with environment variable reference
5. **Missing sample rates**: Add recommended sample rates

**Frontend initialization template (Vue):**

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

**Python initialization template:**

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

**Node.js initialization template:**

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

### Phase 7: CI/CD Integration Check

Verify Sentry integration in CI/CD:

**GitHub Actions checks:**
- `SENTRY_AUTH_TOKEN` secret configured
- Source map upload step in build workflow
- Release creation on deploy

**Recommended workflow addition:**

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

### Phase 8: Standards Tracking

Update or create `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "frontend"
last_configured: "2025-11-30"
components:
  sentry: "2025.1"
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Override project type detection (frontend, python, node) |

## Examples

```bash
# Check compliance and offer fixes
/configure:sentry

# Check only, no modifications
/configure:sentry --check-only

# Auto-fix all issues
/configure:sentry --fix

# Force Python project type
/configure:sentry --type python
```

## Environment Variables

Required environment variables for Sentry:

| Variable | Description | Required |
|----------|-------------|----------|
| `SENTRY_DSN` | Sentry Data Source Name | Yes |
| `SENTRY_ENVIRONMENT` | Environment name | Recommended |
| `SENTRY_RELEASE` | Release version | Recommended |
| `SENTRY_AUTH_TOKEN` | Auth token for CI/CD | For source maps |

**Important:** Never commit DSN or auth tokens. Use environment variables or secrets management.

## Error Handling

- **No Sentry SDK**: Offer to install appropriate SDK for project type
- **Hardcoded DSN**: Report as FAIL, offer to fix with env var reference
- **Invalid DSN format**: Report error, provide DSN format guidance
- **Missing Sentry project**: Report warning, provide setup instructions

## See Also

- `/configure:all` - Run all FVH compliance checks
- `/configure:status` - Quick compliance overview
- `/configure:workflows` - GitHub Actions integration
- `sentry` MCP server - Sentry API access for project verification
