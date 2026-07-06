#!/usr/bin/env bash
# Regression test for the code-hidden-failures ERRORS-track ast-grep rule
# project (issue #2010).
#
# Semantic invariants (not just "does it parse"):
#   1. Every rule in rules/lib/ matches its swallowed-error fixture (invalid)
#      and leaves the correct-handling fixture (valid) untouched — enforced by
#      `ast-grep test`.
#   2. Every rule ships with a matching test fixture (no rule lands untested).
#   3. `ast-grep scan -c rules/sgconfig.yml` runs clean and flags a known
#      swallowed error — the exact command the SKILL.md rewires to.
#
# The shell track stays grep-based (REFERENCE-shell.md + scan-shell.sh) and is
# intentionally NOT part of this rule project.
#
# SKIPs (exit 0) when ast-grep is absent, matching the skill's documented
# graceful-degradation fallback to the per-pattern flow.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules_dir="${script_dir}/../../rules"
sgconfig="${rules_dir}/sgconfig.yml"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

astgrep=""
if command -v ast-grep >/dev/null 2>&1; then
  astgrep="ast-grep"
elif command -v sg >/dev/null 2>&1; then
  astgrep="sg"
else
  echo "SKIP: ast-grep/sg not installed; cannot run code-hidden-failures rule tests"
  exit 0
fi

[ -f "$sgconfig" ] || fail "sgconfig.yml missing at $sgconfig"

rule_count=$(find "${rules_dir}/lib" -name '*.yml' -type f | wc -l | tr -d ' ')
test_count=$(find "${rules_dir}/tests" -name '*-test.yml' -type f | wc -l | tr -d ' ')
[ "$rule_count" -gt 0 ] || fail "no rule files found under rules/lib"
[ "$rule_count" = "$test_count" ] || \
  fail "rule/fixture count mismatch: $rule_count rules vs $test_count fixtures (every rule needs a *-test.yml)"
pass "every rule ($rule_count) has a matching test fixture"

missing=""
while IFS= read -r rf; do
  id="$(basename "$rf" .yml)"
  [ -f "${rules_dir}/tests/${id}-test.yml" ] || missing="${missing} ${id}"
done < <(find "${rules_dir}/lib" -name '*.yml' -type f)
[ -z "$missing" ] || fail "rules without a fixture:${missing}"
pass "each rule id maps to a tests/<id>-test.yml"

# Errors track covers four languages — assert the language spread survives edits.
for lang_prefix in js py go rs; do
  if ! find "${rules_dir}/lib" -name "${lang_prefix}-*.yml" -type f | grep -q .; then
    fail "errors track lost its ${lang_prefix}-* rules (js/py/go/rust must all be present)"
  fi
done
pass "errors track covers js, py, go, and rust"

if ! "$astgrep" test -c "$sgconfig" --skip-snapshot-tests >/tmp/hf-astgrep-test.$$.log 2>&1; then
  cat /tmp/hf-astgrep-test.$$.log >&2
  rm -f /tmp/hf-astgrep-test.$$.log
  fail "ast-grep test reported failing rule fixtures"
fi
rm -f /tmp/hf-astgrep-test.$$.log
pass "ast-grep test: all rule fixtures pass"

smoke_dir="$(mktemp -d)"
[ -n "$smoke_dir" ] || fail "mktemp failed"
trap 'rm -rf "$smoke_dir"' EXIT
printf 'try:\n    do_thing()\nexcept:\n    pass\n' > "${smoke_dir}/sample.py"
out="$("$astgrep" scan -c "$sgconfig" --json=compact "$smoke_dir" 2>/tmp/hf-scan-err.$$.log)"
scan_rc=$?
if [ "$scan_rc" -ne 0 ]; then
  cat /tmp/hf-scan-err.$$.log >&2
  rm -f /tmp/hf-scan-err.$$.log
  fail "ast-grep scan exited non-zero ($scan_rc)"
fi
rm -f /tmp/hf-scan-err.$$.log
if command -v jq >/dev/null 2>&1; then
  ids="$(printf '%s' "$out" | jq -r '.[].ruleId' | sort -u | tr '\n' ' ')"
  case "$ids" in
    *py-bare-except-pass*) pass "scan flags known swallowed errors on a sample (ids: $ids)" ;;
    *) fail "scan did not flag py-bare-except-pass on the sample (got: $ids)" ;;
  esac
else
  case "$out" in
    *py-bare-except-pass*) pass "scan flags known swallowed errors on a sample" ;;
    *) fail "scan did not flag py-bare-except-pass on the sample" ;;
  esac
fi

echo "OK: code-hidden-failures errors-track rule project ($rule_count rules) verified"
exit 0
