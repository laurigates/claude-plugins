---
name: typescript-sentry
description: Error monitoring and performance tracking with Sentry SDK - error capture, breadcrumbs, performance spans, cron monitoring, source maps, structured logging, profiling, and enrichment helpers for Bun/Node.js/Next.js.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-22
modified: 2026-03-27
reviewed: 2026-01-22
---

# TypeScript Sentry

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Adding error monitoring to a project | Setting up logging (use a logger library) |
| Instrumenting performance spans | Monitoring infrastructure metrics (use Prometheus/Grafana) |
| Setting up cron job monitoring | Setting up uptime monitoring (use Pingdom/UptimeRobot) |
| Configuring source maps for Sentry | Debugging errors locally (use debugger) |
| Adding structured logging to Sentry | Configuring project-level Sentry compliance (use `/configure:sentry`) |
| Setting up profiling, replay, or enrichment helpers | Managing Sentry project settings in the dashboard |
| Implementing error/transaction filtering | Creating Sentry alerting rules |

## Core Expertise

Sentry provides error monitoring and performance tracking:
- Automatic error capture with stack traces
- Performance monitoring with distributed tracing
- Cron job monitoring for scheduled tasks
- Source map integration for readable TypeScript traces
- Rich context with tags, breadcrumbs, and user data
- Structured logging forwarded to Sentry (`enableLogs`)
- CPU/JS profiling (Node.js + browser)
- Session replay with privacy controls
- User feedback widget
- Enrichment helpers (custom contexts, breadcrumb categories, fingerprinting)

## Installation

### Bun

```bash
bun add @sentry/bun
```

### Node.js

```bash
bun add @sentry/node
```

### Next.js

```bash
bun add @sentry/nextjs @sentry/profiling-node
```

### React/Browser

```bash
bun add @sentry/react
# or
bun add @sentry/browser
```

## Error Capturing

### captureException

```typescript
try {
  await riskyOperation();
} catch (error) {
  Sentry.captureException(error);
  throw error; // Re-throw if needed
}
```

### With Context

```typescript
Sentry.captureException(error, {
  tags: {
    feature: "checkout",
    paymentProvider: "stripe",
  },
  extra: {
    orderId: order.id,
    userId: user.id,
    cartItems: cart.items.length,
  },
  level: "error", // fatal, error, warning, info, debug
});
```

### captureMessage

```typescript
// Simple message
Sentry.captureMessage("User completed onboarding");

// With level
Sentry.captureMessage("Rate limit approaching", "warning");

// With context
Sentry.captureMessage("Payment failed", {
  level: "error",
  tags: { gateway: "stripe" },
  extra: { errorCode: "card_declined" },
});
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Install Bun | `bun add @sentry/bun` |
| Install Node | `bun add @sentry/node` |
| Install Next.js | `bun add @sentry/nextjs @sentry/profiling-node` |
| Install React | `bun add @sentry/react` |
| Install CLI | `bun add -D @sentry/cli` |
| Upload maps | `npx sentry-cli sourcemaps inject ./dist && npx sentry-cli sourcemaps upload ./dist` |
| Setup wizard | `npx @sentry/wizard@latest -i sourcemaps` |
| Test capture | `Sentry.captureMessage("Test from dev")` |

## Quick Reference

### Capture Methods

| Method | Purpose |
|--------|---------|
| `captureException(error)` | Capture error with stack trace |
| `captureMessage(msg)` | Capture text message |
| `captureCheckIn(opts)` | Cron job check-in |
| `addBreadcrumb(crumb)` | Add navigation/action trail |

### Context Methods

| Method | Purpose |
|--------|---------|
| `setTag(key, value)` | Add filterable tag |
| `setExtra(key, value)` | Add debug data |
| `setUser(user)` | Set user context |
| `withScope(callback)` | Scoped context |

### Performance Methods

| Method | Purpose |
|--------|---------|
| `startSpan(opts, callback)` | Create performance span |
| `withMonitor(slug, callback)` | Monitor cron job |

### Severity Levels

| Level | Use Case |
|-------|----------|
| `fatal` | App crash, unrecoverable |
| `error` | Error requiring attention |
| `warning` | Potential issue |
| `info` | Informational |
| `debug` | Debugging only |

### Configuration Options

| Option | Description |
|--------|-------------|
| `dsn` | Project data source name |
| `environment` | Environment name (production, staging) |
| `release` | Application version |
| `tracesSampleRate` | Transaction sample rate (0.0-1.0) |
| `tracesSampler` | Dynamic sampling function |
| `sendDefaultPii` | Capture IP/headers |
| `integrations` | SDK integrations array |
| `enableLogs` | Forward structured logs to Sentry |
| `profileSessionSampleRate` | Profiling sample rate (0.0-1.0) |
| `profileLifecycle` | `"trace"` profiles every traced request |
| `replaysSessionSampleRate` | Session replay sample rate |
| `replaysOnErrorSampleRate` | Replay capture rate on errors |
| `ignoreErrors` | Array of error patterns to suppress |
| `beforeSend` | Filter/modify events before sending |
| `beforeSendTransaction` | Filter transactions before sending |
| `beforeSendLog` | Filter structured logs before sending |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).
