#!/usr/bin/env bash
# Regression test for issue #1319: transient worktree-isolation leak.
#
# Symptom: `Agent(isolation: "worktree")` briefly causes a file that the child
# wrote inside its worktree to appear as untracked in the parent checkout at the
# same relative path. The orphan vanishes once the child commits.
#
# Without the fifth signal, a naive `git status`-driven response would treat the
# orphan as user content and either stash, restore, or commit it onto the wrong
# branch. With the fifth signal, the detect script flags the leak so the
# orchestrator leaves the working tree alone.
#
# Run: bash git-plugin/skills/git-coworker-check/scripts/tests/test_worktree_leak.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script="$here/../detect-coworkers.sh"
fail=0
pass=0

assert_contains() {
  local label="$1"
  local out="$2"
  local needle="$3"
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %s: expected output to contain %s\n' "$label" "$needle"
    printf -- '--- output ---\n%s\n--- end ---\n' "$out"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local out="$2"
  local needle="$3"
  if printf '%s\n' "$out" | grep -qF -- "$needle"; then
    printf 'FAIL %s: expected output to NOT contain %s\n' "$label" "$needle"
    printf -- '--- output ---\n%s\n--- end ---\n' "$out"
    fail=$((fail + 1))
  else
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  fi
}

init_test_repo() {
  local dir="$1"
  cd "$dir"
  git init -q -b main
  # Test-only fixture config: throwaway repo in a temp dir, no upstream, no
  # need (and no way) to satisfy the harness's commit-signing server.
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
  git config tag.gpgsign false
}

setup_parent_with_worktree_leak() {
  local tmp leaked_path
  tmp=$(mktemp -d)
  leaked_path="health-plugin/skills/health-check/scripts/check-runtime.sh"

  # Parent repo with an initial commit so the worktree has a valid HEAD to branch from.
  (
    init_test_repo "$tmp"
    mkdir -p health-plugin/skills/health-check/scripts
    : > .gitignore
    git add .gitignore
    git commit -q -m "init"
  )

  # Child worktree under .claude/worktrees/ mirroring the real harness layout.
  (
    cd "$tmp"
    git worktree add -q -b worktree-agent-test .claude/worktrees/agent-test >/dev/null
    cd .claude/worktrees/agent-test
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    mkdir -p health-plugin/skills/health-check/scripts
    printf '#!/usr/bin/env bash\necho hi\n' > "$leaked_path"
    git add "$leaked_path"
    git commit -q -m "feat: add $leaked_path"
  )

  # Simulate the leak: the same path appears as an untracked file in the parent
  # while the child worktree holds the committed copy.
  printf '#!/usr/bin/env bash\necho hi\n' > "$tmp/$leaked_path"

  echo "$tmp"
}

# Case 1: parent sees an untracked file that matches a path committed in a
# child worktree under .claude/worktrees/. Detection must surface this as a
# worktree-leak candidate rather than silently classifying it as user drift.
parent_dir=$(setup_parent_with_worktree_leak)
out=$(bash "$script" --project-dir "$parent_dir")

assert_contains "leak section is emitted" "$out" "=== WORKTREE_LEAK_CHECK ==="
assert_contains "leaked path is reported" "$out" "WORKTREE_LEAK_PATH=health-plugin/skills/health-check/scripts/check-runtime.sh"
assert_contains "child worktree is named in the leak entry" "$out" "WORKTREE_LEAK_WORKTREE="
assert_contains "leak count is non-zero" "$out" "WORKTREE_LEAK_COUNT=1"
# Verdict must not silently swallow the leak — orchestrator needs visibility.
assert_not_contains "clear verdict suppressed when a leak is suspected" "$out" "VERDICT=clear"

rm -rf "$parent_dir"

# Case 2: clean parent with no leak — the section still appears but reports zero
# entries, so the skill can rely on the section's presence as a contract.
clean_dir=$(mktemp -d)
(
  init_test_repo "$clean_dir"
  : > .gitignore
  git add .gitignore
  git commit -q -m "init"
)
out=$(bash "$script" --project-dir "$clean_dir")
assert_contains "leak section present even on clean tree" "$out" "=== WORKTREE_LEAK_CHECK ==="
assert_contains "leak count is zero on clean tree" "$out" "WORKTREE_LEAK_COUNT=0"
assert_contains "clean tree verdicts to clear" "$out" "VERDICT=clear"
rm -rf "$clean_dir"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
