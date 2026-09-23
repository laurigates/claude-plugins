#!/usr/bin/env bash
# Assert every eval suite carries an impossible-task (abstention) control.
#
# The defect (issue #2690): every eval assertion shape is positive -- something
# must appear or match -- and the LLM grader passes an assertion only on
# evidence of satisfaction. So a case whose honest answer is "this cannot be
# done" has nothing to pass, and a fabricated answer has nothing to fail. A
# suite made only of satisfiable cases cannot tell a skill that invents output
# under pressure from one that refuses honestly, which is the opposite of what
# a gate is for.
#
# The control is a case marked `"expected_outcome": "abstain"`
# (evaluate-plugin/references/schemas.md). This guard pins, for every
# evals.json in the tree:
#
#   1. at least one case is an abstain case          (no_abstention_case)
#   2. every abstain case carries an absent_regex    (abstention_undetectable)
#      fabrication detector, so an invented deliverable FAILS for zero judge
#      tokens instead of resting on the probabilistic half alone
#   3. expected_outcome is comply or abstain         (expected_outcome_invalid)
#      -- a misspelled "abstian" would silently grade as comply
#   4. the file parses                                (evals_unparseable)
#
# New suites inherit the control from `/evaluate:skill --create-evals` (Step 3),
# which is told to generate one.
#
# Discovery runs from INSIDE the root against RELATIVE paths, so a scan root
# that is itself an agent worktree is not pruned as a whole (#2219), while a
# clone nested below it still is. A tree with no evals.json is legitimately
# empty and reported as SCANNED_EMPTY=true, not as a pass over nothing.
#
# Output follows .claude/rules/structured-script-output.md.
#
# Usage: check-evals-abstention.sh [--project-dir DIR]
# Exit:  0 every suite carries a detectable control, 1 one does not, 2 usage.
set -uo pipefail

ROOT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-evals-abstention.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      ROOT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "check-evals-abstention.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT_DIR" ] || ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR" || exit 2

# Counted in the loop, not via ${#files[@]}: expanding an empty array is an
# unbound-variable error under set -u on bash < 4.4 (#2333).
files=()
scanned=0
while IFS= read -r -d '' f; do
  files+=("${f#./}")
  scanned=$((scanned + 1))
done < <(find . \( -path '*/.claude/worktrees' -o -path './dist' -o -name node_modules -o -name .git \) -prune \
           -o -type f -name evals.json -print0 | LC_ALL=C sort -z)

# One python pass over every file: JSON is parsed, not grepped, so a pattern or
# assertion text that merely mentions "abstain" cannot satisfy the guard.
report="$(python3 - ${files[@]+"${files[@]}"} <<'PY'
import json
import sys

OUTCOMES = ("comply", "abstain")
files = sys.argv[1:]
with_abstention = 0
abstention_cases = 0
issues = []

for path in files:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as err:
        issues.append(("evals_unparseable", path, f"cannot parse: {err}"))
        continue
    cases = data.get("evals") if isinstance(data, dict) else None
    if not isinstance(cases, list):
        issues.append(("evals_unparseable", path, "no evals[] array"))
        continue
    abstain_here = 0
    for case in cases:
        if not isinstance(case, dict):
            continue
        case_id = case.get("id", "<no id>")
        outcome = case.get("expected_outcome", "comply")
        if outcome not in OUTCOMES:
            issues.append((
                "expected_outcome_invalid", path,
                f"case {case_id} has expected_outcome {outcome!r}; expected comply or abstain",
            ))
            continue
        if outcome != "abstain":
            continue
        abstain_here += 1
        expectations = case.get("expectations") or []
        detectable = any(
            isinstance(e, dict) and e.get("check") == "absent_regex" and e.get("pattern")
            for e in expectations
        )
        if not detectable:
            issues.append((
                "abstention_undetectable", path,
                f"abstain case {case_id} has no absent_regex, so a fabricated answer "
                "cannot fail deterministically",
            ))
    abstention_cases += abstain_here
    if abstain_here:
        with_abstention += 1
    else:
        issues.append((
            "no_abstention_case", path,
            "no case has expected_outcome abstain; add an impossible-task control "
            "whose honest answer is a refusal",
        ))

print(f"WITH={with_abstention}")
print(f"CASES={abstention_cases}")
for kind, path, msg in issues:
    print(f"ISSUE\t{kind}\t{path}\t{msg}")
PY
)"
py_rc=$?
if [ "$py_rc" -ne 0 ]; then
  echo "check-evals-abstention.sh: the analysis pass failed (python3 exit $py_rc)" >&2
  exit 2
fi

with="$(printf '%s\n' "$report" | sed -n 's/^WITH=//p')"
cases="$(printf '%s\n' "$report" | sed -n 's/^CASES=//p')"
issue_count=0
findings=""
while IFS=$'\t' read -r tag kind evals_path msg; do
  [ "$tag" = "ISSUE" ] || continue
  issue_count=$((issue_count + 1))
  findings="${findings}  - SEVERITY=ERROR TYPE=${kind} FILE=${evals_path} MSG=${msg}
"
done <<<"$report"

echo "=== EVALS ABSTENTION CONTROL ==="
echo "EVALS_FILES_SCANNED=$scanned"
echo "EVALS_FILES_WITH_ABSTENTION=${with:-0}"
echo "ABSTENTION_CASES=${cases:-0}"
if [ "$scanned" -eq 0 ]; then echo "SCANNED_EMPTY=true"; else echo "SCANNED_EMPTY=false"; fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%s' "$findings"
else
  echo "STATUS=OK"
fi
echo "=== END EVALS ABSTENTION CONTROL ==="

[ "$issue_count" -gt 0 ] && exit 1
exit 0
