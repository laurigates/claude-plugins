#!/usr/bin/env bash
# Regression test for the code-antipatterns ast-grep rule project (issue #2010).
#
# Semantic invariants (not just "does it parse"):
#   1. Every rule in rules/lib/ matches its anti-pattern fixture (invalid) and
#      leaves the clean fixture (valid) untouched — enforced by `ast-grep test`.
#   2. Every rule ships with a matching test fixture (no rule can land untested).
#   3. `ast-grep scan -c rules/sgconfig.yml` runs clean and flags a known
#      anti-pattern sample — the exact command the SKILL.md rewires to.
#
# SKIPs (exit 0) when ast-grep is absent, matching the skill's documented
# graceful-degradation fallback to the per-pattern flow.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules_dir="${script_dir}/../../rules"
sgconfig="${rules_dir}/sgconfig.yml"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

# Resolve the ast-grep binary. It ships as both `ast-grep` and `sg`, but `sg`
# also collides with shadow-utils' set-group binary (present on Linux CI
# runners), so require the resolved command to self-identify as ast-grep before
# trusting it — otherwise SKIP cleanly rather than running the wrong binary.
astgrep=""
for cand in ast-grep sg; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" --version 2>/dev/null | grep -qiE '^ast[_-]?grep'; then
    astgrep="$cand"
    break
  fi
done
if [ -z "$astgrep" ]; then
  echo "SKIP: ast-grep not installed; cannot run code-antipatterns rule tests"
  exit 0
fi

[ -f "$sgconfig" ] || fail "sgconfig.yml missing at $sgconfig"

# Invariant 2: every rule has a fixture (rule count == fixture count, and each
# rule id has a same-named *-test.yml).
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

# Invariant 1: valid/invalid fixtures behave (semantic gate).
if ! "$astgrep" test -c "$sgconfig" --skip-snapshot-tests >/tmp/ap-astgrep-test.$$.log 2>&1; then
  cat /tmp/ap-astgrep-test.$$.log >&2
  rm -f /tmp/ap-astgrep-test.$$.log
  fail "ast-grep test reported failing rule fixtures"
fi
rm -f /tmp/ap-astgrep-test.$$.log
pass "ast-grep test: all rule fixtures pass"

# Invariant 3: the SKILL's scan command runs clean and flags a real sample.
smoke_dir="$(mktemp -d)"
[ -n "$smoke_dir" ] || fail "mktemp failed"
trap 'rm -rf "$smoke_dir"' EXIT
printf 'var x = 0;\nconsole.log(x);\ntry { risky(); } catch (e) { }\n' > "${smoke_dir}/sample.ts"
out="$("$astgrep" scan -c "$sgconfig" --json=compact "$smoke_dir" 2>/tmp/ap-scan-err.$$.log)"
scan_rc=$?
if [ "$scan_rc" -ne 0 ]; then
  cat /tmp/ap-scan-err.$$.log >&2
  rm -f /tmp/ap-scan-err.$$.log
  fail "ast-grep scan exited non-zero ($scan_rc)"
fi
rm -f /tmp/ap-scan-err.$$.log
if command -v jq >/dev/null 2>&1; then
  ids="$(printf '%s' "$out" | jq -r '.[].ruleId' | sort -u | tr '\n' ' ')"
  case "$ids" in
    *no-var*) : ;;
    *) fail "scan did not flag no-var on the sample (got: $ids)" ;;
  esac
  pass "scan flags known anti-patterns on a sample (ids: $ids)"
else
  case "$out" in
    *no-var*) pass "scan flags known anti-patterns on a sample" ;;
    *) fail "scan did not flag no-var on the sample" ;;
  esac
fi

echo "OK: code-antipatterns rule project ($rule_count rules) verified"
exit 0
