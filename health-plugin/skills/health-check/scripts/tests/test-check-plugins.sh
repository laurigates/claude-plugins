#!/usr/bin/env bash
# shellcheck disable=SC2015 # `cmd && pass || fail` is the deliberate assertion idiom here
# Regression test for check-plugins.sh output contract (#3580).
# The script predated REASON=, so a WARN or ERROR said how many registry
# problems there were and never which. Every block must now pass
# scripts/check-structured-output-contract.sh --validate: canonical STATUS,
# ISSUE_COUNT equal to the ISSUES rows, REASON= on WARN/ERROR only, naming the
# first row at the reported severity.
# CHECK_PLUGINS_SCRIPT overrides the script under test (to replay a pre-fix copy).
# Hermetic: --home-dir / --project-dir point into a mktemp sandbox.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${CHECK_PLUGINS_SCRIPT:-${script_dir}/../check-plugins.sh}"
contract_script="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"

pass_count=0
fail_count=0
pass() { echo "PASS: $1"; pass_count=$((pass_count + 1)); }
fail() { printf 'FAIL: %b\n' "$1" >&2; fail_count=$((fail_count + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-plugins tests"
  exit 0
fi
[ -f "$check_script" ] || { echo "FAIL: $check_script not found" >&2; exit 1; }
[ -f "$contract_script" ] || { echo "FAIL: $contract_script not found" >&2; exit 1; }

tmp_root="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
{ [ -n "$tmp_root" ] && [ -d "$tmp_root" ]; } || { echo "FAIL: mktemp -d returned no directory" >&2; exit 1; }
trap 'rm -rf "$tmp_root"' EXIT

new_home() {
  local h="${tmp_root}/$1"
  mkdir -p "${h}/.claude/plugins" "${h}/proj"
  printf '%s' "$h"
}

run_check() {
  bash "$check_script" --home-dir "$1" --project-dir "$1/proj"
}

validate_contract() {  # $1 = label, $2 = output
  local verdict
  if verdict=$(bash "$contract_script" --validate - <<<"$2" 2>&1); then
    pass "$1: output satisfies the structured-output contract"
  else
    fail "$1: contract --validate rejected the output:\n$verdict\n$2"
  fi
}

# --- Case A: healthy registry, every enabled plugin installed -> OK, no REASON
h="$(new_home a)"
printf '{"plugins":{"one@m":[{"scope":"user"}]}}' > "$h/.claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"one@m":true}}' > "$h/.claude/settings.json"
out="$(run_check "$h")"
grep -q '^STATUS=OK$' <<<"$out" && ! grep -q '^REASON=' <<<"$out" \
  && pass "healthy registry gives STATUS=OK with no REASON" \
  || fail "case A expected STATUS=OK and no REASON:\n$out"
validate_contract "case A" "$out"

# --- Case B: missing registry -> WARN with REASON
h="$(new_home b)"
out="$(run_check "$h")"
grep -q '^STATUS=WARN$' <<<"$out" && grep -q '^REASON=missing_registry: ' <<<"$out" \
  && pass "missing registry gives WARN with REASON=missing_registry" \
  || fail "case B expected WARN + REASON=missing_registry:\n$out"
validate_contract "case B" "$out"

# --- Case C: invalid registry JSON -> ERROR with REASON, exit 1
h="$(new_home c)"
printf '{not json' > "$h/.claude/plugins/installed_plugins.json"
out="$(run_check "$h")"; rc=$?
[ "$rc" -eq 1 ] && grep -q '^STATUS=ERROR$' <<<"$out" && grep -q '^REASON=invalid_json: ' <<<"$out" \
  && pass "invalid registry gives ERROR with REASON=invalid_json, exit 1" \
  || fail "case C expected ERROR + REASON=invalid_json, exit 1 (rc=$rc):\n$out"
validate_contract "case C" "$out"

# --- Case D: orphaned entry + enabled-not-installed -> WARN, REASON names the
# first row with a (+1 more) tail
h="$(new_home d)"
printf '{"plugins":{"gone@m":[{"scope":"project","projectPath":"/nonexistent/proj-3580"}]}}' \
  > "$h/.claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"missing@m":true}}' > "$h/.claude/settings.json"
out="$(run_check "$h")"
grep -q '^STATUS=WARN$' <<<"$out" && grep -q '^ISSUE_COUNT=2$' <<<"$out" \
  && grep -q '^REASON=orphaned: .* (+1 more)$' <<<"$out" \
  && pass "two findings give REASON=orphaned: ... (+1 more), ISSUE_COUNT=2" \
  || fail "case D expected WARN, ISSUE_COUNT=2, REASON=orphaned: ... (+1 more):\n$out"
validate_contract "case D" "$out"

echo "PASSED=${pass_count} FAILED=${fail_count}"
[ "$fail_count" -eq 0 ]
