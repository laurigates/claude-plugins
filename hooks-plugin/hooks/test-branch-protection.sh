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
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-protection.sh"
PASS=0
FAIL=0

# Create a throwaway git repo on `main` so the hook's branch detection has
# something to find. Cleaned up on exit.
TEST_REPO=$(mktemp -d)
trap 'rm -rf "$TEST_REPO"' EXIT

git -C "$TEST_REPO" init -q -b main
git -C "$TEST_REPO" config user.email "test@example.com"
git -C "$TEST_REPO" config user.name "test"
git -C "$TEST_REPO" config commit.gpgsign false
git -C "$TEST_REPO" config tag.gpgsign false
git -C "$TEST_REPO" commit -q --allow-empty -m "init"

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
    for assign in "$@"; do
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
