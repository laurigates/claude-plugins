#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level (must precede first command): the `[ -n ] && [ -d ] || { exit }` sandbox-dir guards are the intentional fail-fast idiom, not an if-then-else
# Regression test for issue #1745: test-bash-antipatterns.sh must not leak its
# sandbox git ops into a shared/real repo when GIT_DIR / GIT_WORK_TREE are
# inherited from the environment.
#
# THE BUG
# The suite builds throwaway repos with `git -C "$(mktemp -d)" init` / `git config`.
# An injected absolute GIT_DIR / GIT_WORK_TREE OVERRIDES `git -C`, so those ops
# target the real `.git` instead of the sandbox — flipping it to `core.bare=true`
# and injecting a junk `[user]` / `[commit]` identity into the shared config. In a
# shared checkout this breaks every worktree in the clone (the #1692 corruption
# class via a different vector than the empty-`mktemp -d` one).
#
# THE GUARD
# Stand up a throwaway "real" repo, snapshot its `.git/config`, then run the suite
# with GIT_DIR / GIT_WORK_TREE exported at it. The fix (`unset GIT_DIR GIT_WORK_TREE`
# at the top of the suite) means the config must be byte-identical afterward. Before
# the fix, the suite's `git config user.email …` writes land in the shared config
# and this test fails.
#
# Run: bash hooks-plugin/hooks/test-bash-antipatterns-git-env-isolation.sh
# Exit 0 = pass, Exit 1 = fail
set -euo pipefail

# This test's OWN setup builds a sandbox repo, so it must itself be robust against
# the inherited git context that pre-commit (or an agent) may have exported —
# otherwise its `git -C "$REAL" commit` would be hijacked before it can even probe
# the suite. Clean the full family up front; the injection it deliberately tests
# (GIT_DIR / GIT_WORK_TREE) is re-exported only in the suite-run subshell below.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SUITE="$(cd "$(dirname "$0")" && pwd)/test-bash-antipatterns.sh"
PASS=0
FAIL=0

echo "=== bash-antipatterns git-env isolation (#1745) ==="

# Guard the sandbox dir before any `git -C "$REAL" …` (#1692): if mktemp fails and
# REAL is empty, `git -C "" init` would fall back to the CWD and corrupt THIS repo.
REAL=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
[ -n "$REAL" ] && [ -d "$REAL" ] || { echo "FATAL: invalid sandbox dir '$REAL'" >&2; exit 1; }
trap 'rm -rf "$REAL"' EXIT

# Build a normal (non-bare) "real" repo and snapshot its config.
git -C "$REAL" init -q -b main
git -C "$REAL" config user.email real@example.com
git -C "$REAL" config user.name "Real User"
git -C "$REAL" config commit.gpgsign false
git -C "$REAL" commit -q --allow-empty -m seed

config_before=$(cat "$REAL/.git/config")

# Run the suite with the inherited-env hijack in place. We only care whether the
# shared config survives, not the suite's own pass/fail, so ignore its exit code
# and run it from a neutral cwd outside the real repo.
neutral=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
[ -n "$neutral" ] && [ -d "$neutral" ] || { echo "FATAL: invalid neutral dir" >&2; exit 1; }
trap 'rm -rf "$REAL" "$neutral"' EXIT

(
  cd "$neutral"
  export GIT_DIR="$REAL/.git"
  export GIT_WORK_TREE="$REAL"
  bash "$SUITE" >/dev/null 2>&1
) || true

config_after=$(cat "$REAL/.git/config")

assert() {
  local desc="$1" cond="$2"
  if [ "$cond" = "ok" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n" "$desc"; FAIL=$((FAIL + 1))
  fi
}

# 1. Config byte-identical — no sandbox git op leaked into the shared repo.
if [ "$config_before" = "$config_after" ]; then
  assert "shared .git/config is byte-identical after the suite runs under injected GIT_DIR" ok
else
  assert "shared .git/config is byte-identical after the suite runs under injected GIT_DIR" fail
  echo "    --- diff (before vs after) ---"
  diff <(printf '%s\n' "$config_before") <(printf '%s\n' "$config_after") | sed 's/^/    /' || true
fi

# 2. Repo was never flipped to bare (the headline #1692 symptom).
if [ "$(git -C "$REAL" rev-parse --is-bare-repository 2>/dev/null)" = "false" ]; then
  assert "real repo is still a work tree (core.bare not flipped to true)" ok
else
  assert "real repo is still a work tree (core.bare not flipped to true)" fail
fi

# 3. No junk identity injected over the seeded one.
if [ "$(git -C "$REAL" config user.email 2>/dev/null)" = "real@example.com" ]; then
  assert "seeded user.email is intact (no junk [user] injected)" ok
else
  assert "seeded user.email is intact (no junk [user] injected)" fail
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
