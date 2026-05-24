#!/usr/bin/env bash
# Regression tests for branch-protection.sh
#
# Run: bash hooks-plugin/hooks/test-branch-protection.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers:
#   - Inline `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git ...` prefix is NOT
#     honored (regression: subagents previously self-served this bypass).
#   - Process-environment `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1` IS still
#     honored (human-operator escape hatch).
#   - `git push origin main:fix/foo` with explicit refspec is allowed.
#   - Plain `git commit` / `git push` on main is denied.
#   - `git -C <feature-worktree> commit` from a cwd on main is allowed (#1389).
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-protection.sh"
PASS=0
FAIL=0

# Create a throwaway git repo on `main` so the hook's branch detection has
# something to find. Cleaned up on exit.
TEST_REPO=$(mktemp -d)
# Sibling worktrees used by the `-C <worktree>` regression tests (#1389):
#   FEATURE_WT — on `feature/probe`, writes should be allowed
#   MASTER_WT  — on `master`, writes should still be denied (negative case)
FEATURE_WT=$(mktemp -d)
MASTER_WT=$(mktemp -d)
trap 'rm -rf "$TEST_REPO" "$FEATURE_WT" "$MASTER_WT"' EXIT

git -C "$TEST_REPO" init -q -b main
git -C "$TEST_REPO" config user.email "test@example.com"
git -C "$TEST_REPO" config user.name "test"
git -C "$TEST_REPO" config commit.gpgsign false
git -C "$TEST_REPO" config tag.gpgsign false
git -C "$TEST_REPO" commit -q --allow-empty -m "init"

# Add linked worktrees. The TEST_REPO stays on `main`; tests then invoke
# `git -C "$FEATURE_WT" ...` from inside TEST_REPO and the hook must read
# the branch from the worktree, not the cwd. The MASTER_WT lets us assert
# the parser correctly *denies* when the target worktree is on a protected
# branch — proving it isn't a blanket bypass.
rmdir "$FEATURE_WT" "$MASTER_WT"
git -C "$TEST_REPO" worktree add -q -b feature/probe "$FEATURE_WT" >/dev/null
git -C "$TEST_REPO" worktree add -q -b master "$MASTER_WT" >/dev/null

# run_hook <command-string> [env-var-assignment...]
# Returns the hook's stdout (the JSON decision body, or empty for silent allow).
run_hook() {
  local cmd_str="$1"
  shift
  local input
  input=$(jq -nc --arg cmd "$cmd_str" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  (
    cd "$TEST_REPO"
    # Apply any extra env-var assignments passed as remaining args.
    # `export "KEY=VALUE"` is the intentional form here (the literal
    # KEY=VALUE string is the export arg, not the name of a variable).
    for assign in "$@"; do
      # shellcheck disable=SC2163
      export "$assign"
    done
    printf '%s' "$input" | bash "$HOOK"
  )
}

assert_deny() {
  local desc="$1" cmd_str="$2"
  shift 2
  local out
  out=$(run_hook "$cmd_str" "$@")
  if echo "$out" | grep -q '"permissionDecision":"deny"'; then
    printf "  PASS: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n        expected deny, got: %s\n" "$desc" "${out:-<empty>}"
    FAIL=$((FAIL + 1))
  fi
}

assert_allow() {
  local desc="$1" cmd_str="$2"
  shift 2
  local out
  out=$(run_hook "$cmd_str" "$@")
  # Allow = either silent (empty) or any non-deny JSON. The hook only emits
  # JSON for deny/ask, so a non-empty non-deny output would also be unexpected.
  if [ -z "$out" ]; then
    printf "  PASS: %s\n" "$desc"
    PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n        expected silent allow, got: %s\n" "$desc" "$out"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== branch-protection hook tests ==="

# ── inline-bypass regression ────────────────────────────────────────────────
# Regression: subagents bypassed this hook by prefixing their commands with
# CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1, committing to main. The hook used
# to honor this inline form. It must now be ignored so that agents cannot
# self-serve the bypass.
echo ""
echo "inline bypass regression (CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 prefix on the command must NOT bypass):"

assert_deny \
  "inline-prefixed git commit on main is denied" \
  "CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git commit -m foo"

assert_deny \
  "inline-prefixed git add on main is denied" \
  "CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git add ."

assert_deny \
  "inline-prefixed git push on main (no refspec) is denied" \
  "CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git push"

# ── plain block behavior ────────────────────────────────────────────────────
echo ""
echo "baseline blocks (writes on main are denied):"

assert_deny \
  "plain git commit on main is denied" \
  "git commit -m foo"

assert_deny \
  "plain git push on main (no refspec) is denied" \
  "git push"

assert_deny \
  "plain git add on main is denied" \
  "git add file.txt"

# ── refspec-push allow (already-existing behavior, guarded against regression)
echo ""
echo "explicit-refspec push (the recommended way to move local main onto a remote feature branch):"

assert_allow \
  "git push origin main:fix/foo is allowed" \
  "git push origin main:fix/foo"

assert_allow \
  "git push origin HEAD:feature/bar is allowed" \
  "git push origin HEAD:feature/bar"

# ── human-operator env-var escape hatch ─────────────────────────────────────
# When the variable is exported in the *process environment* (not inline on
# the command), the hook short-circuits at the top. This is the legitimate
# main-branch-dev / dotfiles workflow.
echo ""
echo "process-environment escape hatch (human-operator opt-in must still work):"

assert_allow \
  "git commit allowed when CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 is in the env" \
  "git commit -m foo" \
  "CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1"

assert_allow \
  "git push allowed when CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 is in the env" \
  "git push" \
  "CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1"

# ── git -C <worktree> branch detection (#1389 regression) ──────────────────
# When the orchestrator's cwd is on `main` but the command targets a
# linked worktree via `git -C <path>`, the hook must read the branch from
# the worktree path, not the cwd. Pre-fix, the hook ran
# `git branch --show-current` in its own cwd and denied legitimate writes
# against feature-branch worktrees.
echo ""
echo "git -C <worktree> branch detection (#1389):"

assert_allow \
  "git -C <feature-worktree> commit allowed from a main cwd" \
  "git -C $FEATURE_WT commit -m foo"

assert_allow \
  "git -C <feature-worktree> add allowed from a main cwd" \
  "git -C $FEATURE_WT add file.txt"

assert_allow \
  "git -C <feature-worktree> push allowed from a main cwd" \
  "git -C $FEATURE_WT push -u origin feature/probe"

# Negative: a `-C <worktree>` whose worktree is itself on a protected
# branch (`master` here, since `main` is already checked out in TEST_REPO)
# must still deny. This proves the parser isn't a blanket bypass — it
# correctly resolves the branch from the target dir.
assert_deny \
  "git -C <master-worktree> commit is still denied" \
  "git -C $MASTER_WT commit -m foo"

assert_deny \
  "git -C <master-worktree> push (no refspec) is still denied" \
  "git -C $MASTER_WT push"

# ── read-only operations remain silently allowed ────────────────────────────
echo ""
echo "read-only git operations remain allowed:"

assert_allow \
  "git status on main is allowed" \
  "git status"

assert_allow \
  "git log on main is allowed" \
  "git log --oneline"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
