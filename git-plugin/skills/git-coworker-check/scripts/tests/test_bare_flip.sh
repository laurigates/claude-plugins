#!/usr/bin/env bash
# Regression test for issue #1692: shared-checkout bare flip / leaked GIT_DIR.
#
# Symptom: a concurrent agent fleet sharing one checkout flips the repo to
# `core.bare = true` (or leaves a leaked GIT_DIR / GIT_WORK_TREE env pointing
# away from the repo). Every `git status` / `git commit` in every linked
# worktree then fails with "fatal: this operation must be run in a work tree".
#
# The prevention side (scripts/check-git-sandbox-guards.sh guarding mktemp -d
# sandboxes) already landed. This is the DETECTION side: detect-coworkers.sh must
# raise `bare_flip_suspected` so a session can notice the corruption and recover
# instead of misreading the cascade of git failures as its own fault.
#
# Run: bash git-plugin/skills/git-coworker-check/scripts/tests/test_bare_flip.sh

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
  cd "$dir" || return 1
  git init -q -b main
  # Test-only fixture config: throwaway repo in a temp dir, no upstream, no
  # need (and no way) to satisfy the harness's commit-signing server.
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
  git config tag.gpgsign false
}

# Case 1: a normal working checkout that has been flipped to core.bare=true.
# Detection must surface the flip and refuse a clear verdict.
bare_dir=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$bare_dir" ] || { echo "empty sandbox dir" >&2; exit 1; }
(
  init_test_repo "$bare_dir"
  : > .gitignore
  git add .gitignore
  git commit -q -m "init"
  # The corruption: a shared working checkout silently flipped to bare.
  git config core.bare true
)
out=$(bash "$script" --project-dir "$bare_dir")

assert_contains "bare-flip section is emitted" "$out" "=== BARE_FLIP_CHECK ==="
assert_contains "core.bare is reported true" "$out" "CORE_BARE=true"
assert_contains "bare flip is detected" "$out" "BARE_FLIP_DETECTED=true"
assert_contains "bare-flip count is non-zero" "$out" "BARE_FLIP_COUNT=1"
assert_contains "verdict flags the bare flip" "$out" "VERDICT=bare_flip_suspected"
assert_not_contains "clear verdict suppressed on a bare flip" "$out" "VERDICT=clear"

rm -rf "$bare_dir"

# Case 2: a normal (non-bare) checkout — the section appears but reports no flip,
# so the skill can rely on the section's presence as a contract.
clean_dir=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$clean_dir" ] || { echo "empty sandbox dir" >&2; exit 1; }
(
  init_test_repo "$clean_dir"
  : > .gitignore
  git add .gitignore
  git commit -q -m "init"
)
out=$(bash "$script" --project-dir "$clean_dir")

assert_contains "bare-flip section present on normal checkout" "$out" "=== BARE_FLIP_CHECK ==="
assert_contains "core.bare is reported false" "$out" "CORE_BARE=false"
assert_contains "no bare flip detected" "$out" "BARE_FLIP_DETECTED=false"
assert_contains "bare-flip count is zero" "$out" "BARE_FLIP_COUNT=0"
assert_contains "normal checkout verdicts to clear" "$out" "VERDICT=clear"

rm -rf "$clean_dir"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
