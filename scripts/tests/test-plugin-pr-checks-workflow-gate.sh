#!/usr/bin/env bash
# Regression test for the Claude Skill Quality Review OIDC gate in
# .github/workflows/plugin-pr-checks.yml (issues #1472, #1495, #1508).
#
# Root cause: when a PR modifies plugin-pr-checks.yml itself, GitHub blocks
# the OIDC token exchange that claude-code-action relies on, so the
# "Claude Skill Quality Review" step fails with a benign-but-red
# "Workflow validation failed" error.
#
# Fix: the `changed` step emits a `workflow_changed` output, and the Claude
# review step's `if:` skips when that output is true.
#
# This test guards both halves of the contract so a future edit can't silently
# drop the gate and let the failure recur.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
workflow="$repo_root/.github/workflows/plugin-pr-checks.yml"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { grep -qE "$1" "$workflow" && echo true || echo false; }
contains_fixed() { grep -qF "$1" "$workflow" && echo true || echo false; }

echo "=== TEST: workflow file exists ==="
assert "plugin-pr-checks.yml is present" "$([ -f "$workflow" ] && echo true || echo false)"

echo "=== TEST: changed step emits workflow_changed output ==="
assert "changed step writes workflow_changed to GITHUB_OUTPUT" \
  "$(contains 'workflow_changed=(true|false)')"

echo "=== TEST: workflow_changed is computed from a diff of this workflow file ==="
assert "diff targets plugin-pr-checks.yml" \
  "$(contains 'plugin-pr-checks\.yml')"

echo "=== TEST: Claude review step is gated on workflow_changed ==="
assert "Claude review if-condition references workflow_changed" \
  "$(contains_fixed "steps.changed.outputs.workflow_changed != 'true'")"

echo
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
