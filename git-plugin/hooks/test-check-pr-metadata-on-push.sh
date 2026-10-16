#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures are the LITERAL, unexpanded command text a hook receives
# Regression tests for check-pr-metadata-on-push.sh
#
# Run: bash git-plugin/hooks/test-check-pr-metadata-on-push.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Note: Tests that require gh CLI or an actual PR are guarded
# and skipped when gh is unavailable. Core guard-clause tests
# always run since they exit before reaching gh.
set -euo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK="$(dirname "$0")/check-pr-metadata-on-push.sh"
PASS=0
FAIL=0
SKIP=0

# Create a temporary git repo
TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR"' EXIT

git -C "$TMPDIR" init -q
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config user.email "test@test.com"
git -C "$TMPDIR" config user.name "Test"
git -C "$TMPDIR" commit --allow-empty -m "initial" -q
git -C "$TMPDIR" checkout -b main -q 2>/dev/null || true
git -C "$TMPDIR" checkout -b feature -q
git -C "$TMPDIR" commit --allow-empty -m "feat: add feature

Closes #42" -q

# Point origin/HEAD at main so merge-base works
git -C "$TMPDIR" remote add origin "$TMPDIR" 2>/dev/null || true
git -C "$TMPDIR" symbolic-ref refs/remotes/origin/HEAD refs/heads/main

assert_exit() {
    local desc="$1" expected="$2"
    local json="$3"
    local exit_code=0
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"
        FAIL=$((FAIL + 1))
    fi
}

# assert_exit discards the hook's output, so it pins that the push is stopped
# but not the review material the block prints (the PR, its commits, and how to
# get past the check) — the part that makes the block actionable (issue #2715).
# Capture stderr and read it.
assert_stderr_contains() {
    local desc="$1" needle="$2" json="$3"
    local out
    out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
    if grep -qF -- "$needle" <<<"$out"; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (stderr missing: %s)\n" "$desc" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

skip_test() {
    local desc="$1" reason="$2"
    printf "  SKIP: %s (%s)\n" "$desc" "$reason"
    SKIP=$((SKIP + 1))
}

make_json() {
    local cmd="$1"
    local cwd="${2:-$TMPDIR}"
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" \
        '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd}'
}

echo "=== check-pr-metadata-on-push hook tests ==="

# ── Guard clauses: non-push commands pass through ──────────────────────────
echo ""
echo "guard clause (non-push commands pass through):"

assert_exit \
    "non-git command is allowed" 0 \
    "$(make_json "ls -la")"

assert_exit \
    "git status is allowed" 0 \
    "$(make_json "git status")"

assert_exit \
    "git commit is allowed" 0 \
    "$(make_json "git commit -m 'feat: something'")"

assert_exit \
    "git pull is allowed" 0 \
    "$(make_json "git pull origin main")"

assert_exit \
    "git fetch is allowed" 0 \
    "$(make_json "git fetch origin")"

assert_exit \
    "gh pr create is allowed (not a push)" 0 \
    "$(make_json "gh pr create --title 'feat: test'")"

# ── Guard clause: git push detected but no CWD ────────────────────────────
echo ""
echo "guard clause (push without valid cwd):"

assert_exit \
    "git push with empty cwd passes through" 0 \
    '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"cwd":""}'

assert_exit \
    "git push with non-repo cwd passes through" 0 \
    "$(make_json "git push origin main" "/tmp")"

# ── Guard clause: git push patterns are detected ──────────────────────────
# These test that the regex correctly identifies push commands.
# Since there's no real PR, gh pr view will fail and the hook exits 0.
echo ""
echo "push pattern detection (no PR exists, so these allow through):"

assert_exit \
    "simple git push is detected (no PR, allows)" 0 \
    "$(make_json "git push")"

assert_exit \
    "git push origin branch is detected (no PR, allows)" 0 \
    "$(make_json "git push origin feature")"

assert_exit \
    "git push -u origin branch is detected (no PR, allows)" 0 \
    "$(make_json "git push -u origin feature")"

assert_exit \
    "git push with --force flag is detected (no PR, allows)" 0 \
    "$(make_json "git push --force origin feature")"

assert_exit \
    "chained command with git push is detected (no PR, allows)" 0 \
    "$(make_json "git add . && git push origin feature")"

# ── Guard clause: empty/missing input ─────────────────────────────────────
echo ""
echo "guard clause (empty/missing input):"

assert_exit \
    "empty command passes through" 0 \
    '{"tool_name":"Bash","tool_input":{"command":""},"cwd":"/tmp"}'

assert_exit \
    "missing command field passes through" 0 \
    '{"tool_name":"Bash","tool_input":{},"cwd":"/tmp"}'

# ── Retry-aware bypass: PR updated after HEAD commit ──────────────────────
# Regression test for issue #1041: the hook must NOT block when the PR
# metadata was edited after the latest local commit, because the agent
# (or human) has demonstrably already reconciled metadata for HEAD.
echo ""
echo "retry-aware bypass (PR updatedAt vs HEAD commit time):"

# Mock gh CLI: writes canned PR JSON from $MOCK_PR_JSON
MOCK_BIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
# Mock: only handles `gh pr view ...` for these tests.
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    if [ -n "${MOCK_PR_JSON:-}" ]; then
        printf '%s' "$MOCK_PR_JSON"
    fi
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"

# Cross-platform ISO 8601 timestamp helpers (BSD vs GNU date)
iso_offset() {
    local offset_sec="$1"
    if date -u -v"${offset_sec}S" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null; then
        return 0
    fi
    date -u -d "${offset_sec} seconds" "+%Y-%m-%dT%H:%M:%SZ"
}

PR_FUTURE=$(iso_offset "+3600")  # 1h ahead of HEAD commit
PR_PAST=$(iso_offset   "-3600")  # 1h behind HEAD commit

# Make `git push origin feature` resolve to a PR via the mock
PUSH_JSON=$(make_json "git push origin feature")

# Test: PR updated AFTER HEAD commit → hook exits 0 (skip block)
MOCK_PR_JSON=$(jq -n --arg t "$PR_FUTURE" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR updated after HEAD commit allows push (retry-aware)" 0 "$PUSH_JSON"

# Test: PR updated BEFORE HEAD commit → hook still blocks (exit 2)
MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR not updated since HEAD commit still blocks" 2 "$PUSH_JSON"

# Test: missing updatedAt → fall back to legacy block behaviour
MOCK_PR_JSON='{"number":42,"title":"feat: x","body":"body","url":"https://example/42"}'
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "missing updatedAt falls back to blocking" 2 "$PUSH_JSON"

# ── Author-date bypass after rebase (issue #1400) ─────────────────────────
# Regression test: `git rebase` updates committer time to "now" but
# preserves author time. The bypass must use author time so it survives a
# rebase that adds no new content. Without this, a post-rebase push
# requires a content-changing `gh pr edit` to escape the block, which
# `gh pr edit --body-file` no-ops when the body is unchanged (issue #1400).
echo ""
echo "author-date bypass (rebase preserves author date):"

git -C "$TMPDIR" checkout -b rebased -q

# Simulate a rebased commit: author date = when the agent originally wrote
# the work (2h ago); committer date = when the rebase ran (now, default).
PAST_AUTHOR_DATE=$(iso_offset "-7200")
GIT_AUTHOR_DATE="$PAST_AUTHOR_DATE" git -C "$TMPDIR" commit --allow-empty \
    -m "feat: rebased commit" -q

REBASED_PUSH_JSON=$(make_json "git push origin rebased")

# PR was edited 1h ago: AFTER the agent wrote the commit, BEFORE rebase ran.
# With author-date semantics, bypass fires. With committer-date semantics,
# bypass fails (committer time is "now", later than PR.updatedAt).
PR_BETWEEN=$(iso_offset "-3600")
MOCK_PR_JSON=$(jq -n --arg t "$PR_BETWEEN" \
    '{number:42,title:"feat: rebased",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR updated after author-date allows push post-rebase (#1400)" 0 "$REBASED_PUSH_JSON"

# Counter-test: PR genuinely never reviewed (updatedAt before author date)
# still blocks — so the bypass doesn't fire indiscriminately.
PR_BEFORE_AUTHOR=$(iso_offset "-10800")  # 3h ago, before author wrote
MOCK_PR_JSON=$(jq -n --arg t "$PR_BEFORE_AUTHOR" \
    '{number:42,title:"feat: rebased",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "PR not updated since author-date still blocks post-rebase" 2 "$REBASED_PUSH_JSON"

# Return HEAD to feature for any subsequent tests
git -C "$TMPDIR" checkout feature -q

# ── Cross-branch push uses pushed branch's ref (issue #1419) ──────────────
# Regression test: when `git push origin <branch>` is run from a checkout
# whose HEAD is on a different branch (e.g. orchestrator on main pushing
# a feature branch in a worktree), the hook must read commits and the
# bypass author time from the PUSHED branch, not the running shell's HEAD.
#
# Without the fix, the hook reads HEAD (the current branch) — showing
# wrong commits in the block message and reading the wrong author time,
# which traps the agent in a re-block loop when the current branch happens
# to have more recent author time than the pushed branch.
echo ""
echo "cross-branch push reads pushed branch ref (#1419):"

# Build a fresh branch "older-target" with an old author date.
# Then put HEAD on a separate "newer-current" branch with a recent author
# date. From newer-current, push older-target. PR.updatedAt is set
# between the two author dates: AFTER older-target's commit, BEFORE
# newer-current's commit. With HEAD-based logic this fails to bypass
# (uses newer-current's recent author date). With PUSH_REF-based logic
# it bypasses correctly (uses older-target's older author date).
git -C "$TMPDIR" checkout main -q
git -C "$TMPDIR" checkout -b older-target -q
OLDER_AUTHOR_DATE=$(iso_offset "-10800")  # 3h ago
GIT_AUTHOR_DATE="$OLDER_AUTHOR_DATE" git -C "$TMPDIR" commit --allow-empty \
    -m "feat: target branch work" -q

git -C "$TMPDIR" checkout main -q
git -C "$TMPDIR" checkout -b newer-current -q
NEWER_AUTHOR_DATE=$(iso_offset "-60")  # 1m ago
GIT_AUTHOR_DATE="$NEWER_AUTHOR_DATE" git -C "$TMPDIR" commit --allow-empty \
    -m "feat: unrelated current-branch work" -q

# PR last updated 1h ago — between the two author dates.
PR_BETWEEN_BRANCHES=$(iso_offset "-3600")
CROSS_PUSH_JSON=$(make_json "git push origin older-target")

# Bypass MUST fire: pushed branch's author time (3h ago) < PR.updatedAt (1h ago).
MOCK_PR_JSON=$(jq -n --arg t "$PR_BETWEEN_BRANCHES" \
    '{number:42,title:"feat: target",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "cross-branch push uses pushed branch's author date for bypass (#1419)" 0 "$CROSS_PUSH_JSON"

# Counter-test: PR genuinely not updated since pushed branch's commit
# (PR.updatedAt 4h ago, target branch authored 3h ago) → still blocks.
PR_BEFORE_TARGET=$(iso_offset "-14400")  # 4h ago
MOCK_PR_JSON=$(jq -n --arg t "$PR_BEFORE_TARGET" \
    '{number:42,title:"feat: target",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "cross-branch push still blocks when PR is older than pushed branch" 2 "$CROSS_PUSH_JSON"

# First-push case: `git push -u origin brand-new-branch` when the local
# ref doesn't yet exist must fall back to HEAD without erroring.
NEW_PUSH_JSON=$(make_json "git push -u origin brand-new-branch")
MOCK_PR_JSON='{"number":42,"title":"feat: new","body":"body","url":"https://example/42"}'
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "missing local ref falls back to HEAD without error" 2 "$NEW_PUSH_JSON"

git -C "$TMPDIR" checkout feature -q

# ── Branch deletions carry no metadata to reconcile (issue #2351) ─────────
# Regression test: `git push origin --delete <branch>` (and its `-d` and
# colon-refspec equivalents) pushes no commits, so none of the hook's three
# checks (title accuracy, description currency, issue references) have
# anything to act on. The hook must exit 0 before touching gh.
#
# Each case uses a PR whose updatedAt is OLDER than the branch's latest
# commit — i.e. the exact state that blocks a normal push — so a passing
# test proves the deletion detection fired, not the retry-aware bypass.
echo ""
echo "branch deletion pushes exit early (#2351):"

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"OPEN"}')

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "git push origin --delete <branch> is allowed (#2351)" 0 \
    "$(make_json "git push origin --delete feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "git push origin -d <branch> is allowed (#2351)" 0 \
    "$(make_json "git push origin -d feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "git push origin :<branch> is allowed (#2351)" 0 \
    "$(make_json "git push origin :feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "git push origin :refs/heads/<branch> is allowed (#2351)" 0 \
    "$(make_json "git push origin :refs/heads/feature")"

# Counter-tests: the deletion detection must not swallow real commit pushes.
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "normal push still blocks (deletion detection not over-broad)" 2 \
    "$(make_json "git push origin feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "--dry-run push still blocks (not mistaken for -d)" 2 \
    "$(make_json "git push --dry-run origin feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "HEAD:<branch> refspec still blocks (colon is not leading)" 2 \
    "$(make_json "git push origin HEAD:feature")"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "-d in a chained non-push command still blocks" 2 \
    "$(make_json "git push origin feature && rmdir -d /tmp/nope")"

# ── Merged PRs are a historical record (issue #2351) ──────────────────────
# A merged PR's metadata is finished; prompting to edit it invites rewriting
# the description of something already reviewed and landed.
echo ""
echo "merged PR metadata is not reconciled (#2351):"

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"MERGED"}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "push to a branch whose PR is MERGED is allowed (#2351)" 0 \
    "$(make_json "git push origin feature")"

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"OPEN"}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "push to a branch whose PR is OPEN still blocks" 2 \
    "$(make_json "git push origin feature")"

# ── Closed-unmerged PRs are equally finished (issue #2545) ────────────────
# `gh pr view <branch>` returns the most recent PR on the branch regardless
# of state, so a long-closed PR permanently trips the check on a branch that
# is reused for later work. The remedy the block message prescribes — "edit
# the PR title or body" — then forces editing a CLOSED PR's metadata purely
# to bump its updatedAt, which is what the reporter had to do to unblock.
#
# The bypass is deliberately not what saves these: PR_PAST is older than the
# branch's latest commit, i.e. the exact state that blocks a normal push, so
# a passing test proves the state guard fired.
echo ""
echo "closed-unmerged PR metadata is not reconciled (#2545):"

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:364,title:"Release 2.3.0",body:"body",url:"https://example/364",updatedAt:$t,state:"CLOSED"}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "push to a branch whose only PR is CLOSED is allowed (#2545)" 0 \
    "$(make_json "git push origin feature")"

# A branch reused after its PR closed: the colon-refspec deletion form the
# reporter was blocked on must also pass (belt and braces with #2351).
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "deleting a branch whose only PR is CLOSED is allowed (#2545)" 0 \
    "$(make_json "git push origin :refs/heads/feature")"

# Counter-test: an unrecognised state must not silently disable the hook.
# Only MERGED/CLOSED are known-finished; anything else keeps blocking so a
# future gh state enum cannot turn the guard into a blanket allow.
MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"OPEN"}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "OPEN PR still blocks after the CLOSED guard (#2545)" 2 \
    "$(make_json "git push origin feature")"

# Counter-test: a response with no state field at all keeps legacy blocking
# behaviour rather than failing open.
MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t}')
PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_exit "absent state field still blocks (no fail-open) (#2545)" 2 \
    "$(make_json "git push origin feature")"

# ── Block message carries the review material (issue #2715) ───────────────
# The block asks the agent to reconcile PR metadata with the commits being
# pushed, so the message must name the PR, list those commits, and say how to
# get past the check. Uses the same OPEN, not-updated-since-HEAD PR as the
# blocking cases above.
echo ""
echo "block message names the PR, its commits, and the bypass (#2715):"

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"OPEN"}')
MSG_PUSH_JSON=$(make_json "git push origin feature")

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_stderr_contains "block message states why the push stopped" \
    "PR METADATA CHECK: You are pushing to a branch with an existing PR." "$MSG_PUSH_JSON"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_stderr_contains "block message names the PR number and title" \
    "PR #42: feat: x" "$MSG_PUSH_JSON"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_stderr_contains "block message lists the pushed branch's commits" \
    "  - feat: add feature" "$MSG_PUSH_JSON"

PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" \
    assert_stderr_contains "block message says how to get past the check" \
    "To bypass: edit the PR title or body so it reflects the new commit, THEN push." \
    "$MSG_PUSH_JSON"

# ── Parsed trigger: a mention is not a push (issue #2737) ──────────────────
# The trigger used to be `(^|\s|&&\s*|;\s*)git\s+push\b` over the raw command,
# so a quoted argument, a heredoc body or a commit message that merely MENTIONS
# a push fired the full block. It is now decided on parsed command nodes.
#
# Every row uses the OPEN, not-updated-since-HEAD PR that blocks a real push,
# so "allowed" proves the trigger stayed quiet rather than a later guard.
#
# Then a GENERATED spelling probe (bases x wrappers, two bases x shell
# contexts) must all fire, and a DIFFERENTIAL runs the same set through the
# pre-fix hook (`git show <PREFIX_SHA>:…`): a spelling the old hook blocked
# that the new one allows fails the suite. Hand-picked spellings alone are how
# a narrowed trigger silently loses a real invocation.
echo ""
echo "parsed trigger: quoted/heredoc mentions of git push do not fire (#2737):"

PREFIX_SHA=716345bf213793134a30bec2ff68761946aee38d
HOOK_REL=git-plugin/hooks/check-pr-metadata-on-push.sh

have_parser() {
    [ "${CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP:-}" = 1 ] && return 1
    command -v ast-grep >/dev/null 2>&1 && return 0
    command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'
}

MOCK_PR_JSON=$(jq -n --arg t "$PR_PAST" \
    '{number:42,title:"feat: x",body:"body",url:"https://example/42",updatedAt:$t,state:"OPEN"}')
export MOCK_PR_JSON

# $1 = hook path, $2 = command. Prints "fire" (exit 2) or "quiet" (exit 0),
# or "exit<N>" for anything else.
verdict() {
    local rc=0
    make_json "$2" | PATH="$MOCK_BIN:$PATH" bash "$1" >/dev/null 2>&1 || rc=$?
    case $rc in
        2) echo fire ;;
        0) echo quiet ;;
        *) echo "exit$rc" ;;
    esac
}

expect() { # $1 = fire|quiet, $2 = description, $3 = command
    local got
    got=$(verdict "$HOOK" "$3")
    if [ "$got" = "$1" ]; then
        printf "  PASS: %s\n" "$2"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$2" "$1" "$got"
        FAIL=$((FAIL + 1))
    fi
}

if ! have_parser; then
    skip_test "parsed-trigger rows, spelling probe and differential" "ast-grep not installed"
else
    expect quiet "gh issue comment --body mentioning git push" \
        'gh issue comment 1 --body "run git push later"'
    expect quiet "commit message mentioning git push" \
        'git commit -m "docs: explain when to git push origin feature"'
    expect quiet "commit heredoc body mentioning git push" \
        "$(printf '%s\n' "git commit -F - <<'EOF'" 'then git push origin feature' 'EOF')"
    expect quiet "heredoc inside \$(…) inside a quoted --body" \
        "$(printf '%s\n' "gh pr comment 1 --body \"\$(cat <<'EOF'" '; git push origin feature' 'EOF' ')"')"
    expect quiet "trailing comment mentioning git push" \
        'git status # then git push origin feature'
    expect quiet "single-quoted echo of git push" \
        "echo 'cd repo && git push origin feature'"
    expect fire "real push after a quoted mention still fires" \
        'git commit -m "prep for git push" && git push origin feature'
    expect fire "cd x && git push fires" "cd $TMPDIR && git push origin feature"
    expect fire "git -C <dir> push fires" "git -C $TMPDIR push origin feature"
    expect fire "bash -c with a quoted push script fires" "bash -c 'git push origin feature'"
    expect fire "push inside \$(…) fires" 'out=$(git push origin feature 2>&1)'
    expect fire "FOO=1 git push fires" "GIT_TRACE=0 git push origin feature"

    # With the parser forced off, the old raw-text match decides (nudge polarity:
    # keep the regex rather than go silent), false positive included.
    got=$(make_json 'gh issue comment 1 --body "x; git push later"' \
        | PATH="$MOCK_BIN:$PATH" CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP=1 bash "$HOOK" >/dev/null 2>&1 && echo quiet || echo fire)
    if [ "$got" = fire ]; then
        printf "  PASS: %s\n" "no parser: raw-text regex still decides"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (got %s)\n" "no parser: raw-text regex still decides" "$got"
        FAIL=$((FAIL + 1))
    fi

    echo ""
    echo "generated spelling probe + differential vs pre-fix hook (#2737):"
    BASES=("git push" "git push origin feature" "git push -u origin feature"
        "git push --force-with-lease origin feature" "git --no-pager push origin feature"
        "git -c core.askPass=true push origin feature" "/usr/bin/git push origin feature"
        "git -C $TMPDIR push origin feature")
    WRAPPERS=("" "env X=1 " "X=1 " "timeout 5 " "sudo " "command " "nice -n 5 " "nohup " "exec " "time ")
    CONTEXTS=('X' 'cd . && X' 'true; X' 'X; true' 'true && X' 'false || X' 'X || true'
        'X 2>&1 | tail -1' 'for d in 1; do X; done' 'if true; then X; fi' '( X )' '{ X; }'
        $'echo start\nX' 'out=$(X)' 'echo "$(X)"' "bash -c 'X'" "sh -c 'cd . && X'" 'X &'
        'git add a.txt && git commit -m "wip: x" && X' 'gh issue comment 1 --body "pushing now" && X')
    SPELLINGS=()
    for b in "${BASES[@]}"; do
        for w in "${WRAPPERS[@]}"; do SPELLINGS+=("$w$b"); done
    done
    for b in "git push origin feature" "git -C $TMPDIR push"; do
        for c in "${CONTEXTS[@]}"; do SPELLINGS+=("${c%%X*}$b${c#*X}"); done
    done

    BASELINE=""
    if git -C "$(dirname "$0")" cat-file -e "$PREFIX_SHA:$HOOK_REL" 2>/dev/null; then
        BASELINE="$TMPDIR/baseline-hook.sh"
        git -C "$(dirname "$0")" show "$PREFIX_SHA:$HOOK_REL" >"$BASELINE"
    fi
    missed=0
    lost=0
    base_hits=0
    for s in "${SPELLINGS[@]}"; do
        new=$(verdict "$HOOK" "$s")
        if [ "$new" != fire ]; then
            missed=$((missed + 1))
            printf "  FAIL: spelling probe must fire (got %s): %s\n" "$new" "$s"
        fi
        if [ -n "$BASELINE" ] && [ "$(verdict "$BASELINE" "$s")" = fire ]; then
            base_hits=$((base_hits + 1))
            if [ "$new" != fire ]; then lost=$((lost + 1)); fi
        fi
    done
    if [ "$missed" -eq 0 ]; then
        printf "  PASS: all %d generated spellings fire\n" "${#SPELLINGS[@]}"
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    if [ -z "$BASELINE" ]; then
        skip_test "differential vs pre-fix hook" "commit $PREFIX_SHA not in this clone"
    elif [ "$base_hits" -lt 40 ]; then
        printf "  FAIL: differential is vacuous (baseline fired on only %d)\n" "$base_hits"
        FAIL=$((FAIL + 1))
    elif [ "$lost" -eq 0 ]; then
        printf "  PASS: differential: baseline fires on %d of %d, none lost\n" "$base_hits" "${#SPELLINGS[@]}"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: differential: %d spelling(s) the pre-fix hook blocked are allowed\n" "$lost"
        FAIL=$((FAIL + 1))
    fi
fi

rm -rf "$MOCK_BIN"

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
