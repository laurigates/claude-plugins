#!/usr/bin/env bash
# blueprint-derive-tests analysis (read-only)
# Classifies fix/feat commits from git history, detects whether each commit
# carried an inline test-file change, and assigns a severity via the fixed
# matrix. The generative TRP document and recommendation output stay with
# the model — this script only emits the deterministic classification.
#
# Usage: bash blueprint-derive-tests.sh --project-dir <path> [--home-dir <path>] [--limit N]
#
# --project-dir is the git repo to analyse (the injectable seam: tests plant
# a tiny repo with feat/fix commits and point --project-dir at it so the run
# is fully offline). --limit caps how many commits are scanned (default 200).

set -uo pipefail

home_dir=""
project_dir=""
commit_limit="200"

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --limit) commit_limit="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== BLUEPRINT DERIVE-TESTS ==="

run_status="OK"
issue_count=0
issues_list=""

add_issue() {
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 $3\n"
  issue_count=$((issue_count + 1))
}

if ! command -v git >/dev/null 2>&1; then
  echo "GIT_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=git is required but not installed"
  echo "=== END BLUEPRINT DERIVE-TESTS ==="
  exit 1
fi
echo "GIT_AVAILABLE=true"

# A scanned commit is a gap iff it modified no test file. Severity matrix:
#   fix:  + no inline test file -> CRITICAL  (bug fix shipped untested)
#   feat: + no inline test file -> MEDIUM    (feature shipped untested)
#   any   + inline test file    -> (not a gap; classified COVERED)
classify_severity() {
  # $1 = commit type (fix|feat), $2 = has_test (true|false)
  if [ "$2" = "true" ]; then
    echo "COVERED"
  elif [ "$1" = "fix" ]; then
    echo "CRITICAL"
  else
    echo "MEDIUM"
  fi
}

git_dir="${project_dir}/.git"
if [ ! -d "$git_dir" ] && ! git -C "$project_dir" rev-parse --git-dir >/dev/null 2>&1; then
  echo "GIT_REPO=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=not_a_repo MSG=${project_dir} is not a git repository"
  echo "=== END BLUEPRINT DERIVE-TESTS ==="
  exit 1
fi
echo "GIT_REPO=true"

# Classify each fix/feat commit in scope and detect inline test changes.
fix_count=0; feat_count=0
critical_count=0; medium_count=0; covered_count=0
shas="$(git -C "$project_dir" log --format='%H %s' --max-count="$commit_limit" 2>/dev/null \
  | grep -E '^[a-f0-9]+ (fix|feat)(\([^)]*\))?(!)?:' || true)"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  commit_sha="${line%% *}"
  subject="${line#* }"
  case "$subject" in
    fix*) commit_type="fix"; fix_count=$((fix_count + 1)) ;;
    feat*) commit_type="feat"; feat_count=$((feat_count + 1)) ;;
    *) continue ;;
  esac

  # Inline test-file detection: did this commit touch a test path?
  # `git show --name-only` handles root commits (which `diff-tree -r` skips
  # without --root); `--format=` strips the commit header so only paths print.
  if git -C "$project_dir" show --name-only --format= "$commit_sha" 2>/dev/null \
       | grep -qE '(test|spec|_test\.|\.test\.|\.spec\.)'; then
    has_test="true"
  else
    has_test="false"
  fi

  severity="$(classify_severity "$commit_type" "$has_test")"
  case "$severity" in
    CRITICAL)
      critical_count=$((critical_count + 1))
      add_issue ERROR coverage_gap "SHA=${commit_sha:0:12} TYPE=fix SEVERITY=CRITICAL SUBJECT=${subject}"
      ;;
    MEDIUM)
      medium_count=$((medium_count + 1))
      add_issue WARN coverage_gap "SHA=${commit_sha:0:12} TYPE=feat SEVERITY=MEDIUM SUBJECT=${subject}"
      ;;
    COVERED)
      covered_count=$((covered_count + 1))
      ;;
  esac
done <<< "$shas"

echo "COMMIT_LIMIT=${commit_limit}"
echo "FIX_COMMITS=${fix_count}"
echo "FEAT_COMMITS=${feat_count}"
echo "GAPS_CRITICAL=${critical_count}"
echo "GAPS_MEDIUM=${medium_count}"
echo "COVERED_COMMITS=${covered_count}"
echo "GAPS_TOTAL=$((critical_count + medium_count))"

if [ "$critical_count" -gt 0 ]; then
  run_status="ERROR"
elif [ "$medium_count" -gt 0 ]; then
  run_status="WARN"
fi

echo "STATUS=${run_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  printf '%b' "$issues_list" | sed '/^$/d'
fi
echo "=== END BLUEPRINT DERIVE-TESTS ==="

[ "$run_status" = "ERROR" ] && exit 1
exit 0
