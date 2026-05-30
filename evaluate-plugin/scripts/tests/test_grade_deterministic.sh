#!/usr/bin/env bash
# Regression test for grade_deterministic.py and render_matrix_report.py.
#
# Per .claude/rules/regression-testing.md, the deterministic grader (the
# token-frugality lever of the cross-model framework) ships with a test that
# proves: (a) machine-checkable assertions pass on good output, (b) they fail
# on bad output, (c) judge-typed assertions are deferred not graded, and
# (d) the matrix renderer produces the delta table.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$script_dir")"
fixtures="$script_dir/fixtures"
evals="$scripts_dir/../../git-plugin/skills/git-commit/evals.json"
grader="$scripts_dir/grade_deterministic.py"
renderer="$scripts_dir/render_matrix_report.py"

fail_count=0
pass_count=0

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() {
  # field <output> <KEY>  -> prints the value after KEY=
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2
}

echo "=== TEST: deterministic grading (gc-001) ==="

# Good output: all 4 deterministic checks pass, 1 judge deferred.
good_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt")"
check "good: deterministic total" "4" "$(field "$good_out" DETERMINISTIC_TOTAL)"
check "good: deterministic passed" "4" "$(field "$good_out" DETERMINISTIC_PASSED)"
check "good: deterministic failed" "0" "$(field "$good_out" DETERMINISTIC_FAILED)"
check "good: judge pending" "1" "$(field "$good_out" JUDGE_PENDING)"
check "good: status" "WARN" "$(field "$good_out" STATUS)"

# Bad output: all 4 deterministic checks fail.
bad_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt")"
check "bad: deterministic passed" "0" "$(field "$bad_out" DETERMINISTIC_PASSED)"
check "bad: deterministic failed" "4" "$(field "$bad_out" DETERMINISTIC_FAILED)"
check "bad: status" "ERROR" "$(field "$bad_out" STATUS)"

# --strict exits non-zero when a deterministic check fails.
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt" --strict >/dev/null
check "bad: --strict exit code" "1" "$?"
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt" --strict >/dev/null
check "good: --strict exit code" "0" "$?"

echo "=== TEST: stdin + JSON mode ==="
json_out="$(cat "$fixtures/gc-001-good.txt" | python3 "$grader" --evals "$evals" --eval-id gc-001 --output - --json)"
check "json: passed count" "4" "$(printf '%s' "$json_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["deterministic_passed"])')"

echo "=== TEST: matrix report rendering ==="
report="$(python3 "$renderer" "$fixtures/example-model-matrix.json")"
printf '%s\n' "$report" | grep -q "earns its keep" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing 'earns its keep' verdict" >&2; fail_count=$((fail_count + 1)); }
printf '%s\n' "$report" | grep -q "claude-opus-4-8" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing pinned model id" >&2; fail_count=$((fail_count + 1)); }
printf '%s\n' "$report" | grep -q "Portability flag" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing portability flag (opus-haiku spread = 30pts)" >&2; fail_count=$((fail_count + 1)); }

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
