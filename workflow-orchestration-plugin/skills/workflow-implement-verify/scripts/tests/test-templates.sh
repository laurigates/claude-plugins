#!/usr/bin/env bash
# Regression tests for the workflow-implement-verify templates.
#   1. The Verify/Repair region is byte-identical in both templates, so a
#      repair-round run can consume an implement-verify run's rows.
#   2. Each template, run against a stub runtime, never lands a unit whose
#      verifier returned null (three ad-hoc repair runs read a dead verifier as
#      approval: `if (!v || v.approved)`), repairs at most once, never repairs a
#      `reject`, and aborts over its unit cap before spawning an agent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wf="$here/../../workflows"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }

region() { sed -n '/<shared:begin>/,/<shared:end>/p' "$1"; }
a="$(region "$wf/implement-verify.workflow.js")"
b="$(region "$wf/repair-round.workflow.js")"
if [[ -z "$a" ]]; then
  echo "FAIL shared region markers missing from implement-verify.workflow.js"; exit 1
fi
if [[ "$a" != "$b" ]]; then
  echo "FAIL shared Verify/Repair region differs between the two templates:"
  diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true
  exit 1
fi
echo "PASS shared region identical ($(printf '%s\n' "$a" | wc -l | tr -d ' ') lines)"

status=0
for t in implement-verify repair-round; do
  node "$here/run-template.mjs" "$wf/$t.workflow.js" || status=1
done
exit "$status"
