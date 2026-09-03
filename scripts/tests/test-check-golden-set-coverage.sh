#!/usr/bin/env bash
# Regression test for scripts/check-golden-set-coverage.sh.
#
# The defect: 16 canaries, exactly ONE with an evals.json, and the sweep gate is
# `eval_ready_count != '0'` -- so a 6% sweep ran green and filed an issue whose
# prompt said "Eval-ready canaries: 1" with no denominator. The ratio lived only
# in $GITHUB_STEP_SUMMARY, which no issue mirrors.
#
# The interesting property is that failing on the GAP was rejected: it would be
# red on arrival until 15 evals are written, and a permanently-red monthly audit
# gets switched off. So case A is load-bearing in the unusual direction -- the
# real repo, at 1 of 16, must be GREEN.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
CHECK="$repo_root/scripts/check-golden-set-coverage.sh"

pass=0; fail=0
assert() { if [ "$2" = "true" ]; then pass=$((pass+1)); else echo "FAIL: $1" >&2; fail=$((fail+1)); fi; }
has() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }

fx="$(mktemp -d)"; [ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

# stage <dir> <floor|none> <ready-count> -- a fixture repo with 16 canaries.
stage() {
  local d="$fx/$1" floor="$2" ready="$3" i=0
  mkdir -p "$d/evaluate-plugin" "$d/.github/workflows"
  {
    printf '{\n'
    [ "$floor" != none ] && printf '  "evalCoverageFloor": %s,\n' "$floor"
    printf '  "canaries": [\n'
    while [ $i -lt 16 ]; do
      [ $i -gt 0 ] && printf ',\n'
      printf '    {"skill": "p%d-plugin/s%d", "pattern": "x"}' "$i" "$i"
      i=$((i+1))
    done
    printf '\n  ]\n}\n'
  } > "$d/evaluate-plugin/golden-set.json"
  i=0
  while [ $i -lt "$ready" ]; do
    mkdir -p "$d/p${i}-plugin/skills/s${i}"
    echo '{}' > "$d/p${i}-plugin/skills/s${i}/evals.json"
    i=$((i+1))
  done
  # A workflow carrying all three invariants.
  cat > "$d/.github/workflows/golden-set-evaluation.yml" <<'WF'
name: x
on: {workflow_dispatch: {}}
jobs:
  gather:
    runs-on: ubuntu-latest
    outputs:
      eval_total_count: ${{ steps.c.outputs.eval_total_count }}
    steps:
      - id: c
        run: |
          floor="$(jq -r '.evalCoverageFloor // 0' evaluate-plugin/golden-set.json)"
          echo "::warning::sweep covers N of M canaries"
WF
}

# --- A: the real repo, at 1 of 16, must be GREEN ----------------------------
# A guard that failed here would be switched off before it ever caught anything.
echo "=== A: a standing coverage gap is NOT an error ==="
out="$(bash "$CHECK" 2>&1)"; rc=$?
assert "A exits 0 on the real repo" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "A STATUS=OK" "$(has "$out" 'STATUS=OK')"
# Non-vacuity: the gap must be REPORTED even though it is not an error, or the
# check is indistinguishable from one that measured nothing.
assert "A reports the real total" "$(has "$out" 'CANARIES_TOTAL=16')"
assert "A reports the real ready count" "$(has "$out" 'CANARIES_EVAL_READY=1')"
assert "A reports the declared floor" "$(has "$out" 'COVERAGE_FLOOR=1')"

# --- B: a REGRESSION below the floor is an error ----------------------------
echo "=== B: dropping below the declared floor fails ==="
stage b 3 1
out="$(bash "$CHECK" --project-dir "$fx/b" 2>&1)"; rc=$?
assert "B exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "B names the regression" "$(has "$out" 'coverage_below_floor')"
assert "B quotes both numbers" "$(has "$out" '1 of 16')"

# Guard integrity: the SAME fixture at a floor it meets must pass, so B's
# failure is attributable to the floor and not to the fixture being broken.
stage b_ok 1 1
out="$(bash "$CHECK" --project-dir "$fx/b_ok" 2>&1)"; rc=$?
assert "B a met floor passes" "$([ $rc -eq 0 ] && echo true || echo false)"

# --- C: an undeclared floor is an error -------------------------------------
# Undeclared intent is unauditable (.claude/rules/generated-fleet-drift.md).
echo "=== C: no declared floor is an error ==="
stage c none 8
out="$(bash "$CHECK" --project-dir "$fx/c" 2>&1)"; rc=$?
assert "C exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "C names floor_not_declared" "$(has "$out" 'floor_not_declared')"

# --- D: each workflow invariant is pinned independently ---------------------
# Strip one at a time, so a single missing property is attributable.
echo "=== D: the three workflow invariants ==="
for pair in "evalCoverageFloor|floor_not_read" "::warning::|no_partial_warning" "eval_total_count|denominator_missing"; do
  tok="${pair%%|*}"; want="${pair##*|}"
  stage "d_$want" 1 1
  wf="$fx/d_$want/.github/workflows/golden-set-evaluation.yml"
  grep -vF -- "$tok" "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
  out="$(bash "$CHECK" --project-dir "$fx/d_$want" 2>&1)"; rc=$?
  assert "D stripping $tok exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
  assert "D stripping $tok reports $want" "$(has "$out" "$want")"
done
# And the intact fixture must pass, or the three above prove nothing.
stage d_ok 1 1
out="$(bash "$CHECK" --project-dir "$fx/d_ok" 2>&1)"; rc=$?
assert "D an intact workflow passes" "$([ $rc -eq 0 ] && echo true || echo false)"

# --- E: unknown argument exits 2 (#2057) ------------------------------------
echo "=== E: unknown argument exits 2 ==="
out="$(bash "$CHECK" --nope 2>&1)"; rc=$?
assert "E exits 2" "$([ $rc -eq 2 ] && echo true || echo false)"
assert "E names the flag" "$(has "$out" 'unknown argument')"

echo ""
echo "PASSED=$pass"
echo "FAILED=$fail"
[ "$fail" -gt 0 ] && { echo "STATUS=FAIL"; exit 1; }
echo "STATUS=OK"
