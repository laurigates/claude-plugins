#!/usr/bin/env bash
# test-check-blueprint-level3-templates.sh — regression tests for
# check-blueprint-level3-templates.sh (ADR-0020 level 3, issue #2005).
#
# Pins:
#   A. the real templates pass (STATUS=OK, exit 0)
#   B. stripping --model opus from an invocation fails
#   C. stripping the work-order-approved trigger fails
#   D. INLINING github.event.issue.body a second time (script-injection risk)
#      fails the "referenced exactly once" guard
#   E. removing the independent verify: job / state-packet field fails
#   F. dropping the top-level permissions: block fails

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-blueprint-level3-templates.sh"
REAL_TDIR="${REPO_ROOT}/blueprint-plugin/templates"

pass=0
fail=0
check() { # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
  fi
}

[ -f "$CHECK" ] || { echo "missing script: $CHECK" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Build a fixture project-dir with copies of the real templates, then mutate.
mk_fixture() { # mk_fixture <name>  -> echoes the fixture project dir
  local d="$WORK/$1"
  mkdir -p "$d/blueprint-plugin/templates"
  cp "$REAL_TDIR/blueprint-autorun.workflow.yml"     "$d/blueprint-plugin/templates/"
  cp "$REAL_TDIR/blueprint-wo-execute.workflow.yml"  "$d/blueprint-plugin/templates/"
  echo "$d"
}

run() { bash "$CHECK" --project-dir "$1" >/dev/null 2>&1; echo $?; }

# A. real templates pass
d=$(mk_fixture A)
check "A: real templates exit 0" "0" "$(run "$d")"

# B. strip --model opus from one autorun invocation
d=$(mk_fixture B)
sed -i.bak 's/--model opus --effort medium --max-turns 25/--effort medium --max-turns 25/' \
  "$d/blueprint-plugin/templates/blueprint-autorun.workflow.yml" && rm -f "$d"/blueprint-plugin/templates/*.bak
check "B: missing --model opus exit 1" "1" "$(run "$d")"

# C. strip the work-order-approved trigger
d=$(mk_fixture C)
sed -i.bak "s/work-order-approved/some-other-label/g" \
  "$d/blueprint-plugin/templates/blueprint-wo-execute.workflow.yml" && rm -f "$d"/blueprint-plugin/templates/*.bak
check "C: missing work-order-approved exit 1" "1" "$(run "$d")"

# D. inline the untrusted body a second time (script-injection regression)
d=$(mk_fixture D)
wo="$d/blueprint-plugin/templates/blueprint-wo-execute.workflow.yml"
# Deliberate literal ${{ }} — a second inlined body reference (the injection regression).
# shellcheck disable=SC2016
printf '          echo "%s"\n' '${{ github.event.issue.body }}' >> "$wo"
check "D: second body reference exit 1 (injection)" "1" "$(run "$d")"

# E. remove the state-packet field
d=$(mk_fixture E)
sed -i.bak "s/state-packet/status/g" \
  "$d/blueprint-plugin/templates/blueprint-wo-execute.workflow.yml" && rm -f "$d"/blueprint-plugin/templates/*.bak
check "E: missing state-packet exit 1" "1" "$(run "$d")"

# F. drop the top-level permissions block from autorun
d=$(mk_fixture F)
sed -i.bak "s/^permissions:/x_permissions:/" \
  "$d/blueprint-plugin/templates/blueprint-autorun.workflow.yml" && rm -f "$d"/blueprint-plugin/templates/*.bak
check "F: missing permissions exit 1" "1" "$(run "$d")"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
