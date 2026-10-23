#!/usr/bin/env bash
# shellcheck disable=SC2016  # the effort assertions grep for a literal "$EFFORT" / "$E"
# Tests for scripts/model-compare/: both synthetic sets keep their grader
# contract (untouched fixture fails, fixture + reference scores 1.0), and the
# runners refuse bad arguments before spending anything. Makes no model calls.
#
# Run: bash evaluate-plugin/scripts/tests/test-model-compare.sh
# Exit 0 = all pass, 1 = failures
set -uo pipefail

MC="$(cd "$(dirname "$0")/../model-compare" && pwd)"
PASS=0
FAIL=0

check() { # name expected actual
    if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL: $1"; echo "  expected: $2"; echo "  actual:   $3"
    fi
}

out=$(bash "$MC/basic/validate.sh" 2>&1); rc=$?
check "basic set validates" "0" "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out"
check "basic set has 8 tasks" "8" "$(grep -cE ' (OK|FAIL)$' <<<"$out")"

out=$(bash "$MC/hard/validate.sh" 2>&1); rc=$?
check "hard set validates" "0" "$rc"
[ "$rc" = 0 ] || printf '%s\n' "$out"
check "hard set has 8 tasks" "8" "$(grep -cE ' (OK|FAIL)$' <<<"$out")"

# A grader must never crash on an empty workdir: missing deliverables are
# failed cases, and the last line is still a JSON score.
EMPTY=$(mktemp -d) || exit 1
trap 'rm -rf "$EMPTY"' EXIT
bad=0
for t in "$MC"/basic/tasks/*/ "$MC"/hard/tasks/*/; do
    last=$(cd "$EMPTY" && python3 -I "$t/check.py" "$EMPTY" 2>/dev/null | tail -1)
    python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert 0 <= d["score"] <= 1' "$last" 2>/dev/null || {
        bad=$((bad + 1)); echo "  no JSON score on empty workdir: $t"; }
done
check "graders score an empty workdir" "0" "$bad"

# Runners: usage errors exit 2 without launching anything.
bash "$MC/run_cell.sh" >/dev/null 2>&1
check "run_cell.sh no args" "2" "$?"
bash "$MC/run_cell.sh" "$MC/hard" no-such-task claude-haiku-5-5 1 >/dev/null 2>&1
check "run_cell.sh unknown task" "2" "$?"
bash "$MC/run_issue.sh" >/dev/null 2>&1
check "run_issue.sh no args" "2" "$?"
bash "$MC/run_issue.sh" 999999 claude-haiku-5-5 >/dev/null 2>&1
check "run_issue.sh unknown issue" "2" "$?"

# Every runner invocation pins effort and a spend cap.
check "run_cell pins effort" "1" "$(grep -c -- '--effort "\$EFFORT"' "$MC/run_cell.sh")"
check "run_cell caps spend" "1" "$(grep -c -- '--max-budget-usd "' "$MC/run_cell.sh")"
check "run_issue pins effort" "1" "$(grep -c -- '--effort "\$E"' "$MC/run_issue.sh")"
check "run_issue caps spend" "1" "$(grep -c -- '--max-budget-usd "' "$MC/run_issue.sh")"

echo "model-compare: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
