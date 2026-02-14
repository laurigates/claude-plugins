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
