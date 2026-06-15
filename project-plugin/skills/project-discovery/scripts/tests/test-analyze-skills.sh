#!/usr/bin/env bash
# Regression test for analyze-skills.sh
#
# Run: bash project-plugin/skills/project-discovery/scripts/tests/test-analyze-skills.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers issue #1548 (analyze-skills.sh scans .claude/worktrees/ copies):
#   - A SKILL.md planted under .claude/worktrees/<name>/.../skills/ is NOT
#     counted, so TOTAL_SKILLS reflects only the real tree (not the N+1
#     inflation each linked worktree clone would add).
#   - No .claude/worktrees/ path leaks into the analyzer output.
# Same class as the #1492 worktree-prune fix for check-version-pin-coverage.sh.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/analyze-skills.sh"
PASS=0
FAIL=0

# Throwaway fake repo: one real skill, plus an identical worktree-clone copy
# that the analyzer must prune rather than double-count.
REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT
mkdir -p "$REPO/demo-plugin/skills/demo"
printf '# Demo skill\n\nReal skill in the working tree.\n' \
  > "$REPO/demo-plugin/skills/demo/SKILL.md"

# A linked worktree is a full repo clone — the same skill appears again under
# .claude/worktrees/<name>/. The analyzer must not walk it.
mkdir -p "$REPO/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo"
printf '# Demo skill\n\nWorktree clone copy — must be pruned.\n' \
  > "$REPO/.claude/worktrees/agent-deadbeef/demo-plugin/skills/demo/SKILL.md"

OUT=$(bash "$SCRIPT" "$REPO")

field() { echo "$OUT" | grep -E "^$1=" | head -1 | cut -d= -f2-; }

assert_eq() {
  local desc="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (want '%s', got '%s')\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== TEST: .claude/worktrees/ copies are pruned, not counted (#1548) ==="
assert_eq "TOTAL_SKILLS counts only the real skill (worktree clone pruned)" \
  "1" "$(field TOTAL_SKILLS)"

if echo "$OUT" | grep -q '/.claude/worktrees/'; then
  printf "  FAIL: no .claude/worktrees/ path leaks into output\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: no .claude/worktrees/ path leaks into output\n"; PASS=$((PASS + 1))
fi

echo ""
echo "PASS=$PASS"
echo "FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
