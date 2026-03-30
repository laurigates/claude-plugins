# TypeScript Sentry - Reference

Detailed reference material for Sentry SDK integration.

## Initialization Examples

### Bun Setup

Create `instrument.ts` in project root:

```typescript
import * as Sentry from "@sentry/bun";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.npm_package_version,

  // Performance monitoring (1.0 = 100% in dev, lower in prod)
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,

  // Send user IP and headers
  sendDefaultPii: true,

  // Enable log forwarding
  enableLogs: true,
});
```

Launch with preload:

```bash
bun --preload ./instrument.ts app.ts
```

### Node.js Setup

```typescript
import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV,
  release: process.env.npm_package_version,
  tracesSampleRate: 0.1,
  integrations: [
    Sentry.httpIntegration(),
    Sentry.expressIntegration(),
  ],
});
```

## Context & Enrichment

### Scoped Context

```typescript
Sentry.withScope((scope) => {
  scope.setTag("transaction", "checkout");
  scope.setExtra("cartValue", cart.total);
  scope.setUser({ id: user.id, email: user.email });

  Sentry.captureException(error);
});
```

### Global Tags

```typescript
Sentry.setTag("app.version", "2.1.0");
Sentry.setTag("deployment.region", "us-east-1");
```

### User Context

```typescript
Sentry.setUser({
  id: user.id,
  email: user.email,
  username: user.username,
  ip_address: "{{auto}}", // Captured automatically
});

// Clear on logout
Sentry.setUser(null);
```

### Breadcrumbs

Breadcrumbs are buffered until an error is captured:

```typescript
// Manual breadcrumb
Sentry.addBreadcrumb({
  category: "auth",
  message: "User logged in",
  level: "info",
  data: { method: "oauth", provider: "github" },
});

// Navigation breadcrumb
Sentry.addBreadcrumb({
  category: "navigation",
  message: "Navigated to /checkout",
  level: "info",
});

// HTTP breadcrumb (usually automatic)
Sentry.addBreadcrumb({
  category: "http",
  message: "POST /api/orders",
  level: "info",
  data: { status_code: 201 },
});
```

## Performance Monitoring

### Basic Span

```typescript
Sentry.startSpan(
  {
    op: "db.query",
    name: "SELECT users",
  },
  () => {
    return db.query("SELECT * FROM users");
  }
);
```

### Async Span

```typescript
const result = await Sentry.startSpan(
  {
    op: "http.client",
    name: "Fetch external API",
  },
  async () => {
    const response = await fetch("https://api.example.com/data");
    return response.json();
  }
);
```

### Nested Spans

```typescript
await Sentry.startSpan({ op: "task", name: "Process order" }, async () => {
  await Sentry.startSpan({ op: "db.query", name: "Fetch order" }, async () => {
    await db.query("SELECT * FROM orders WHERE id = ?", [orderId]);
  });

  await Sentry.startSpan({ op: "http.client", name: "Charge payment" }, async () => {
    await stripe.charges.create({ amount: order.total });
  });

  await Sentry.startSpan({ op: "queue.publish", name: "Send confirmation" }, async () => {
    await queue.publish("email.send", { orderId });
  });
});
```

### Span Attributes

```typescript
Sentry.startSpan(
  {
    op: "db.query",
    name: "Bulk insert",
    attributes: {
      "db.system": "postgresql",
      "db.operation": "INSERT",
      "db.rows_affected": records.length,
    },
  },
  () => db.batchInsert(records)
);
```

### Sampling Configuration

```typescript
Sentry.init({
  // Sample rate (0.0 - 1.0)
  tracesSampleRate: 0.1, // 10% of transactions

  // Or dynamic sampling
  tracesSampler: (samplingContext) => {
    // Always sample errors
    if (samplingContext.transactionContext?.name?.includes("error")) {
      return 1.0;
    }
    // Sample health checks less
    if (samplingContext.transactionContext?.name === "GET /health") {
      return 0.01;
    }
    // Default rate
    return 0.1;
  },
});
```

## Cron Monitoring

### withMonitor (Simplest)

```typescript
// Basic usage
Sentry.withMonitor("daily-cleanup", () => {
  await cleanupOldRecords();
});

// With configuration
Sentry.withMonitor(
  "hourly-sync",
  async () => {
    await syncExternalData();
  },
  {
    schedule: { type: "crontab", value: "0 * * * *" },
    checkinMargin: 5,  // Grace period (minutes)
    maxRuntime: 30,    // Timeout (minutes)
    timezone: "UTC",
  }
);
```

### Check-In Monitoring (Two-Step)

```typescript
const checkInId = Sentry.captureCheckIn({
  monitorSlug: "nightly-report",
  status: "in_progress",
});

try {
  await generateReport();

  Sentry.captureCheckIn({
    checkInId,
    monitorSlug: "nightly-report",
    status: "ok",
  });
} catch (error) {
  Sentry.captureCheckIn({
    checkInId,
    monitorSlug: "nightly-report",
    status: "error",
  });
  throw error;
}
```

### Auto-Instrument Cron Libraries

```typescript
// node-cron
import cron from "node-cron";
const instrumentedCron = Sentry.cron.instrumentNodeCron(cron);

instrumentedCron.schedule(
  "0 * * * *",
  () => processQueue(),
  { name: "queue-processor" }
);

// cron package
import { CronJob } from "cron";
const InstrumentedCronJob = Sentry.cron.instrumentCron(CronJob, "my-job");

new InstrumentedCronJob("0 0 * * *", () => dailyTask());
```

## Source Maps

### TypeScript Configuration

```json
{
  "compilerOptions": {
    "sourceMap": true,
    "inlineSources": true,
    "sourceRoot": "/",
    "noEmitHelpers": true,
    "importHelpers": true
  }
}
```

### Upload with Sentry CLI

```bash
# Install CLI
bun add -D @sentry/cli

# Inject debug IDs
npx sentry-cli sourcemaps inject ./dist

# Upload
npx sentry-cli sourcemaps upload ./dist \
  --release=$(npm pkg get version | tr -d '"') \
  --org=your-org \
  --project=your-project
```

### Automated with Wizard

```bash
npx @sentry/wizard@latest -i sourcemaps
```

### Environment Variables

```bash
# .env
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
SENTRY_ORG=your-org
SENTRY_PROJECT=your-project
SENTRY_AUTH_TOKEN=sntrys_xxx
```

## Integrations

### Bun Server (Automatic)

```typescript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [Sentry.bunServerIntegration()],
});

// Errors in Bun.serve() automatically captured
Bun.serve({
  port: 3000,
  fetch(req) {
    // Errors here are automatically reported
    return new Response("OK");
  },
});
```

### HTTP Client

```typescript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [
    Sentry.httpIntegration({
      tracing: true,
      breadcrumbs: true,
    }),
  ],
});
```

### Database (Prisma Example)

```typescript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  integrations: [Sentry.prismaIntegration()],
});
```

## Error Boundaries (React)

```tsx
import * as Sentry from "@sentry/react";

function App() {
  return (
    <Sentry.ErrorBoundary
      fallback={({ error, resetError }) => (
        <div>
          <p>Something went wrong</p>
          <button onClick={resetError}>Try again</button>
        </div>
      )}
      beforeCapture={(scope) => {
        scope.setTag("location", "app-root");
      }}
    >
      <MainContent />
    </Sentry.ErrorBoundary>
  );
}
```

## Next.js Setup

### File Structure

```
sentry.server.config.ts        # Node.js server runtime init
sentry.edge.config.ts          # Edge runtime init
src/
  instrumentation.ts            # Next.js register() hook — loads server/edge config
  instrumentation-client.ts     # Client-side Sentry init
  app/
    error.tsx                   # Route-level error boundary
    global-error.tsx            # Global error boundary
    layout.tsx                  # Include <SentryUserIdentity /> here
  lib/
    sentry/
      enrichment.ts             # Custom contexts, breadcrumbs, fingerprinting
      sentry-user-identity.tsx  # Syncs NextAuth session → Sentry user
```

### next.config.mjs Integration

```javascript
import { withSentryConfig } from "@sentry/nextjs"

const nextConfig = {
  serverExternalPackages: ["@sentry/profiling-node"],
  async headers() {
    return [
      { source: "/monitoring", headers: [{ key: "Cache-Control", value: "no-store" }] },
    ]
  },
}

const sentryOptions = {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  authToken: process.env.SENTRY_AUTH_TOKEN,
  silent: !process.env.CI,
  hideSourceMaps: true,
  tunnelRoute: "/monitoring",
  sourcemaps: { deleteSourcemapsAfterUpload: true },
  release: { name: version, setCommits: { auto: true, ignoreMissing: true } },
}

// Skip during container builds to save ~1GB memory
const skip = process.env.NEXT_PUBLIC_SENTRY_SKIP_BUILD === "1"
export default skip ? nextConfig : withSentryConfig(nextConfig, sentryOptions)
```

### Instrumentation Hook

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

### Next.js Error Boundaries

```tsx
// src/app/error.tsx — route-level
"use client"
import * as Sentry from "@sentry/nextjs"
import { useEffect } from "react"

export default function Error({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    Sentry.captureException(error, {
      tags: { errorBoundary: "route" },
      extra: { digest: error.digest },
    })
  }, [error])
  return <div><h2>Something went wrong</h2><button onClick={reset}>Try again</button></div>
}
```

### Router Transition Instrumentation

```typescript
// src/instrumentation-client.ts (at the end)
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart
```

## Structured Logging

Forward application logs to Sentry for correlation with errors and traces.

```typescript
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  enableLogs: true,

  // Filter logs before sending
  beforeSendLog(log) {
    const isProduction = process.env.NODE_ENV === "production"
    // Drop verbose logs in production
    if (isProduction && (log.level === "trace" || log.level === "debug")) {
      return null
    }
    // Strip sensitive attributes
    if (log.attributes) {
      for (const key of Object.keys(log.attributes)) {
        if (/password|token|secret|authorization|cookie/i.test(key)) {
          delete log.attributes[key]
        }
      }
    }
    return log
  },
})
```

## Profiling

### Node.js (Server-Side)

```typescript
import { nodeProfilingIntegration } from "@sentry/profiling-node"

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  profileSessionSampleRate: 1.0, // Profile 100% of sampled transactions
  profileLifecycle: "trace",      // Profile every traced request
  integrations: [nodeProfilingIntegration()],
})
```

For Next.js, add `@sentry/profiling-node` to `serverExternalPackages` (native bindings).

### Browser (Client-Side)

```typescript
Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  profileSessionSampleRate: 1.0,
  profileLifecycle: "trace",
  integrations: [Sentry.browserProfilingIntegration()],
})
```

Uses the JS Self-Profiling API (Chromium-based browsers only).

## Session Replay

```typescript
Sentry.init({
  replaysSessionSampleRate: 0.1, // 10% of sessions
  replaysOnErrorSampleRate: 1.0, // 100% when errors occur
  integrations: [
    Sentry.replayIntegration({
      maskAllText: true,   // Privacy: mask all text
      blockAllMedia: true, // Privacy: block media elements
    }),
  ],
})
```

## Feedback Widget

```typescript
Sentry.init({
  integrations: [
    Sentry.feedbackIntegration({
      colorScheme: "system",
      autoInject: true,
      enableScreenshot: true,
      showBranding: false,
      useSentryUser: true, // Pre-fill from Sentry.setUser()
    }),
  ],
})
```

## Event Filtering

### Error Filtering (beforeSend)

```typescript
Sentry.init({
  // Ignore known noise patterns
  ignoreErrors: [
    /chrome-extension:\/\//,
    /moz-extension:\/\//,
    "Network request failed",
    "Failed to fetch",
    "AbortError",
  ],

  // Strip sensitive data from events
  beforeSend(event) {
    const headers = event.request?.headers
    if (headers) {
      delete headers.authorization
      delete headers.cookie
      delete headers["x-api-key"]
    }
    return event
  },
})
```

### Transaction Filtering (beforeSendTransaction)

```typescript
Sentry.init({
  beforeSendTransaction(event) {
    const name = event.transaction
    // Drop health checks and static assets
    if (
      name?.startsWith("GET /api/health") ||
      name?.startsWith("GET /monitoring") ||
      name?.startsWith("GET /_next/")
    ) {
      return null
    }
    return event
  },
})
```

## Enrichment Helpers

### Custom Contexts

```typescript
// Domain-specific structured context
Sentry.setContext("ai_operation", {
  operation: "generate-description",
  model: "gpt-4",
  entityType: "theme",
  entityId: "theme-123",
})

Sentry.setContext("sync_operation", {
  source: "external-api",
  operation: "import",
  entityCount: 42,
})
```

### Breadcrumb Categories

```typescript
const CATEGORIES = {
  EXTERNAL_API: "external-api",
  AI_OPERATION: "ai-operation",
  SYNC_OPERATION: "sync-operation",
  AUTH: "auth",
} as const

Sentry.addBreadcrumb({
  category: CATEGORIES.EXTERNAL_API,
  message: "GET https://api.example.com/themes",
  level: "info",
  data: { service: "theme-api", method: "GET", status: 200 },
})
```

### Custom Fingerprinting

Group related errors by service instead of stack trace:

```typescript
function captureUpstreamError(error: Error, service: string, extra?: Record<string, unknown>) {
  Sentry.captureException(error, {
    fingerprint: ["upstream-service", service],
    tags: { errorType: "upstream", service },
    extra,
  })
}
```

### User Identity Sync (React/Next.js)

```tsx
"use client"
import * as Sentry from "@sentry/nextjs"
import { useSession } from "next-auth/react"
import { useEffect } from "react"

export function SentryUserIdentity() {
  const { data: session } = useSession()
  useEffect(() => {
    if (session?.user) {
      Sentry.setUser({ id: session.user.id, email: session.user.email ?? undefined })
    } else {
      Sentry.setUser(null)
    }
  }, [session])
  return null
}
```

### Fire-and-Forget Operations

Track non-critical background operations without blocking requests:

```typescript
function recordFireAndForgetFailure(
  error: unknown,
  context: { operation: string; entityType?: string; entityId?: string },
) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`[fire-and-forget] ${context.operation} failed:`, message)
  Sentry.addBreadcrumb({
    category: "fire-and-forget",
    level: "error",
    message: `${context.operation} failed: ${message}`,
    data: context,
  })
}
```

## Troubleshooting

### Events Not Appearing

```typescript
// Verify DSN
console.log("Sentry DSN:", process.env.SENTRY_DSN);

// Force flush before exit
await Sentry.close(2000);
```

### Source Maps Not Working

1. Verify `release` matches between SDK and CLI upload
2. Check source maps uploaded: Project Settings > Source Maps
3. Ensure `sourceMap: true` in tsconfig.json

### Performance Data Missing

- Don't set `tracesSampleRate: 0` (disables sampling, not tracing)
- Omit `tracesSampleRate` entirely to disable tracing
