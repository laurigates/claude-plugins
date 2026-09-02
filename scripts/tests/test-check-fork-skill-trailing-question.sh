#!/usr/bin/env bash
# Regression test for scripts/check-fork-skill-trailing-question.sh
# (testing-plugin:test-analyze ended its context: fork body with a
# user-directed confirmation question — no channel back to the user exists
# in a forked subagent, 2026-09).
#
# Guards:
#   A. the real repo stays clean — no context: fork skill ends on a question
#   B. a context: fork skill ending on "Do you want me to…?" exits 1
#   C. a context: fork skill NOT ending on a question exits 0
#   D. a non-fork skill ending on the same question is NOT flagged (out of scope)
#   E. .claude/worktrees/ copies are pruned, not scanned
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-fork-skill-trailing-question.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

# make_skill <path> <context-line-or-empty> <last-body-line>
make_skill() {
  local dir
  dir="$(dirname "$1")"
  mkdir -p "$dir"
  {
    echo "---"
    echo "name: $(basename "$dir")"
    echo "description: Fixture skill for the fork-trailing-question test."
    [ -n "$2" ] && echo "$2"
    echo "allowed-tools: Read"
    echo "created: 2026-09-02"
    echo "modified: 2026-09-02"
    echo "reviewed: 2026-09-02"
    echo "---"
    echo ""
    echo "# Fixture Skill"
    echo ""
    echo "Some body text."
    echo ""
    echo "$3"
  } > "$1"
}

run() {
  local dir="$1"
  OUT="$(bash "$checker" --project-dir "$dir" 2>&1)"
  RC=$?
}

echo "=== TEST A: real repo is clean (no fork skill ends on a question) ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

fx_b="$(mktemp -d)"
fx_c="$(mktemp -d)"
fx_d="$(mktemp -d)"
fx_e="$(mktemp -d)"
trap 'rm -rf "$fx_b" "$fx_c" "$fx_d" "$fx_e"' EXIT

echo "=== TEST B: fork skill ending on a confirmation question exits 1 ==="
make_skill "$fx_b/demo-plugin/skills/bad-fork/SKILL.md" "context: fork" \
  "Do you want me to proceed with the analysis and planning, or would you like to review the plan first?"
run "$fx_b"
assert "bad-fork fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "bad-fork fixture names the offending file" "$(contains "$OUT" 'bad-fork/SKILL.md')"

echo "=== TEST C: fork skill NOT ending on a question exits 0 ==="
make_skill "$fx_c/demo-plugin/skills/good-fork/SKILL.md" "context: fork" \
  "Proceed with the analysis and planning now."
run "$fx_c"
assert "good-fork fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

echo "=== TEST D: non-fork skill ending on a question is out of scope ==="
make_skill "$fx_d/demo-plugin/skills/no-fork/SKILL.md" "" \
  "Do you want me to proceed, or would you like to review the plan first?"
run "$fx_d"
assert "non-fork fixture exits 0 (out of scope)" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "non-fork fixture checked 0 fork skills" "$(contains "$OUT" 'SKILLS_SCANNED=0')"

echo "=== TEST E: .claude/worktrees/ copies are pruned, not scanned ==="
make_skill "$fx_e/demo-plugin/skills/good-fork/SKILL.md" "context: fork" \
  "Proceed now."
make_skill "$fx_e/demo-plugin/.claude/worktrees/agent-deadbeef/skills/bad-fork/SKILL.md" "context: fork" \
  "Do you want me to proceed, or would you like to review the plan first?"
run "$fx_e"
assert "worktree fixture exits 0 (leaked copy pruned)" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "no .claude/worktrees/ path leaks into output" "$([ "$(contains "$OUT" '.claude/worktrees/')" = "false" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY: $pass_count passed, $fail_count failed ==="
[ "$fail_count" -eq 0 ]
