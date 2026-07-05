#!/usr/bin/env bash
# Regression test for configure-instrumentation.sh detection.
# Fixtures prove: a project with the OTel SDK + init file recommends
# "configured"; a bare project recommends "setup" (WARN); a Sentry-only or
# logger-only project recommends "partial" with the no_otel_sdk issue; a
# Python OTel project is detected through pyproject.toml.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../configure-instrumentation.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

[ -f "$check_script" ] || fail "configure-instrumentation.sh not found at $check_script"

# -----------------------------------------------------------------------------
# Case 1: OTel SDK + init file → RECOMMENDATION=configured, STATUS=OK
# -----------------------------------------------------------------------------
otel_proj="$(mktemp -d)"
[ -n "$otel_proj" ] || fail "mktemp -d returned empty"
trap 'rm -rf "$otel_proj"' EXIT
cat > "${otel_proj}/package.json" <<'JSON'
{"dependencies":{"@opentelemetry/sdk-node":"^0.52.0","@opentelemetry/api":"^1.9.0","@opentelemetry/exporter-trace-otlp-http":"^0.52.0","pino":"^9.0.0"}}
JSON
cat > "${otel_proj}/instrumentation.ts" <<'TS'
import { NodeSDK } from "@opentelemetry/sdk-node";
TS

out1="$(bash "$check_script" --home-dir "$HOME" --project-dir "$otel_proj")"
echo "$out1" | grep -q "^OTEL_SDK=true$" || fail "expected OTEL_SDK=true:\n$out1"
echo "$out1" | grep -q "^OTEL_INIT=true$" || fail "expected OTEL_INIT=true:\n$out1"
echo "$out1" | grep -q "^STRUCTURED_LOGGER=node$" || fail "expected STRUCTURED_LOGGER=node:\n$out1"
echo "$out1" | grep -q "^RECOMMENDATION=configured$" || fail "expected RECOMMENDATION=configured:\n$out1"
echo "$out1" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK:\n$out1"
pass "OTel SDK + init file recommends configured"
rm -rf "$otel_proj"

# -----------------------------------------------------------------------------
# Case 2: bare project → RECOMMENDATION=setup, STATUS=WARN
# -----------------------------------------------------------------------------
bare="$(mktemp -d)"
[ -n "$bare" ] || fail "mktemp -d returned empty"
printf '{}' > "${bare}/package.json"
out2="$(bash "$check_script" --home-dir "$HOME" --project-dir "$bare")"
echo "$out2" | grep -q "^OTEL_SDK=false$" || fail "expected OTEL_SDK=false:\n$out2"
echo "$out2" | grep -q "^RECOMMENDATION=setup$" || fail "expected RECOMMENDATION=setup:\n$out2"
echo "$out2" | grep -q "^STATUS=WARN$" || fail "expected STATUS=WARN:\n$out2"
echo "$out2" | grep -q "TYPE=no_instrumentation" || fail "expected no_instrumentation issue:\n$out2"
pass "bare project recommends setup"
rm -rf "$bare"

# -----------------------------------------------------------------------------
# Case 3: Sentry-only project → RECOMMENDATION=partial + no_otel_sdk issue
# -----------------------------------------------------------------------------
sentry_only="$(mktemp -d)"
[ -n "$sentry_only" ] || fail "mktemp -d returned empty"
printf '{"dependencies":{"@sentry/node":"^8.0.0"}}' > "${sentry_only}/package.json"
out3="$(bash "$check_script" --home-dir "$HOME" --project-dir "$sentry_only")"
echo "$out3" | grep -q "^SENTRY_SDK=true$" || fail "expected SENTRY_SDK=true:\n$out3"
echo "$out3" | grep -q "^RECOMMENDATION=partial$" || fail "expected RECOMMENDATION=partial:\n$out3"
echo "$out3" | grep -q "TYPE=no_otel_sdk" || fail "expected no_otel_sdk issue:\n$out3"
pass "sentry-only project recommends partial"
rm -rf "$sentry_only"

# -----------------------------------------------------------------------------
# Case 4: Python OTel via pyproject.toml + structlog → configured
# -----------------------------------------------------------------------------
py_proj="$(mktemp -d)"
[ -n "$py_proj" ] || fail "mktemp -d returned empty"
cat > "${py_proj}/pyproject.toml" <<'TOML'
[project]
dependencies = ["opentelemetry-sdk>=1.25", "opentelemetry-api>=1.25", "structlog>=24.0"]
TOML
cat > "${py_proj}/telemetry.py" <<'PY'
from opentelemetry import trace
PY
out4="$(bash "$check_script" --home-dir "$HOME" --project-dir "$py_proj")"
echo "$out4" | grep -q "^OTEL_SDK=true$" || fail "expected OTEL_SDK=true from pyproject:\n$out4"
echo "$out4" | grep -q "^STRUCTURED_LOGGER=python$" || fail "expected STRUCTURED_LOGGER=python:\n$out4"
echo "$out4" | grep -q "^RECOMMENDATION=configured$" || fail "expected RECOMMENDATION=configured for python fixture:\n$out4"
pass "python OTel project detected via pyproject.toml"
rm -rf "$py_proj"

echo "ALL TESTS PASSED"
