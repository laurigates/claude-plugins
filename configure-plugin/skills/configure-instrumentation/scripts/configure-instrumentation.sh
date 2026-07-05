#!/usr/bin/env bash
# Detect observability-instrumentation posture for a project.
# Scans --project-dir for OpenTelemetry SDK/init/env signals, structured
# loggers (pino/winston, structlog/loguru), metrics exporters
# (prom-client/prometheus-client), and Sentry SDK presence, then emits a
# recommendation over the detected booleans. Generative steps (writing init
# files and configs) stay with the model.
# Usage: bash configure-instrumentation.sh --home-dir <path> --project-dir <path>

set -uo pipefail

home_dir=""
project_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== CONFIGURE INSTRUMENTATION ==="

inst_issue_count=0
inst_status="OK"
inst_issues_list=""

add_issue() {
  inst_issues_list="${inst_issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  inst_issue_count=$((inst_issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    inst_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$inst_status" = "OK" ]; then
    inst_status="WARN"
  fi
}

exists_file() { [ -f "$1" ] && echo "true" || echo "false"; }

# Grep a dependency manifest quietly; false when the file is absent.
dep_present() {
  local pattern="$1"; shift
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    if grep -qE "$pattern" "$f" 2>/dev/null; then
      echo "true"
      return 0
    fi
  done
  echo "false"
}

pkg_json="${project_dir}/package.json"
pyproject="${project_dir}/pyproject.toml"
requirements="${project_dir}/requirements.txt"

echo "PACKAGE_JSON=$(exists_file "$pkg_json")"
echo "PYPROJECT=$(exists_file "$pyproject")"

# -----------------------------------------------------------------------------
# OpenTelemetry: SDK deps, init file, exporter env vars
# -----------------------------------------------------------------------------
otel_sdk=$(dep_present '@opentelemetry/(sdk-node|sdk-trace|auto-instrumentations)' "$pkg_json")
if [ "$otel_sdk" = "false" ]; then
  otel_sdk=$(dep_present 'opentelemetry-(sdk|distro)' "$pyproject" "$requirements")
fi
echo "OTEL_SDK=${otel_sdk}"

otel_api=$(dep_present '@opentelemetry/api' "$pkg_json")
if [ "$otel_api" = "false" ]; then
  otel_api=$(dep_present 'opentelemetry-api' "$pyproject" "$requirements")
fi
echo "OTEL_API=${otel_api}"

otel_exporter=$(dep_present '@opentelemetry/exporter' "$pkg_json")
if [ "$otel_exporter" = "false" ]; then
  otel_exporter=$(dep_present 'opentelemetry-exporter' "$pyproject" "$requirements")
fi
echo "OTEL_EXPORTER=${otel_exporter}"

otel_init="false"
otel_init_file=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qE '@opentelemetry/|opentelemetry\.' "$f" 2>/dev/null || grep -qE 'from opentelemetry|import opentelemetry' "$f" 2>/dev/null; then
    otel_init="true"
    otel_init_file="$f"
    break
  fi
done < <(find "$project_dir" -maxdepth 3 \
           \( -path '*/node_modules/*' -o -path '*/.venv/*' -o -path '*/.git/*' \) -prune -o \
           -type f \( -name 'otel*' -o -name '*telemetry*' -o -name 'tracing*' -o -name 'instrumentation*' \) -print 2>/dev/null)
echo "OTEL_INIT=${otel_init}"
[ -n "$otel_init_file" ] && echo "OTEL_INIT_FILE=${otel_init_file#"${project_dir}"/}"

otel_env="false"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if grep -qE 'OTEL_(EXPORTER_OTLP|SERVICE_NAME|RESOURCE_ATTRIBUTES)' "$f" 2>/dev/null; then
    otel_env="true"
    break
  fi
done < <(find "$project_dir" -maxdepth 3 \
           \( -path '*/node_modules/*' -o -path '*/.git/*' \) -prune -o \
           -type f \( -name '.env*' -o -path '*/.github/workflows/*' -o -name 'docker-compose*' -o -name '*.yaml' -o -name '*.yml' \) -print 2>/dev/null)
echo "OTEL_ENV=${otel_env}"

# -----------------------------------------------------------------------------
# Structured logging
# -----------------------------------------------------------------------------
structured_logger="false"
if [ "$(dep_present '"(pino|winston)"' "$pkg_json")" = "true" ]; then
  structured_logger="node"
elif [ "$(dep_present '(structlog|loguru)' "$pyproject" "$requirements")" = "true" ]; then
  structured_logger="python"
fi
echo "STRUCTURED_LOGGER=${structured_logger}"

# -----------------------------------------------------------------------------
# Metrics exporters (outside the OTel SDK)
# -----------------------------------------------------------------------------
metrics_exporter="false"
if [ "$(dep_present '"prom-client"' "$pkg_json")" = "true" ]; then
  metrics_exporter="prom-client"
elif [ "$(dep_present 'prometheus[-_]client' "$pyproject" "$requirements")" = "true" ]; then
  metrics_exporter="prometheus-client"
elif [ "$otel_sdk" = "true" ] && [ "$otel_exporter" = "true" ]; then
  metrics_exporter="otel"
fi
echo "METRICS_EXPORTER=${metrics_exporter}"

# -----------------------------------------------------------------------------
# Sentry (delegated to /configure:sentry for fixes; presence informs the report)
# -----------------------------------------------------------------------------
sentry_sdk=$(dep_present '@sentry/' "$pkg_json")
if [ "$sentry_sdk" = "false" ]; then
  sentry_sdk=$(dep_present 'sentry[-_]sdk' "$pyproject" "$requirements")
fi
echo "SENTRY_SDK=${sentry_sdk}"

# -----------------------------------------------------------------------------
# Recommendation over detected booleans
# -----------------------------------------------------------------------------
recommendation="setup"
if [ "$otel_sdk" = "true" ] && [ "$otel_init" = "true" ]; then
  recommendation="configured"
elif [ "$otel_sdk" = "true" ] || [ "$otel_init" = "true" ] || [ "$otel_env" = "true" ] || \
     [ "$structured_logger" != "false" ] || [ "$metrics_exporter" != "false" ] || [ "$sentry_sdk" = "true" ]; then
  recommendation="partial"
fi
echo "RECOMMENDATION=${recommendation}"

case "$recommendation" in
  setup)
    add_issue "WARN" "no_instrumentation" "no observability instrumentation detected — recommend OpenTelemetry + structured logging setup"
    ;;
  partial)
    if [ "$otel_sdk" = "false" ]; then
      add_issue "WARN" "no_otel_sdk" "no OpenTelemetry SDK detected — traces/metrics are vendor-locked or absent"
    elif [ "$otel_init" = "false" ]; then
      add_issue "WARN" "no_otel_init" "OpenTelemetry SDK installed but no init file found — SDK is never started"
    fi
    if [ "$structured_logger" = "false" ]; then
      add_issue "WARN" "no_structured_logger" "no structured logger detected (pino/winston or structlog/loguru)"
    fi
    ;;
esac

echo "STATUS=${inst_status}"
echo "ISSUE_COUNT=${inst_issue_count}"
if [ -n "$inst_issues_list" ]; then
  echo "ISSUES:"
  echo -e "$inst_issues_list" | sed '/^$/d'
fi
echo "=== END CONFIGURE INSTRUMENTATION ==="

[ "$inst_status" = "ERROR" ] && exit 1
exit 0
