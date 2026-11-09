#!/usr/bin/env bash
# shellcheck disable=SC2016  # the printed exclude command is LITERAL text, run later via bash -c
# Regression tests for git-drift-probe.sh
#
# Run: bash git-plugin/hooks/test-git-drift-probe.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The probe writes a per-plugin signal file (drift-protocol.sh) under
# $CLAUDE_DRIFT_SIGNALS_DIR/<session-id>/git-plugin.json and prints nothing.
# Tests read that file. gh is mocked.
#
# Focus: the worktrees_not_ignored signal (issue #3436). Claude Code puts its
# worktrees under <repo>/.claude/worktrees/ by default; when that path is not
# git-ignored, each worktree shows up as an untracked directory in the main
# checkout. The probe nudges (it never writes the ignore entry itself), on any
# branch including the default one, without needing gh. The existing PR-branch
# signals keep their behaviour: silent on the default branch, need gh.
set -uo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

PROBE="$(cd "$(dirname "$0")" && pwd)/git-drift-probe.sh"
PASS=0
FAIL=0

SANDBOX=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then echo "empty sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$SANDBOX"' EXIT

SIGNALS="$SANDBOX/signals"
MOCK_BIN="$SANDBOX/mock-bin"
NOGH_BIN="$SANDBOX/nogh-bin"
ERR_BIN="$SANDBOX/err-bin"
mkdir -p "$SIGNALS" "$MOCK_BIN" "$NOGH_BIN" "$ERR_BIN"

# Mock gh: `gh pr view ...` prints $MOCK_PR_JSON (empty = no PR).
cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    [ -n "${MOCK_PR_JSON:-}" ] && printf '%s' "$MOCK_PR_JSON"
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"
[ -x "$MOCK_BIN/gh" ] || { echo "mock gh not executable" >&2; exit 1; }

# A PATH with every tool the probe uses except gh, so the "gh missing" case is
# real and not shadowed by an installed gh.
for tool in git jq date mkdir mv rm tr cat sort tail dirname sed awk grep head; do
    p=$(command -v "$tool") || { echo "missing tool for test PATH: $tool" >&2; exit 1; }
    ln -s "$p" "$NOGH_BIN/$tool"
done
if PATH="$NOGH_BIN" command -v gh >/dev/null 2>&1; then
    echo "nogh PATH still resolves gh" >&2; exit 1
fi

# A git wrapper whose check-ignore exits 128 (an error, not "not ignored").
REAL_GIT=$(command -v git)
cat >"$ERR_BIN/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
    if [ "\$a" = check-ignore ]; then echo "fatal: simulated" >&2; exit 128; fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$ERR_BIN/git"
[ -x "$ERR_BIN/git" ] || { echo "error git wrapper not executable" >&2; exit 1; }

new_repo() { # new_repo <dir> — a one-commit repo on main
    local d="$1"
    mkdir -p "$d"
    git -C "$d" init -q
    git -C "$d" config commit.gpgsign false
    git -C "$d" config user.email "test@test.com"
    git -C "$d" config user.name "Test"
    git -C "$d" commit --allow-empty -m "initial" -q
    git -C "$d" branch -m main 2>/dev/null || true
}

# run_probe <cwd> [env assignments...] — runs the probe, prints the signal JSON.
# Called inside $(…), so no counter survives between calls: the signal dir is
# emptied first, so a probe that fails to start reads MISSING, never the
# previous case's file. The probe runs under "$BASH" (an absolute path) so a
# PATH override that has no bash on it still starts it.
run_probe() {
    local cwd="$1"; shift
    local sid="sid"
    rm -rf "${SIGNALS:?}/$sid"
    jq -nc --arg s "$sid" --arg c "$cwd" '{session_id:$s, cwd:$c}' |
        env CLAUDE_DRIFT_SIGNALS_DIR="$SIGNALS" PATH="$MOCK_BIN:$PATH" "$@" "$BASH" "$PROBE" >/dev/null 2>&1
    cat "$SIGNALS/$sid/git-plugin.json" 2>/dev/null || echo "MISSING"
}

kinds() { printf '%s' "$1" | jq -r '[.findings[].kind] | join(",")' 2>/dev/null; }

expect_kind() { # expect_kind <desc> <json> <kind>
    if printf '%s' "$2" | jq -e --arg k "$3" 'any(.findings[]; .kind == $k)' >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (kinds: [%s])\n" "$1" "$(kinds "$2")"; FAIL=$((FAIL + 1))
    fi
}

expect_no_kind() { # expect_no_kind <desc> <json> <kind> — also requires the file was written
    if [ "$2" = "MISSING" ]; then
        printf "  FAIL: %s (no signal file written)\n" "$1"; FAIL=$((FAIL + 1))
    elif printf '%s' "$2" | jq -e --arg k "$3" 'any(.findings[]; .kind == $k) | not' >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (kinds: [%s])\n" "$1" "$(kinds "$2")"; FAIL=$((FAIL + 1))
    fi
}

summary_of() { printf '%s' "$1" | jq -r --arg k "$2" '.findings[] | select(.kind == $k) | .summary' 2>/dev/null; }

# ── Not ignored, default branch ───────────────────────────────────────────────
echo "not ignored:"
R1="$SANDBOX/plain"
new_repo "$R1"
out=$(run_probe "$R1")
expect_kind "default branch, no ignore entry -> worktrees_not_ignored" "$out" worktrees_not_ignored
s=$(summary_of "$out" worktrees_not_ignored)
case "$s" in *"$R1"*) printf "  PASS: summary names the repo root\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: summary does not name %s: %s\n" "$R1" "$s"; FAIL=$((FAIL + 1)) ;; esac
case "$s" in *'/configure:gitignore'*) printf "  PASS: summary names /configure:gitignore\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: summary lacks /configure:gitignore: %s\n" "$s"; FAIL=$((FAIL + 1)) ;; esac
case "$s" in *'git rev-parse --git-path info/exclude'*) printf "  PASS: summary gives the git-path info/exclude one-liner\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: summary lacks the info/exclude one-liner: %s\n" "$s"; FAIL=$((FAIL + 1)) ;; esac
skill=$(printf '%s' "$out" | jq -r '.findings[] | select(.kind == "worktrees_not_ignored") | .remediation_skill' 2>/dev/null)
if [ "$skill" = "/configure:gitignore" ]; then
    printf "  PASS: remediation_skill is /configure:gitignore\n"; PASS=$((PASS + 1))
else
    printf "  FAIL: remediation_skill is '%s'\n" "$skill"; FAIL=$((FAIL + 1))
fi
sev=$(printf '%s' "$out" | jq -r '.findings[] | select(.kind == "worktrees_not_ignored") | .severity' 2>/dev/null)
if [ "$sev" = "warn" ]; then
    printf "  PASS: severity is warn\n"; PASS=$((PASS + 1))
else
    printf "  FAIL: severity is '%s'\n" "$sev"; FAIL=$((FAIL + 1))
fi

out=$(run_probe "$R1" PATH="$NOGH_BIN")
expect_kind "gh not installed -> still reported (needs only git)" "$out" worktrees_not_ignored

mkdir -p "$R1/sub/dir"
out=$(run_probe "$R1/sub/dir")
expect_kind "cwd in a subdirectory -> reported" "$out" worktrees_not_ignored

# ── Ignored by .gitignore / info/exclude ──────────────────────────────────────
echo ""
echo "ignored:"
R2="$SANDBOX/gitignored"
new_repo "$R2"
printf '.claude/worktrees/\n' >"$R2/.gitignore"
git -C "$R2" add .gitignore && git -C "$R2" commit -q -m "chore: ignore worktrees"
out=$(run_probe "$R2")
expect_no_kind ".gitignore'd -> silent" "$out" worktrees_not_ignored

R3="$SANDBOX/excluded"
new_repo "$R3"
mkdir -p "$R3/.git/info"
printf '.claude/worktrees/\n' >>"$R3/.git/info/exclude"
out=$(run_probe "$R3")
expect_no_kind "info/exclude'd -> silent" "$out" worktrees_not_ignored

R3b="$SANDBOX/broad"
new_repo "$R3b"
printf '.claude/\n' >"$R3b/.gitignore"
out=$(run_probe "$R3b")
expect_no_kind "a broader .claude/ ignore -> silent" "$out" worktrees_not_ignored

# ── Linked worktree cwd ───────────────────────────────────────────────────────
echo ""
echo "linked worktree:"
R4="$SANDBOX/linked-main"
new_repo "$R4"
git -C "$R4" worktree add -q "$R4/.claude/worktrees/wt1" -b wt1 2>/dev/null
out=$(run_probe "$R4/.claude/worktrees/wt1")
expect_kind "cwd in a linked worktree of an un-ignored main -> reported" "$out" worktrees_not_ignored
s=$(summary_of "$out" worktrees_not_ignored)
case "$s" in *"in $R4,"*|*"in $R4 "*) printf "  PASS: summary names the MAIN checkout, not the linked one\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: summary does not name main checkout %s: %s\n" "$R4" "$s"; FAIL=$((FAIL + 1)) ;; esac

# The printed one-liner, run from the linked worktree, must land in the SHARED
# exclude file (git-path resolves the common dir) and silence the signal.
cmd=$(printf '%s' "$s" | sed -n "s/.*exclude it locally: \(echo .*\)\$/\1/p")
if [ -z "$cmd" ]; then
    printf "  FAIL: could not extract the exclude one-liner from: %s\n" "$s"; FAIL=$((FAIL + 1))
else
    (cd "$R4/.claude/worktrees/wt1" && bash -c "$cmd") >/dev/null 2>&1
    if grep -qxF '.claude/worktrees/' "$R4/.git/info/exclude" 2>/dev/null; then
        printf "  PASS: printed one-liner writes the shared .git/info/exclude\n"; PASS=$((PASS + 1))
    else
        printf "  FAIL: printed one-liner did not write %s\n" "$R4/.git/info/exclude"; FAIL=$((FAIL + 1))
    fi
    out=$(run_probe "$R4/.claude/worktrees/wt1")
    expect_no_kind "after the printed one-liner -> silent in the linked worktree" "$out" worktrees_not_ignored
    out=$(run_probe "$R4")
    expect_no_kind "after the printed one-liner -> silent in the main checkout" "$out" worktrees_not_ignored
fi

# ── Not applicable / errors ───────────────────────────────────────────────────
echo ""
echo "silent cases:"
NOGIT="$SANDBOX/not-a-repo"
mkdir -p "$NOGIT"
out=$(run_probe "$NOGIT")
expect_no_kind "non-git directory -> signal written, no finding" "$out" worktrees_not_ignored
if [ "$out" != "MISSING" ] && [ "$(printf '%s' "$out" | jq '.findings | length')" = "0" ]; then
    printf "  PASS: non-git directory -> empty findings\n"; PASS=$((PASS + 1))
else
    printf "  FAIL: non-git directory -> %s\n" "$out"; FAIL=$((FAIL + 1))
fi

BARE="$SANDBOX/bare.git"
git init -q --bare "$BARE"
out=$(run_probe "$BARE")
expect_no_kind "bare repository -> silent" "$out" worktrees_not_ignored
# A linked worktree of a bare repository: the main entry has no checkout. (The
# probe's explicit bare skip and check-ignore's own exit 128 in a bare repo both
# keep this silent, so this case does not tell the two apart.)
git -C "$R1" push -q "$BARE" main 2>/dev/null
git -C "$BARE" worktree add -q "$SANDBOX/bare-linked" main 2>/dev/null
out=$(run_probe "$SANDBOX/bare-linked")
expect_no_kind "linked worktree of a bare repository -> silent" "$out" worktrees_not_ignored

out=$(run_probe "$R1" PATH="$ERR_BIN:$MOCK_BIN:$PATH")
expect_no_kind "check-ignore error (exit 128) -> silent" "$out" worktrees_not_ignored

out=$(run_probe "$R1" CLAUDE_HOOKS_DISABLE_WORKTREES_IGNORE_NUDGE=1)
expect_no_kind "CLAUDE_HOOKS_DISABLE_WORKTREES_IGNORE_NUDGE=1 -> silent" "$out" worktrees_not_ignored

# ── Existing PR-branch signals unchanged ──────────────────────────────────────
echo ""
echo "existing signals:"
MERGED=$(jq -nc '{number:7,state:"MERGED",reviewDecision:""}')
out=$(run_probe "$R1" MOCK_PR_JSON="$MERGED")
expect_no_kind "default branch + merged PR -> no pr_merged (PR signals skip the default branch)" "$out" pr_merged

git -C "$R1" switch -q -c feature
out=$(run_probe "$R1" MOCK_PR_JSON="$MERGED")
expect_kind "feature branch + merged PR -> pr_merged" "$out" pr_merged
expect_kind "feature branch + merged PR -> worktrees_not_ignored alongside" "$out" worktrees_not_ignored

CHANGES=$(jq -nc '{number:8,state:"OPEN",reviewDecision:"CHANGES_REQUESTED"}')
out=$(run_probe "$R1" MOCK_PR_JSON="$CHANGES" CLAUDE_HOOKS_DISABLE_WORKTREES_IGNORE_NUDGE=1)
expect_kind "opt-out leaves changes_requested intact" "$out" changes_requested
expect_no_kind "opt-out drops only worktrees_not_ignored" "$out" worktrees_not_ignored

# ── branch_behind vs squash-merged commits (issue #3527) ──────────────────────
# After a squash merge the remote branch is deleted, but origin/<branch> keeps
# pointing at the pre-squash commit until `git fetch --prune`. Restarting the
# branch from main then leaves that commit unreachable from HEAD, though its
# patch is on main. git cherry marks it `-`; only `+` commits are behind.
echo ""
echo "branch_behind (squash-merged, #3527):"
NOWT="CLAUDE_HOOKS_DISABLE_WORKTREES_IGNORE_NUDGE=1"

# new_remote_pair <name> — bare remote + clone on main with origin/HEAD set.
new_remote_pair() {
    local remote="$SANDBOX/$1-remote.git" clone="$SANDBOX/$1-clone"
    git init -q --bare "$remote"
    git -C "$remote" symbolic-ref HEAD refs/heads/main
    new_repo "$clone"
    git -C "$clone" remote add origin "$remote"
    git -C "$clone" push -q -u origin main 2>/dev/null
    git -C "$clone" remote set-head origin main >/dev/null 2>&1
    printf '%s\n' "$clone"
}

# commit_file <repo> <file> <content> — one commit adding/changing one file.
commit_file() {
    printf '%s\n' "$3" >"$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -q -m "change $2"
}

# squash_onto_main <repo> <branch> — squash-merge <branch> into main, push.
squash_onto_main() {
    git -C "$1" switch -q main
    git -C "$1" merge -q --squash "$2" >/dev/null 2>&1
    git -C "$1" commit -q -m "squash $2"
    git -C "$1" push -q origin main 2>/dev/null
}

# squashed_fixture <name> <ncommits> — feat with <ncommits> commits, squash-
# merged into main, remote branch deleted, origin/feat left unpruned, feat
# restarted from origin/main. Prints the clone path.
squashed_fixture() {
    local c i
    c=$(new_remote_pair "$1")
    git -C "$c" switch -q -c feat
    for i in $(seq 1 "$2"); do commit_file "$c" "$1-$i.txt" "$i"; done
    git -C "$c" push -q -u origin feat 2>/dev/null
    squash_onto_main "$c" feat
    # Delete on the remote side (as GitHub does after merge): `push --delete`
    # from this clone would also drop the local origin/feat, hiding the bug.
    git -C "$SANDBOX/$1-remote.git" branch -q -D feat
    git -C "$c" -c fetch.prune=false fetch -q origin   # plain fetch leaves origin/feat
    git -C "$c" rev-parse --verify -q refs/remotes/origin/feat >/dev/null ||
        { echo "fixture: origin/feat was pruned" >&2; exit 1; }
    git -C "$c" switch -q -C feat origin/main
    printf '%s\n' "$c"
}

expect_prune_hint() { # expect_prune_hint <label> <json>
    expect_no_kind "$1 -> no branch_behind" "$2" branch_behind
    expect_kind "$1 -> stale_remote_ref hint" "$2" stale_remote_ref
    local s sev
    s=$(summary_of "$2" stale_remote_ref)
    case "$s" in *'git fetch --prune'*) printf "  PASS: %s hint suggests git fetch --prune\n" "$1"; PASS=$((PASS + 1)) ;;
        *) printf "  FAIL: %s hint lacks git fetch --prune: %s\n" "$1" "$s"; FAIL=$((FAIL + 1)) ;; esac
    sev=$(printf '%s' "$2" | jq -r '.findings[] | select(.kind == "stale_remote_ref") | .severity' 2>/dev/null)
    if [ "$sev" = "info" ]; then
        printf "  PASS: %s hint severity is info\n" "$1"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s hint severity is '%s'\n" "$1" "$sev"; FAIL=$((FAIL + 1))
    fi
}

# 1. The issue's repro: a one-commit branch squash-merged (cherry marks it -).
S1=$(squashed_fixture squashed1 1)
out=$(run_probe "$S1" "$NOWT")
expect_prune_hint "one-commit squash" "$out"

# 1b. A multi-commit branch squashed into one commit: no single commit is
#     patch-equivalent (cherry marks each +), but merging origin/feat into
#     main changes nothing, so it is all on main.
S1B=$(squashed_fixture squashed3 3)
out=$(run_probe "$S1B" "$NOWT")
expect_prune_hint "three-commit squash" "$out"

# 2. Genuinely behind: the remote has 2 commits not on main.
S2=$(new_remote_pair behind)
git -C "$S2" switch -q -c feat
git -C "$S2" push -q -u origin feat 2>/dev/null
commit_file "$S2" c.txt three
commit_file "$S2" d.txt four
git -C "$S2" push -q origin feat 2>/dev/null
git -C "$S2" reset -q --hard HEAD~2
out=$(run_probe "$S2" "$NOWT")
expect_kind "remote has commits not on main -> branch_behind" "$out" branch_behind
expect_no_kind "remote has commits not on main -> no stale_remote_ref" "$out" stale_remote_ref
s=$(summary_of "$out" branch_behind)
case "$s" in *"is 2 commit(s) behind"*) printf "  PASS: behind count is 2\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: expected 2 commit(s) behind: %s\n" "$s"; FAIL=$((FAIL + 1)) ;; esac

# 3. Mixed: 2 commits cherry-picked/squashed to main one by one (each -), then
#    1 more pushed that is not (+).
S3=$(new_remote_pair mixed)
git -C "$S3" switch -q -c feat
commit_file "$S3" e.txt five
git -C "$S3" push -q -u origin feat 2>/dev/null
squash_onto_main "$S3" feat
git -C "$S3" switch -q feat
commit_file "$S3" f.txt six
git -C "$S3" push -q origin feat 2>/dev/null
git -C "$S3" switch -q main
git -C "$S3" cherry-pick feat >/dev/null 2>&1 ||
    { echo "fixture: cherry-pick failed" >&2; exit 1; }
git -C "$S3" push -q origin main 2>/dev/null
git -C "$S3" switch -q feat
commit_file "$S3" g.txt seven
git -C "$S3" push -q origin feat 2>/dev/null
git -C "$S3" switch -q -C feat origin/main
out=$(run_probe "$S3" "$NOWT")
expect_kind "mixed -> branch_behind" "$out" branch_behind
s=$(summary_of "$out" branch_behind)
case "$s" in *"is 1 commit(s) behind"*) printf "  PASS: mixed counts only the + commit (1)\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: expected 1 commit(s) behind: %s\n" "$s"; FAIL=$((FAIL + 1)) ;; esac

# 4. Default branch unresolvable (no origin/HEAD, no origin/main|master):
#    fall back to the plain count, so the squash-merged case still warns.
git -C "$S1B" remote set-head origin -d >/dev/null 2>&1
git -C "$S1B" update-ref -d refs/remotes/origin/main
out=$(run_probe "$S1B" "$NOWT")
expect_kind "no resolvable default branch -> plain-count branch_behind" "$out" branch_behind
s=$(summary_of "$out" branch_behind)
case "$s" in *"is 3 commit(s) behind"*) printf "  PASS: fallback reports plain count (3)\n"; PASS=$((PASS + 1)) ;;
    *) printf "  FAIL: expected plain count 3: %s\n" "$s"; FAIL=$((FAIL + 1)) ;; esac

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
