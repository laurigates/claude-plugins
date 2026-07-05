---
created: 2026-07-05
modified: 2026-07-05
reviewed: 2026-07-05
description: "Observability instrumentation: OpenTelemetry traces/metrics, structured logging, Sentry. Use when wiring telemetry, tracing, or logging into a repo."
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(bash *), Bash(npm *), Bash(bun *), Bash(uv *), AskUserQuestion, TodoWrite, SlashCommand, WebSearch, WebFetch
args: "[--check-only] [--fix] [--type <otel|logging|metrics|sentry>]"
argument-hint: "[--check-only] [--fix] [--type <otel|logging|metrics|sentry>]"
name: configure-instrumentation
---

# /configure:instrumentation

Check and upsert observability instrumentation — OpenTelemetry traces and
metrics, structured logging, and error tracking — against project standards.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Wiring up observability for a repo (traces, metrics, logs) in one pass | Only Sentry error tracking is needed (use `/configure:sentry`) |
| Checking what instrumentation a project already has | Debugging a live tracing/metrics pipeline (use the vendor's tools) |
| Adding vendor-neutral OpenTelemetry instead of a vendor-locked SDK | Load-testing performance (use `/configure:load-tests`) |
| Adding structured logging (pino/winston, structlog/loguru) | Profiling memory (use `/configure:memory-profiling`) |
| Standardizing `OTEL_*` env-var configuration and OTLP export | Managing dashboards/alerts in Grafana or the vendor UI |

## Context

- Package.json: !`find . -maxdepth 1 -name 'package.json'`
- Pyproject.toml: !`find . -maxdepth 1 -name 'pyproject.toml'`
- Project standards: !`find . -maxdepth 1 -name '.project-standards.yaml' -type f`
- OTel in package.json: !`find . -maxdepth 1 -name 'package.json' -exec grep -o '"@opentelemetry/[^"]*"' {} +`
- OTel in pyproject.toml: !`find . -maxdepth 1 -name 'pyproject.toml' -exec grep -o 'opentelemetry-[a-z-]*' {} +`
- Init candidates: !`find . -maxdepth 2 -type f \( -name 'otel*' -o -name '*telemetry*' -o -name 'tracing*' -o -name 'instrumentation*' \) -not -path '*/node_modules/*'`
- Structured loggers: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' \) -exec grep -oE '"(pino|winston)"|structlog|loguru' {} +`
- Sentry SDK: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' \) -exec grep -oE '@sentry/[a-z-]*|sentry-sdk' {} +`

## Parameters

Parse these from `$ARGUMENTS`:

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering fixes |
| `--fix` | Apply all fixes automatically without prompting |
| `--type <type>` | Restrict to one signal: `otel` (traces+metrics SDK), `logging`, `metrics`, `sentry` |

## Execution

Execute this instrumentation compliance check:

### Step 1: Run the detection script

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/configure-instrumentation.sh" --project-dir "$(pwd)"
```

The script emits `OTEL_SDK=`, `OTEL_INIT=`, `OTEL_ENV=`, `STRUCTURED_LOGGER=`,
`METRICS_EXPORTER=`, `SENTRY_SDK=`, and `RECOMMENDATION=configured|partial|setup`.
Use these booleans as the ground truth for the rest of the check — do not
re-derive detection by hand.

### Step 2: Detect language and framework

1. Read `.project-standards.yaml` for `project_type` if present
2. Node/TypeScript: `package.json` (Express/Fastify/Next.js shape decides the
   auto-instrumentation set)
3. Python: `pyproject.toml` or `requirements.txt` (Django/Flask/FastAPI decide
   the instrumentor packages)

### Step 3: Analyze against standards

Compare the detection output against the compliance tables in
[REFERENCE.md](REFERENCE.md). The standard posture is:

1. **Traces + metrics**: OpenTelemetry SDK installed, one init file that
   starts it (`instrumentation.ts` NodeSDK / `telemetry.py`), OTLP exporter
   configured via `OTEL_EXPORTER_OTLP_ENDPOINT` (never hardcoded endpoints)
2. **Sampling**: `OTEL_TRACES_SAMPLER` set for production (parentbased_traceidratio)
3. **Logging**: one structured logger (pino/winston or structlog/loguru)
   emitting JSON with trace correlation (trace_id/span_id fields)
4. **Metrics**: exported through the OTel SDK, or prom-client/prometheus-client
   with a `/metrics` endpoint
5. **Error tracking**: if `SENTRY_SDK=true`, delegate the Sentry compliance
   pass to `/configure:sentry --check-only` via the SlashCommand tool rather
   than re-checking it here

If `--type` was given, check only that signal.

### Step 4: Report results

Print a compliance report: per-signal status (PASS/WARN/FAIL), the
`RECOMMENDATION` verdict, and missing items. If `--check-only`, stop here.

### Step 5: Apply fixes (if --fix or user confirms)

Using the templates in [REFERENCE.md](REFERENCE.md):

1. **Missing OTel SDK**: add the SDK packages for the detected language
2. **Missing init**: create the init file (Node `instrumentation.ts` NodeSDK;
   Python `telemetry.py` or `opentelemetry-instrument` entrypoint)
3. **Missing env config**: add `OTEL_SERVICE_NAME` / `OTEL_EXPORTER_OTLP_*`
   to `.env.example` and deployment manifests — never commit real endpoints
   with credentials
4. **Missing structured logger**: add pino (Node) or structlog (Python) with
   the trace-correlation config
5. **Sentry gaps**: run `/configure:sentry --fix` via SlashCommand

### Step 6: Update standards tracking

Update or create `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
project_type: "<detected>"
last_configured: "<timestamp>"
components:
  instrumentation: "2025.1"
```

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `OTEL_SERVICE_NAME` | Logical service name on every span/metric | Yes |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OTLP collector endpoint | Yes |
| `OTEL_EXPORTER_OTLP_HEADERS` | Auth headers for a hosted collector | Vendor-dependent |
| `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG` | Production sampling | Recommended |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment=...` etc. | Recommended |

For SDK install commands, init templates, sampling guidance, logger
configuration, and metrics-endpoint patterns, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick posture check | `bash "${CLAUDE_SKILL_DIR}/scripts/configure-instrumentation.sh" --project-dir "$(pwd)"` |
| Full compliance check | `/configure:instrumentation --check-only` |
| Auto-fix everything | `/configure:instrumentation --fix` |
| Logging only | `/configure:instrumentation --type logging` |
| Error tracking only | `/configure:instrumentation --type sentry` |
| Find hardcoded OTLP endpoints | `rg -n 'OTEL_EXPORTER_OTLP_ENDPOINT.*https?://' --glob '!.env.example'` |

## Error Handling

- **No package manifest**: report "no instrumentable project detected" and stop
- **Both Node and Python present**: check both stacks, report per-stack status
- **OTel SDK present but never started** (`OTEL_INIT=false`): FAIL — an
  installed-but-unstarted SDK silently exports nothing

## See Also

- `/configure:sentry` - Sentry error-tracking setup (the vendor complement; this skill delegates Sentry fixes there)
- `/configure:all` - Run all compliance checks
- `/configure:status` - Quick compliance overview
- `typescript-plugin:typescript-sentry` - Day-to-day Sentry SDK usage patterns for Bun/Node/Next.js
