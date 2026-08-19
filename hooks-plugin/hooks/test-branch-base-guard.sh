#!/usr/bin/env bash
# Regression tests for branch-base-guard.sh
#
# Run: bash hooks-plugin/hooks/test-branch-base-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook always exits 0 and signals a nudge by emitting a PreToolUse
# permissionDecision:"ask" JSON envelope on stdout, so assertions read that
# stdout rather than exit codes.
#
# Covers:
#   - EXEMPTION 1 (the most important test in the file): the hook's OWN
#     suggested fix `git switch -c feat/x origin/main` must NOT re-trigger it,
#     or the nudge becomes an infinite ask loop.
#   - Value-taking-flag parsing: `--track` / `-t <upstream>` leave the
#     start-point positional and therefore visible.
#   - Default-branch RESOLUTION: a `master`-default fixture must still nudge
#     (a hardcoded `main` fails here).
#   - EXEMPTION 2: HEAD must be the resolved default branch.
#   - Trigger surface: switch -c/-C, checkout -b/-B, worktree add -b.
#   - Quote scrubbing, remote-exec suppression, `git -C` repo resolution
#     (#1389), non-repo cwd, opt-out env var, TTL dedup.
#
# Every make_json call mints a FRESH session_id — the TTL cache would otherwise
# turn the second assertion in each group into a silent "none".
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/branch-base-guard.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Keep the hook's TTL cache inside the fixture tree so a run never touches the
# developer's real /tmp cache (and so each run starts cold).
export TMPDIR="$WORK/tmpcache"
mkdir -p "$TMPDIR"

# ── Fixtures ─────────────────────────────────────────────────────────────────
# setup_repo <dir> <default-branch> <unpushed-commits>
setup_repo() {
    local dir="$1" br="$2" extra="$3" i
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config commit.gpgsign false
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"
    git -C "$dir" commit --allow-empty -m "initial" -q
    git -C "$dir" branch -m "$br" 2>/dev/null || git -C "$dir" checkout -b "$br" -q
    git init -q --bare "$dir.git"
    git -C "$dir" remote add origin "$dir.git"
    git -C "$dir" push -q origin "$br"
    git -C "$dir" fetch -q origin
    i=1
    while [ "$i" -le "$extra" ]; do
        git -C "$dir" commit --allow-empty -m "feat: unpushed $i" -q
        i=$((i + 1))
    done
}

AHEAD="$WORK/ahead"          # default main, 2 unpushed commits on main
CLEAN="$WORK/clean"          # default main, 0 unpushed commits
MASTERD="$WORK/masterd"      # default master, 2 unpushed commits on master
FEATURE="$WORK/feature"      # ahead main, but HEAD parked on feat/y
DETACH="$WORK/detach"        # ahead main, detached HEAD
NOREMOTE="$WORK/noremote"    # no origin at all

setup_repo "$AHEAD" main 2
setup_repo "$CLEAN" main 0
setup_repo "$MASTERD" master 2
setup_repo "$FEATURE" main 2
git -C "$FEATURE" checkout -b feat/y -q
setup_repo "$DETACH" main 2
git -C "$DETACH" checkout --detach -q

mkdir -p "$NOREMOTE"
git -C "$NOREMOTE" init -q
git -C "$NOREMOTE" config commit.gpgsign false
git -C "$NOREMOTE" config user.email "test@test.com"
git -C "$NOREMOTE" config user.name "Test"
git -C "$NOREMOTE" commit --allow-empty -m "initial" -q
git -C "$NOREMOTE" branch -m main 2>/dev/null || git -C "$NOREMOTE" checkout -b main -q

# ── Helpers ──────────────────────────────────────────────────────────────────
make_json_sid() {   # $1 command, $2 cwd, $3 session_id
    jq -nc --arg cmd "$1" --arg cwd "$2" --arg sid "$3" \
        '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,session_id:$sid}'
}

make_json() {       # $1 command, $2 cwd (default: the ahead fixture)
    make_json_sid "$1" "${2:-$AHEAD}" "test-$RANDOM-$RANDOM-$RANDOM"
}

decision_of() {     # $1 hook stdout
    if [ -z "$1" ]; then
        printf 'none'
    else
        printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null \
            || printf 'parse_error'
    fi
}

assert_decision() { # $1 desc, $2 expected, $3 json
    local desc="$1" want="$2" json="$3" out got
    out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
    got=$(decision_of "$out")
    if [ "$got" = "$want" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}

assert_decision_env() { # $1 desc, $2 expected, $3 json, $4 VAR=value
    local desc="$1" want="$2" json="$3" envassign="$4" out got
    out=$(printf '%s' "$json" | env "$envassign" bash "$HOOK" 2>/dev/null)
    got=$(decision_of "$out")
    if [ "$got" = "$want" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}

assert_reason_contains() { # $1 desc, $2 needle, $3 json
    local desc="$1" needle="$2" json="$3" out reason
    out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
    reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
    case "$reason" in
        *"$needle"*) printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1)) ;;
        *) printf "  FAIL: %s (reason lacks '%s')\n" "$desc" "$needle"; FAIL=$((FAIL + 1)) ;;
    esac
}

assert_exit() {     # $1 desc, $2 expected exit, $3 json
    local desc="$1" want="$2" json="$3" got=0
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || got=$?
    if [ "$got" -eq "$want" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}

echo "=== branch-base-guard hook tests ==="

# ── THE decisive test: the suggested fix must never re-trigger the nudge ─────
echo ""
echo "EXEMPTION 1 — explicit start-point (the hook's own suggested fix):"
assert_decision "git switch -c feat/x origin/main (the suggested fix) → silent" \
    none "$(make_json "git switch -c feat/x origin/main")"
assert_decision "git fetch origin && git switch -c feat/x origin/main → silent" \
    none "$(make_json "git fetch origin && git switch -c feat/x origin/main")"
assert_decision "git checkout -b feat/x origin/main → silent" \
    none "$(make_json "git checkout -b feat/x origin/main")"
assert_decision "git switch -c feat/x abc1234 (sha start-point) → silent" \
    none "$(make_json "git switch -c feat/x abc1234")"
assert_decision "git switch -c feat/x main (branch start-point) → silent" \
    none "$(make_json "git switch -c feat/x main")"
assert_decision "git switch -C feat/x origin/main (force-create + start-point) → silent" \
    none "$(make_json "git switch -C feat/x origin/main")"
assert_decision "git switch --create feat/x origin/main (long form) → silent" \
    none "$(make_json "git switch --create feat/x origin/main")"
assert_decision "git worktree add -b feat/x ../wt origin/main → silent" \
    none "$(make_json "git worktree add -b feat/x ../wt origin/main")"

echo ""
echo "value-taking-flag parsing (start-point still seen):"
assert_decision "git switch -c feat/x --track origin/main → silent" \
    none "$(make_json "git switch -c feat/x --track origin/main")"
assert_decision "git switch -c feat/x -t origin/main → silent" \
    none "$(make_json "git switch -c feat/x -t origin/main")"
assert_decision "git checkout -b feat/x --no-track origin/main → silent" \
    none "$(make_json "git checkout -b feat/x --no-track origin/main")"

# ── The nudge fires ──────────────────────────────────────────────────────────
echo ""
echo "nudge fires on ahead-main (no start-point):"
assert_decision "git switch -c feat/x → ask" ask "$(make_json "git switch -c feat/x")"
assert_decision "git checkout -b feat/x → ask" ask "$(make_json "git checkout -b feat/x")"
assert_decision "git switch -C feat/x (force-create) → ask" ask "$(make_json "git switch -C feat/x")"
assert_decision "git checkout -B feat/x (force-create) → ask" ask "$(make_json "git checkout -B feat/x")"
assert_decision "git switch --create feat/x (long form) → ask" ask "$(make_json "git switch --create feat/x")"
assert_decision "git worktree add -b feat/x ../wt → ask" ask "$(make_json "git worktree add -b feat/x ../wt")"
assert_decision "git worktree add ../wt -b feat/x (flag after path) → ask" \
    ask "$(make_json "git worktree add ../wt -b feat/x")"
assert_decision "git fetch origin && git switch -c feat/x (compound) → ask" \
    ask "$(make_json "git fetch origin && git switch -c feat/x")"
assert_decision "cd repo; git switch -c feat/x (semicolon compound) → ask" \
    ask "$(make_json "cd . ; git switch -c feat/x")"
assert_decision "sudo-prefixed create → ask" ask "$(make_json "sudo git switch -c feat/x")"
assert_decision "inline opt-out prefix is NOT honored → ask" \
    ask "$(make_json "CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD=1 git switch -c feat/x")"
assert_decision "git -C <repo> switch -c feat/x from an unrelated cwd → ask (#1389)" \
    ask "$(make_json "git -C $AHEAD switch -c feat/x" "/tmp")"
assert_exit "hook still exits 0 when it nudges" 0 "$(make_json "git switch -c feat/x")"

echo ""
echo "reason content:"
assert_reason_contains "reason names the new branch" "feat/x" "$(make_json "git switch -c feat/x")"
assert_reason_contains "reason carries the ahead count (2)" "2 commit(s) ahead" "$(make_json "git switch -c feat/x")"
assert_reason_contains "reason carries the literal suggested fix" \
    "git switch -c feat/x origin/main" "$(make_json "git switch -c feat/x")"
assert_reason_contains "reason names the verify command" \
    "git log --oneline origin/main..main" "$(make_json "git switch -c feat/x")"
assert_reason_contains "reason cites the source rule" "trap #2" "$(make_json "git switch -c feat/x")"

# ── Default-branch resolution (a hardcoded `main` fails this group) ──────────
echo ""
echo "default-branch resolution (master-default repo):"
assert_decision "master-default repo, ahead master → ask" \
    ask "$(make_json "git switch -c feat/x" "$MASTERD")"
assert_reason_contains "reason names origin/master, not origin/main" \
    "origin/master" "$(make_json "git switch -c feat/x" "$MASTERD")"
assert_reason_contains "suggested fix cuts from origin/master" \
    "git switch -c feat/x origin/master" "$(make_json "git switch -c feat/x" "$MASTERD")"

# ── Exemption 2 and the silent cases ────────────────────────────────────────
echo ""
echo "EXEMPTION 2 and repo-state exemptions (silent):"
assert_decision "HEAD on a feature branch → silent (stacking is deliberate)" \
    none "$(make_json "git switch -c feat/x" "$FEATURE")"
assert_decision "default branch in sync (0 ahead) → silent" \
    none "$(make_json "git switch -c feat/x" "$CLEAN")"
assert_decision "repo with no origin → silent" \
    none "$(make_json "git switch -c feat/x" "$NOREMOTE")"
assert_decision "detached HEAD → silent" \
    none "$(make_json "git switch -c feat/x" "$DETACH")"
assert_decision "cwd is not a git repo → silent" \
    none "$(make_json "git switch -c feat/x" "/tmp")"

# ── Non-triggering commands ─────────────────────────────────────────────────
echo ""
echo "non-triggering commands (silent):"
assert_decision "git switch feat/x (no -c) → silent" none "$(make_json "git switch feat/x")"
assert_decision "git checkout main → silent" none "$(make_json "git checkout main")"
assert_decision "git branch -a → silent" none "$(make_json "git branch -a")"
assert_decision "git branch -d old → silent" none "$(make_json "git branch -d old")"
assert_decision "git branch -vv → silent" none "$(make_json "git branch -vv")"
assert_decision "git branch newbranch → silent (documented out-of-scope gap)" \
    none "$(make_json "git branch newbranch")"
assert_decision "git status → silent" none "$(make_json "git status")"
assert_decision "ls -la → silent" none "$(make_json "ls -la")"
assert_decision "git worktree add ../wt (no -b) → silent" none "$(make_json "git worktree add ../wt")"
assert_decision "git worktree list → silent" none "$(make_json "git worktree list")"
assert_decision "empty command → silent" none \
    "$(make_json_sid "" "$AHEAD" "test-empty-$RANDOM")"
assert_decision "non-Bash tool_name → silent" none \
    "$(jq -nc --arg cwd "$AHEAD" '{tool_name:"Read",tool_input:{command:"git switch -c feat/x"},cwd:$cwd,session_id:"t-read"}')"

echo ""
echo "quote scrubbing (the command appears inside a string):"
assert_decision 'git commit -m "git switch -c feat/x" → silent' \
    none "$(make_json 'git commit -m "git switch -c feat/x"')"
assert_decision "echo 'git checkout -b x' → silent" \
    none "$(make_json "echo 'git checkout -b x'")"
assert_decision 'git commit -m "feat: git worktree add -b x ../wt" → silent' \
    none "$(make_json 'git commit -m "feat: git worktree add -b x ../wt"')"

echo ""
echo "remote-exec suppression (#1900):"
assert_decision "ssh host 'git switch -c feat/x' → silent" \
    none "$(make_json "ssh host 'git switch -c feat/x'")"
assert_decision "docker exec c git checkout -b feat/x → silent" \
    none "$(make_json "docker exec c git checkout -b feat/x")"
assert_decision "kubectl exec p -- git switch -c feat/x → silent" \
    none "$(make_json "kubectl exec p -- git switch -c feat/x")"

# ── Opt-out and dedup ───────────────────────────────────────────────────────
echo ""
echo "opt-out from the process environment:"
assert_decision_env "CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD=1 exported → silent" \
    none "$(make_json "git switch -c feat/x")" "CLAUDE_HOOKS_DISABLE_BRANCH_BASE_GUARD=1"

echo ""
echo "TTL dedup (one nudge per session+repo+default):"
DEDUP_JSON=$(make_json_sid "git switch -c feat/x" "$AHEAD" "dedup-session-fixed")
assert_decision "first invocation in a session → ask" ask "$DEDUP_JSON"
assert_decision "second identical invocation in the same session → silent" none "$DEDUP_JSON"
assert_decision_env "TTL=0 disables the dedup window → ask again" \
    ask "$DEDUP_JSON" "CLAUDE_HOOKS_BRANCH_BASE_TTL=0"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
