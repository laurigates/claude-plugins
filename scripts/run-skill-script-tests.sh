#!/usr/bin/env bash
# Run every skill-local regression test in the repo.
#
# Discovers and runs `*/skills/*/scripts/tests/test-*.sh`, the colocated tests
# that ship next to a skill's extracted scripts (canonical reference:
# health-plugin/skills/health-check/scripts/tests/test-check-settings.sh). Used
# by the `just test-skill-scripts` recipe and the `Test: Skill scripts` CI
# workflow so local and CI run the identical discovery (local↔CI parity).
#
# A test may SKIP (exit 0 with a SKIP line) when a dependency is absent; only a
# non-zero exit counts as a failure. Exits 0 when no tests are found (greenfield)
# so the runner is safe to wire in before any test exists.
#
# Usage: bash scripts/run-skill-script-tests.sh [--root <dir>]

set -uo pipefail

root_dir="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root_dir="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== SKILL SCRIPT TESTS ==="

failed=0
total=0
failed_list=""

# Prune `.claude/worktrees/` (sibling agent clones of the whole repo, #1492) so
# we don't run the same test many times over from worktree copies.
while IFS= read -r -d '' test_file; do
  total=$((total + 1))
  log_file="$(mktemp)"
  if bash "$test_file" >"$log_file" 2>&1; then
    echo "PASS=${test_file}"
  else
    echo "FAIL=${test_file}"
    sed 's/^/  | /' "$log_file"
    failed=$((failed + 1))
    failed_list="${failed_list}  - ${test_file}\n"
  fi
  rm -f "$log_file"
done < <(find "$root_dir" \
  -path '*/.claude/worktrees/*' -prune -o \
  -path '*/skills/*/scripts/tests/test-*.sh' -type f -print0 | sort -z)

echo "TOTAL=${total}"
echo "FAILED=${failed}"
if [ "$failed" -eq 0 ]; then
  echo "STATUS=OK"
else
  echo "STATUS=ERROR"
  echo "ISSUES:"
  printf '%b' "$failed_list"
fi
echo "=== END SKILL SCRIPT TESTS ==="

[ "$failed" -eq 0 ]
