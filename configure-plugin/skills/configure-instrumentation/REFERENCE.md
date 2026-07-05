# /configure:instrumentation Reference

Compliance tables and templates for the instrumentation check. Install
commands deliberately omit version pins — the package manager resolves
current versions, and lockfiles pin them.

## Compliance Tables

### Traces + Metrics (OpenTelemetry)

| Check | PASS | WARN | FAIL |
|-------|------|------|------|
| SDK installed | `@opentelemetry/sdk-node` / `opentelemetry-sdk` present | API-only (`@opentelemetry/api`) with no SDK | Absent |
| SDK started | Init file imports and starts the SDK | Init exists but not wired into the entrypoint | SDK installed, no init (`OTEL_INIT=false`) |
| Exporter | OTLP exporter + `OTEL_EXPORTER_OTLP_ENDPOINT` env | Console exporter only | Hardcoded collector URL with credentials |
| Service identity | `OTEL_SERVICE_NAME` set | Derived default name | Unset (spans land as `unknown_service`) |
| Sampling | `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + arg in prod | Always-on in prod (cost) | — |

### Structured Logging

| Check | PASS | WARN | FAIL |
|-------|------|------|------|
| Logger | pino/winston (Node), structlog/loguru (Python) | Framework default logger | `console.log` / `print` as the logging strategy |
| Format | JSON in production | Pretty-print everywhere | — |
| Trace correlation | `trace_id`/`span_id` injected into log records | — | — |

### Metrics

| Check | PASS | WARN | FAIL |
|-------|------|------|------|
| Export path | OTel metrics via OTLP, or prom-client/prometheus-client with `/metrics` | Custom StatsD-style counters | None |

### Error Tracking

`SENTRY_SDK=true` → delegate to `/configure:sentry` (SDK config, DSN hygiene,
source maps, sampling). This skill only reports presence/absence.

## Install Commands

| Stack | Command |
|-------|---------|
| Node (traces+metrics) | `npm install @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-http @opentelemetry/exporter-metrics-otlp-http` |
| Node (logging) | `npm install pino` (add `pino-pretty` as a dev dependency for local output) |
| Python (traces+metrics) | `uv add opentelemetry-sdk opentelemetry-exporter-otlp opentelemetry-instrumentation` plus framework instrumentors (e.g. `opentelemetry-instrumentation-fastapi`) |
| Python (logging) | `uv add structlog` |

## Init Templates

### Node — `instrumentation.ts` (NodeSDK)

```typescript
import { NodeSDK } from "@opentelemetry/sdk-node";
import { getNodeAutoInstrumentations } from "@opentelemetry/auto-instrumentations-node";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-http";
import { OTLPMetricExporter } from "@opentelemetry/exporter-metrics-otlp-http";
import { PeriodicExportingMetricReader } from "@opentelemetry/sdk-metrics";

const sdk = new NodeSDK({
  // Service name and OTLP endpoint come from OTEL_SERVICE_NAME /
  // OTEL_EXPORTER_OTLP_ENDPOINT — never hardcode them here.
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();

process.on("SIGTERM", () => {
  sdk.shutdown().finally(() => process.exit(0));
});
```

Load it **before** application code: `node --import ./instrumentation.js app.js`
(or `--require` for CJS). In Next.js, use the framework's `instrumentation.ts`
`register()` hook instead.

### Python — `telemetry.py`

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter


def init_telemetry() -> None:
    # Service name and endpoint come from OTEL_SERVICE_NAME /
    # OTEL_EXPORTER_OTLP_ENDPOINT — resource attrs from OTEL_RESOURCE_ATTRIBUTES.
    resource = Resource.create()

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)

    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[PeriodicExportingMetricReader(OTLPMetricExporter())],
    )
    metrics.set_meter_provider(meter_provider)
```

Zero-code alternative: `opentelemetry-instrument python app.py` (from
`opentelemetry-instrumentation`) auto-instruments installed frameworks with no
init file — acceptable, but the explicit init is easier to extend.

## Environment Configuration

`.env.example` block (real values live in secrets management):

```bash
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
# Production sampling: keep 10% of root traces, honor parent decisions
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=0.1
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=development
```

| Guidance | Detail |
|----------|--------|
| Endpoint | `4318` = OTLP/HTTP, `4317` = OTLP/gRPC; point at a collector, not directly at a vendor, when more than one backend may consume the data |
| Auth | Hosted collectors take `OTEL_EXPORTER_OTLP_HEADERS` (e.g. `authorization=Bearer <token>`) — a secret, never committed |
| Sampling | `parentbased_traceidratio` keeps trace trees intact; ratio 0.05–0.2 is a sane production start |

## Structured Logging Templates

### Node — pino with trace correlation

```typescript
import pino from "pino";
import { trace } from "@opentelemetry/api";

export const logger = pino({
  mixin() {
    const span = trace.getActiveSpan();
    if (!span) return {};
    const { traceId, spanId } = span.spanContext();
    return { trace_id: traceId, span_id: spanId };
  },
});
```

### Python — structlog with trace correlation

```python
import structlog
from opentelemetry import trace


def add_trace_context(logger, method_name, event_dict):
    span = trace.get_current_span()
    ctx = span.get_span_context()
    if ctx.is_valid:
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict


structlog.configure(
    processors=[
        add_trace_context,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ]
)
```

## Metrics Endpoint (non-OTel fallback)

When a Prometheus scrape endpoint is preferred over OTLP push:

| Stack | Pattern |
|-------|---------|
| Node | `prom-client` default registry + an HTTP `/metrics` route returning `register.metrics()` |
| Python | `prometheus-client` `make_asgi_app()` mounted at `/metrics` (FastAPI/Starlette) or `start_http_server(port)` |

Prefer the OTel SDK when traces are also wanted — one pipeline, one config
surface — and reserve the Prometheus clients for scrape-only environments.
