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
#   - A plain write (no `-C`) from a feature-worktree input `cwd` is allowed,
#     while the same from a master-worktree `cwd` is denied (#1695).
#   - The initial bootstrap push (single root commit) to main is allowed, and
#     resumes denying once a second commit exists.
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-protection.sh"
PASS=0
FAIL=0

# Create a throwaway git repo on `main` so the hook's branch detection has
# something to find. Cleaned up on exit.
TEST_REPO=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
# Sibling worktrees used by the `-C <worktree>` regression tests (#1389):
#   FEATURE_WT — on `feature/probe`, writes should be allowed
#   MASTER_WT  — on `master`, writes should still be denied (negative case)
FEATURE_WT=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
MASTER_WT=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
# INIT_REPO — a pristine repo with a single root commit on main, used to
# assert the bootstrap-push exemption. Kept separate from TEST_REPO so the
# baseline deny tests still run against a repo that has real history.
INIT_REPO=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TEST_REPO" "$FEATURE_WT" "$MASTER_WT" "$INIT_REPO"' EXIT

git -C "$TEST_REPO" init -q -b main
git -C "$TEST_REPO" config user.email "test@example.com"
git -C "$TEST_REPO" config user.name "test"
git -C "$TEST_REPO" config commit.gpgsign false
git -C "$TEST_REPO" config tag.gpgsign false
git -C "$TEST_REPO" commit -q --allow-empty -m "init"
# A second commit so TEST_REPO has real history — the baseline deny tests
# must not be confused with the single-commit bootstrap exemption. Worktrees
# below branch from this two-commit tip.
git -C "$TEST_REPO" commit -q --allow-empty -m "second"

# INIT_REPO has exactly one commit on main — the bootstrap case.
git -C "$INIT_REPO" init -q -b main
git -C "$INIT_REPO" config user.email "test@example.com"
git -C "$INIT_REPO" config user.name "test"
git -C "$INIT_REPO" config commit.gpgsign false
git -C "$INIT_REPO" config tag.gpgsign false
git -C "$INIT_REPO" commit -q --allow-empty -m "init"

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
  # Mirror the hook's real input: `cwd` is the directory the Bash command runs
  # in (here, the TEST_REPO checkout on main). #1695's fix reads this field.
  input=$(jq -nc --arg cmd "$cmd_str" --arg cwd "$TEST_REPO" \
    '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
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

# ── bootstrap push (initial commit initializes the repo) ─────────────────────
# Pushing the very first commit to main is how an empty GitHub repo gets
# initialized. When the branch tip is the repo's only commit there is no PR-able
# history, so a plain `git push` is allowed. Protection resumes once a second
# commit exists (covered by the baseline deny on TEST_REPO, which has history).
echo ""
echo "bootstrap push (single root commit on main is allowed to initialize the repo):"

assert_allow \
  "git -C <single-commit-repo> push to main is allowed" \
  "git -C $INIT_REPO push"

assert_allow \
  "git -C <single-commit-repo> push -u origin main is allowed" \
  "git -C $INIT_REPO push -u origin main"

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

# ── worktree cwd branch detection (#1695 regression) ────────────────────────
# A plain `git add`/`git rm` (NO `-C`) issued from inside a feature-branch
# worktree must read the branch from that worktree, not the hook's own process
# cwd. Pre-fix the hook ran `git branch --show-current` in its process cwd (the
# main checkout) and wrongly denied writes on a correctly-branched worktree.
# Here the hook process cwd is TEST_REPO (on main) while the input `cwd` points
# at the worktree — exactly the shape the hook receives in practice.
echo ""
echo "worktree cwd branch detection (#1695):"

# run_hook_cwd <command-string> <cwd> — like run_hook but with an explicit
# input `cwd` and a hook process cwd pinned to TEST_REPO (main).
run_hook_cwd() {
  local cmd_str="$1" cwd_val="$2"
  local input
  input=$(jq -nc --arg cmd "$cmd_str" --arg cwd "$cwd_val" \
    '{tool_name:"Bash",cwd:$cwd,tool_input:{command:$cmd}}')
  ( cd "$TEST_REPO" && printf '%s' "$input" | bash "$HOOK" )
}

assert_cwd_allow() {
  local desc="$1" cmd_str="$2" cwd_val="$3"
  local out
  out=$(run_hook_cwd "$cmd_str" "$cwd_val")
  if [ -z "$out" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n        expected silent allow, got: %s\n" "$desc" "$out"; FAIL=$((FAIL + 1))
  fi
}

assert_cwd_deny() {
  local desc="$1" cmd_str="$2" cwd_val="$3"
  local out
  out=$(run_hook_cwd "$cmd_str" "$cwd_val")
  if echo "$out" | grep -q '"permissionDecision":"deny"'; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n        expected deny, got: %s\n" "$desc" "${out:-<empty>}"; FAIL=$((FAIL + 1))
  fi
}

assert_cwd_allow \
  "plain git add from a feature-worktree cwd is allowed (no -C)" \
  "git add file.txt" "$FEATURE_WT"

assert_cwd_allow \
  "plain git rm from a feature-worktree cwd is allowed (no -C)" \
  "git rm file.txt" "$FEATURE_WT"

assert_cwd_allow \
  "plain git commit from a feature-worktree cwd is allowed (no -C)" \
  "git commit -m foo" "$FEATURE_WT"

# Negative: when the input cwd is a worktree on a protected branch, a plain
# write must still be denied — proving the cwd path resolves the real branch,
# not a blanket allow.
assert_cwd_deny \
  "plain git add from a master-worktree cwd is still denied (no -C)" \
  "git add file.txt" "$MASTER_WT"

assert_cwd_deny \
  "plain git commit from a master-worktree cwd is still denied (no -C)" \
  "git commit -m foo" "$MASTER_WT"

# ── push to an explicit non-protected ref from a main checkout (#1600) ───────
# Regression: `git push -u origin feat/x` while parked on main was denied
# because only colon refspecs were allowed — but that command pushes feat/x,
# not main. An explicitly-named non-protected target must be allowed; HEAD and
# the protected branch itself must still be denied.
echo ""
echo "explicit non-protected push target from main is allowed (#1600):"

assert_allow \
  "git push -u origin feat/x (explicit feature ref) is allowed from main" \
  "git push -u origin feat/x"

assert_allow \
  "git push origin feat/x (no -u) is allowed from main" \
  "git push origin feat/x"

assert_deny \
  "git push origin main (explicit protected target) is still denied" \
  "git push origin main"

assert_deny \
  "git push origin HEAD (resolves to main on a main checkout) is still denied" \
  "git push origin HEAD"

# ── GitHub wiki checkout exemption (#1586) ───────────────────────────────────
# Wikis render only `master` and support no PRs, so branch protection would
# force every wiki edit into full user delegation. A *.wiki checkout (detected
# by directory name or *.wiki.git remote) is exempt. Built in its own repo
# whose top-level dir ends in `.wiki`.
echo ""
echo "GitHub wiki checkouts are exempt from branch protection (#1586):"

WIKI_PARENT=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
WIKI_REPO="$WIKI_PARENT/myproject.wiki"
mkdir -p "$WIKI_REPO"
git -C "$WIKI_REPO" init -q -b master
git -C "$WIKI_REPO" config user.email "test@example.com"
git -C "$WIKI_REPO" config user.name "test"
git -C "$WIKI_REPO" config commit.gpgsign false
git -C "$WIKI_REPO" commit -q --allow-empty -m init
git -C "$WIKI_REPO" commit -q --allow-empty -m second

assert_wiki_allow() {
  local desc="$1" cmd_str="$2"
  local json out
  json=$(jq -nc --arg cmd "$cmd_str" '{tool_name:"Bash",tool_input:{command:$cmd}}')
  out=$( cd "$WIKI_REPO" && printf '%s' "$json" | bash "$HOOK" )
  if [ -z "$out" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s\n        expected silent allow, got: %s\n" "$desc" "$out"; FAIL=$((FAIL + 1))
  fi
}

assert_wiki_allow \
  "git add in a *.wiki checkout (by dir name) is allowed on master" \
  "git add Home.md"

assert_wiki_allow \
  "git commit in a *.wiki checkout (by dir name) is allowed on master" \
  "git commit -m 'docs: add page'"

# Now add a *.wiki.git remote and confirm the remote-URL detection path too.
git -C "$WIKI_REPO" remote add origin "https://github.com/owner/myproject.wiki.git"

assert_wiki_allow \
  "git add in a checkout with a *.wiki.git remote is allowed" \
  "git add Home.md"

rm -rf "$WIKI_PARENT"

# ── read-only operations remain silently allowed ────────────────────────────
echo ""
echo "read-only git operations remain allowed:"

assert_allow \
  "git status on main is allowed" \
  "git status"

assert_allow \
  "git log on main is allowed" \
  "git log --oneline"

# ── auto mode: the hook defers to auto mode's own classifier ────────────────
echo ""
echo "auto mode defers to the classifier (no double-gating):"

# run_hook_mode <command-string> <permission_mode> — like run_hook but stamps
# the permission_mode field that real clients send.
run_hook_mode() {
  local cmd_str="$1" mode_val="$2"
  local input
  input=$(jq -nc --arg cmd "$cmd_str" --arg cwd "$TEST_REPO" --arg mode "$mode_val" \
    '{tool_name:"Bash",cwd:$cwd,permission_mode:$mode,tool_input:{command:$cmd}}')
  ( cd "$TEST_REPO"; printf '%s' "$input" | bash "$HOOK" )
}

# A bare `git commit` on main is denied in default mode but must be silently
# allowed under permission_mode "auto" — auto mode's classifier owns the call.
out=$(run_hook_mode "git commit -m 'feat: x'" "auto")
if [ -z "$out" ]; then
  printf "  PASS: %s\n" "git commit on main is allowed under permission_mode=auto"
  PASS=$((PASS + 1))
else
  printf "  FAIL: %s\n        expected silent allow, got: %s\n" \
    "git commit on main under auto" "$out"
  FAIL=$((FAIL + 1))
fi

# The same command in default mode (explicit) must still be denied — the gate
# is auto-specific, not a blanket disable.
out=$(run_hook_mode "git commit -m 'feat: x'" "default")
if echo "$out" | grep -q '"permissionDecision":"deny"'; then
  printf "  PASS: %s\n" "git commit on main is still denied under permission_mode=default"
  PASS=$((PASS + 1))
else
  printf "  FAIL: %s\n        expected deny, got: %s\n" \
    "git commit on main under default" "${out:-<empty>}"
  FAIL=$((FAIL + 1))
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
