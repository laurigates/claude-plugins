# Sentry Configuration Reference

## Configuration Check Tables

### Next.js Configuration Checks

| Check | Standard | Severity |
|-------|----------|----------|
| DSN from env (server) | `process.env.SENTRY_DSN` | FAIL if hardcoded |
| DSN from env (client) | `process.env.NEXT_PUBLIC_SENTRY_DSN` | FAIL if hardcoded |
| Server config | `sentry.server.config.ts` at root | FAIL if missing |
| Edge config | `sentry.edge.config.ts` at root | WARN if missing |
| Instrumentation hook | `src/instrumentation.ts` with `register()` | FAIL if missing |
| Client instrumentation | `src/instrumentation-client.ts` | FAIL if missing |
| withSentryConfig | `next.config.mjs` wraps with `withSentryConfig()` | FAIL if missing |
| Tunnel route | `tunnelRoute: "/monitoring"` | WARN if missing |
| Source maps hidden | `hideSourceMaps: true` | WARN if exposed |
| Source maps deleted | `deleteSourcemapsAfterUpload: true` | WARN if retained |
| Tracing | `tracesSampleRate` set (prod ≤ 0.2) | WARN if missing/high |
| Profiling (server) | `@sentry/profiling-node` + `nodeProfilingIntegration()` | INFO (optional) |
| Profiling (client) | `browserProfilingIntegration()` | INFO (optional) |
| Session replay | `replayIntegration()` | INFO (optional) |
| Structured logging | `enableLogs: true` | INFO (optional) |
| Error boundaries | `src/app/error.tsx` + `src/app/global-error.tsx` | WARN if missing |
| Sensitive header stripping | `beforeSend` removes auth/cookie headers | WARN if missing |
| Transaction filtering | `beforeSendTransaction` drops health/static | INFO (recommended) |
| External packages | `@sentry/profiling-node` in `serverExternalPackages` | FAIL if profiling used |
| Container build skip | `NEXT_PUBLIC_SENTRY_SKIP_BUILD` support | INFO (for Docker) |
| User identity sync | Component calling `Sentry.setUser()` | INFO (optional) |
| Enrichment helpers | Custom contexts, breadcrumb categories | INFO (optional) |
| Feedback widget | `feedbackIntegration()` | INFO (optional) |

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
  Profiling configured     PASS/SKIP
  Structured logging       PASS/SKIP
  Error boundaries         PASS/WARN
  Header stripping         PASS/WARN
  Transaction filtering    PASS/SKIP

Security Checks:
  No hardcoded DSN         PASS/FAIL
  No DSN in git history    PASS/FAIL
  Sample rates reasonable  PASS/WARN
  No auth tokens in client PASS/FAIL

Missing Configuration:
  - <item>

Recommendations:
  - <recommendation>

Overall: <N> warnings, <N> failures
```

## Initialization Templates

### Next.js — Server Config

```typescript
// sentry.server.config.ts (project root)
import * as Sentry from "@sentry/nextjs"
import { nodeProfilingIntegration } from "@sentry/profiling-node"

const isProduction = process.env.NODE_ENV === "production"

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  release: process.env.NEXT_PUBLIC_APP_VERSION,
  environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV,

  tracesSampleRate: isProduction ? 0.1 : 1.0,

  // Profiling
  profileSessionSampleRate: 1.0,
  profileLifecycle: "trace",

  // Structured logging
  enableLogs: true,
  beforeSendLog(log) {
    if (isProduction && (log.level === "trace" || log.level === "debug")) {
      return null // Drop verbose logs in production
    }
    return log
  },

  integrations: [
    Sentry.httpIntegration(),
    Sentry.onUnhandledRejectionIntegration(),
    nodeProfilingIntegration(),
  ],

  // Strip sensitive headers
  beforeSend(event) {
    const headers = event.request?.headers
    if (headers) {
      delete headers.authorization
      delete headers.cookie
      delete headers["x-api-key"]
    }
    return event
  },

  // Drop low-value transactions
  beforeSendTransaction(event) {
    const name = event.transaction
    if (
      name?.startsWith("GET /api/health") ||
      name?.startsWith("GET /monitoring") ||
      name?.startsWith("GET /_next/")
    ) {
      return null
    }
    return event
  },

  initialScope: {
    tags: {
      runtime: "nodejs",
      ...(process.env.HOSTNAME && { "k8s.pod": process.env.HOSTNAME }),
    },
  },
})
```

### Next.js — Edge Config

```typescript
// sentry.edge.config.ts (project root)
import * as Sentry from "@sentry/nextjs"

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  release: process.env.NEXT_PUBLIC_APP_VERSION,
  environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  enableLogs: true,
  initialScope: {
    tags: { runtime: "edge" },
  },
})
```

### Next.js — Client Instrumentation

```typescript
// src/instrumentation-client.ts
import * as Sentry from "@sentry/nextjs"

const isProduction = process.env.NODE_ENV === "production"

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment:
    process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT || process.env.NODE_ENV,

  tracesSampleRate: isProduction ? 0.1 : 1.0,

  // Session replay
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,

  // Profiling
  profileSessionSampleRate: 1.0,
  profileLifecycle: "trace",

  // Structured logging
  enableLogs: true,

  integrations: [
    Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
    Sentry.browserTracingIntegration(),
    Sentry.feedbackIntegration({
      colorScheme: "system",
      autoInject: true,
      enableScreenshot: true,
      showBranding: false,
    }),
    Sentry.browserProfilingIntegration(),
  ],

  ignoreErrors: [
    /chrome-extension:\/\//,
    /moz-extension:\/\//,
    "Network request failed",
    "Failed to fetch",
    "AbortError",
  ],
})

// Export for Next.js router transition instrumentation
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart
```

### Next.js — Server Instrumentation Hook

```typescript
// src/instrumentation.ts
import * as Sentry from "@sentry/nextjs"

export async function register() {
  if (process.env.NEXT_RUNTIME === "nodejs") {
    await import("../sentry.server.config")
  }
  if (process.env.NEXT_RUNTIME === "edge") {
    await import("../sentry.edge.config")
  }
}

export const onRequestError = Sentry.captureRequestError
```

### Next.js — next.config.mjs Integration

```javascript
// next.config.mjs
import { withSentryConfig } from "@sentry/nextjs"

const nextConfig = {
  // Keep @sentry/profiling-node unbundled (native bindings)
  serverExternalPackages: ["@sentry/profiling-node"],

  async headers() {
    return [
      {
        source: "/monitoring",
        headers: [{ key: "Cache-Control", value: "no-store" }],
      },
    ]
  },
}

const sentryOptions = {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  silent: !process.env.CI,
  disableServerWebpackPlugin: process.env.NODE_ENV !== "production",
  disableClientWebpackPlugin: process.env.NODE_ENV !== "production",
  disableLogger: true,
  hideSourceMaps: true,
  release: {
    name: version,
    setCommits: { auto: true, ignoreMissing: true },
  },
  tunnelRoute: "/monitoring",
  sourcemaps: { deleteSourcemapsAfterUpload: true },
}

// Skip Sentry plugin during container builds (saves ~1GB memory)
const skipSentry = process.env.NEXT_PUBLIC_SENTRY_SKIP_BUILD === "1"
export default skipSentry ? nextConfig : withSentryConfig(nextConfig, sentryOptions)
```

### Next.js — Error Boundaries

```tsx
// src/app/error.tsx
"use client"
import * as Sentry from "@sentry/nextjs"
import { useEffect } from "react"

export default function Error({
  error,
  reset,
}: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    Sentry.captureException(error, {
      tags: { errorBoundary: "route" },
      extra: { digest: error.digest },
    })
  }, [error])

  return (
    <div>
      <h2>Something went wrong</h2>
      <button onClick={reset}>Try again</button>
    </div>
  )
}
```

```tsx
// src/app/global-error.tsx
"use client"
import * as Sentry from "@sentry/nextjs"
import { useEffect } from "react"

export default function GlobalError({
  error,
  reset,
}: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    Sentry.captureException(error, {
      tags: { errorBoundary: "global" },
      extra: { digest: error.digest },
    })
  }, [error])

  return (
    <html>
      <body>
        <h2>Something went wrong</h2>
        <button onClick={reset}>Try again</button>
      </body>
    </html>
  )
}
```

### Next.js — User Identity Sync

```tsx
// src/lib/sentry/sentry-user-identity.tsx
"use client"
import * as Sentry from "@sentry/nextjs"
import { useSession } from "next-auth/react"
import { useEffect } from "react"

export function SentryUserIdentity() {
  const { data: session } = useSession()

  useEffect(() => {
    if (session?.user) {
      Sentry.setUser({
        id: session.user.id,
        email: session.user.email ?? undefined,
        username: session.user.name ?? undefined,
      })
    } else {
      Sentry.setUser(null)
    }
  }, [session])

  return null // Invisible component
}

// Include in root layout: <SentryUserIdentity />
```

### Next.js — Enrichment Helpers

```typescript
// src/lib/sentry/enrichment.ts
import * as Sentry from "@sentry/nextjs"

// --- User identity ---
export function setSentryUser(user: { id: string; email?: string; username?: string }) {
  Sentry.setUser(user)
}

export function clearSentryUser() {
  Sentry.setUser(null)
}

// --- Custom contexts ---
export function setSentryAIContext(data: {
  operation: string
  model: string
  entityType?: string
  entityId?: string
}) {
  Sentry.setContext("ai_operation", data)
}

export function setSentrySyncContext(data: {
  source: string
  operation: string
  entityCount?: number
  userId?: string
}) {
  Sentry.setContext("sync_operation", data)
}

// --- Breadcrumb categories ---
export const BREADCRUMB_CATEGORIES = {
  EXTERNAL_API: "external-api",
  AI_OPERATION: "ai-operation",
  SYNC_OPERATION: "sync-operation",
  AUTH: "auth",
} as const

export function addExternalApiBreadcrumb(data: {
  service: string
  method: string
  url: string
  status?: number
}) {
  Sentry.addBreadcrumb({
    category: BREADCRUMB_CATEGORIES.EXTERNAL_API,
    message: `${data.method} ${data.url}`,
    level: data.status && data.status >= 400 ? "error" : "info",
    data,
  })
}

// --- Custom fingerprinting for upstream errors ---
export function captureUpstreamError(
  error: Error,
  service: string,
  extra?: Record<string, unknown>,
) {
  Sentry.captureException(error, {
    fingerprint: ["upstream-service", service],
    tags: { errorType: "upstream", service },
    extra,
  })
}
```

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

### Next.js Container Build Optimization

For Docker builds where source map upload happens in CI (not during build):

```dockerfile
# Skip Sentry webpack plugin during container build
ARG NEXT_PUBLIC_SENTRY_SKIP_BUILD=1
```

This saves ~1GB memory and significant build time. Source maps are uploaded separately via CI/CD.

## Recommended Sample Rates

| Feature | Production | Development |
|---------|-----------|-------------|
| `tracesSampleRate` | 0.1 (10%) | 1.0 (100%) |
| `replaysSessionSampleRate` | 0.1 (10%) | 0.0 (disabled) |
| `replaysOnErrorSampleRate` | 1.0 (100%) | 1.0 (100%) |
| `profileSessionSampleRate` | 1.0 (of sampled) | 1.0 |
