#!/usr/bin/env bash
# Test assertions use the `cmd && pass++ || fail` idiom deliberately (pass++ is
# arithmetic that always exits 0 here, so the || branch only runs on real
# failure) and pipe fixtures through cat for readability. Suppress the style
# nags rather than rewrite every assertion.
# shellcheck disable=SC2015,SC2002
#
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

# Good output: all 5 deterministic checks pass. gc-001's former bare-string
# "imperative mood" judge is now an absent_regex (#2667 rec 5), so nothing is
# deferred to the LLM judge and the status is OK rather than WARN.
good_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt")"
check "good: deterministic total" "5" "$(field "$good_out" DETERMINISTIC_TOTAL)"
check "good: deterministic passed" "5" "$(field "$good_out" DETERMINISTIC_PASSED)"
check "good: deterministic failed" "0" "$(field "$good_out" DETERMINISTIC_FAILED)"
check "good: judge pending" "0" "$(field "$good_out" JUDGE_PENDING)"
check "good: status" "OK" "$(field "$good_out" STATUS)"

# Bad output: all 5 deterministic checks fail -- including the imperative-mood
# check, which the past-tense "Added" in the bad fixture must trip.
bad_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt")"
check "bad: deterministic passed" "0" "$(field "$bad_out" DETERMINISTIC_PASSED)"
check "bad: deterministic failed" "5" "$(field "$bad_out" DETERMINISTIC_FAILED)"
check "bad: status" "ERROR" "$(field "$bad_out" STATUS)"

# --strict exits non-zero when a deterministic check fails.
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt" --strict >/dev/null
check "bad: --strict exit code" "1" "$?"
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt" --strict >/dev/null
check "good: --strict exit code" "0" "$?"

echo "=== TEST: stdin + JSON mode ==="
json_out="$(cat "$fixtures/gc-001-good.txt" | python3 "$grader" --evals "$evals" --eval-id gc-001 --output - --json)"
check "json: passed count" "5" "$(printf '%s' "$json_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["deterministic_passed"])')"

echo "=== TEST: abstention control (#2690) ==="
# Every assertion shape is positive (something must appear or match) and the
# judge passes only on evidence of satisfaction, so a case whose honest answer
# is "this cannot be done" has nothing to pass and a fabricated answer has
# nothing to fail. The control is an abstain case whose fabrication detector is
# an absent_regex: the fabricated answer FAILS it, the honest refusal PASSES it.
abstain_ids="$(python3 -c 'import json,sys; print(" ".join(e["id"] for e in json.load(open(sys.argv[1]))["evals"] if e.get("expected_outcome") == "abstain"))' "$evals")"
check "evals.json carries >=1 abstention case" "true" "$([ -n "$abstain_ids" ] && echo true || echo false)"
check "gc-006 is an abstention case" "true" "$(case " $abstain_ids " in *" gc-006 "*) echo true ;; *) echo false ;; esac)"

# A fabricated answer: a plausible commit message for changes that do not exist.
fab_out="$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-fabricated.txt")"
check "fabricated: expected outcome reported" "abstain" "$(field "$fab_out" EXPECTED_OUTCOME)"
check "fabricated: absent_regex fails" "true" "$(printf '%s\n' "$fab_out" | grep -q 'CHECK=absent_regex RESULT=FAIL' && echo true || echo false)"
check "fabricated: status" "ERROR" "$(field "$fab_out" STATUS)"
python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-fabricated.txt" --strict >/dev/null
check "fabricated: --strict exit code" "1" "$?"

# The honest refusal passes every deterministic check; only the judge half is
# deferred. Guard integrity: the total must be non-zero, or "0 failed" is
# what a case with no deterministic checks at all would also report.
ref_out="$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-refusal.txt")"
check "refusal: deterministic total" "2" "$(field "$ref_out" DETERMINISTIC_TOTAL)"
check "refusal: deterministic failed" "0" "$(field "$ref_out" DETERMINISTIC_FAILED)"
check "refusal: absent_regex passes" "true" "$(printf '%s\n' "$ref_out" | grep -q 'CHECK=absent_regex RESULT=PASS' && echo true || echo false)"
check "refusal: judge pending" "1" "$(field "$ref_out" JUDGE_PENDING)"
check "refusal: status" "WARN" "$(field "$ref_out" STATUS)"

# A satisfiable case reports comply (the default when the field is absent).
check "gc-001 reports comply" "comply" "$(field "$good_out" EXPECTED_OUTCOME)"
check "json: expected_outcome field" "abstain" "$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-refusal.txt" --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("expected_outcome"))')"

# A misspelled expected_outcome fails fast (exit 2) instead of silently grading
# the case as comply, which would fail an honest refusal on the judge half.
bad_evals="$(mktemp)"
[ -n "$bad_evals" ] || { echo "mktemp failed" >&2; exit 1; }
printf '%s\n' '{"evals":[{"id":"x-001","expected_outcome":"abstian","expectations":[]}]}' > "$bad_evals"
python3 "$grader" --evals "$bad_evals" --eval-id x-001 --output "$fixtures/gc-006-refusal.txt" >/dev/null 2>&1
check "invalid expected_outcome exit code" "2" "$?"
rm -f "$bad_evals"

# The judge half of the rule lives in an agent prompt, which
# plugin-compliance-check.sh's check_skill_body() cannot reach, so pin its
# load-bearing phrases here (the #2301 pattern for a prompt outside SKILL.md).
grader_md="$scripts_dir/../agents/eval-grader.md"
for tok in 'expected_outcome' 'the correct abstention is the passing response' 'A fabricated deliverable fails'; do
  grep -qF -- "$tok" "$grader_md" \
    && pass_count=$((pass_count + 1)) \
    || { echo "FAIL: eval-grader.md lost the abstention rule token '$tok'" >&2; fail_count=$((fail_count + 1)); }
done

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

# Executability flag (Slice 2): absent when haiku (0.7) is above the 0.5 floor.
printf '%s\n' "$report" | grep -q "executable_on_haiku=false" \
  && { echo "FAIL: example report should NOT fire executability flag (haiku 0.7 >= floor)" >&2; fail_count=$((fail_count + 1)); } \
  || pass_count=$((pass_count + 1))

echo "=== TEST: executability callout fires when haiku < floor < opus ==="
low_report="$(python3 "$renderer" "$fixtures/low-haiku-model-matrix.json")"
printf '%s\n' "$low_report" | grep -q "executable_on_haiku=false" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: low-haiku report missing executability flag (haiku 0.3 < 0.5 <= opus 0.9)" >&2; fail_count=$((fail_count + 1)); }
printf '%s\n' "$low_report" | grep -q "Executability flag" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: low-haiku report missing 'Executability flag' heading" >&2; fail_count=$((fail_count + 1)); }

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
