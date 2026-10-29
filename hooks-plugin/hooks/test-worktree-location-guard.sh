#!/usr/bin/env bash
# Regression tests for worktree-location-guard.sh
#
# Run: bash hooks-plugin/hooks/test-worktree-location-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook always exits 0 and signals a deny by emitting a PreToolUse
# permissionDecision:"deny" JSON envelope on stdout, so assertions read that
# stdout rather than exit codes.
#
# Covers:
#   - The hook's OWN suggested fix must be allowed (extracted from the deny
#     message and re-fed), or a deny becomes a retry loop.
#   - Sibling (`../<repo>-wt-x`), in-repo-but-not-.claude/worktrees, and `~`
#     paths are denied; `.claude/worktrees/<name>` is allowed.
#   - Cross-repo: `git -C <other-repo> worktree add ../x` resolves against the
#     -C repo, and `git -C <repo> worktree add <repo>/.claude/worktrees/x` from
#     an unrelated cwd is allowed.
#   - A session inside a linked worktree targets the MAIN repo's
#     .claude/worktrees/, not its own.
#   - Temp-dir scratch worktrees, unresolvable `$VAR` paths, quoted mentions,
#     `git worktree list`, non-repo cwd, remote-exec and the opt-out are silent.
set -uo pipefail

# Neutralize any inherited git context before building sandbox repos (issue
# #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK="$(cd "$(dirname "$0")" && pwd)/worktree-location-guard.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "$WORK" ] || { echo "mktemp -d produced no dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
WORK=$(cd -P -- "$WORK" && pwd -P)

# The hook exempts /tmp, /private/tmp, /var/folders and $TMPDIR, and mktemp -d
# lands under one of those — fixture repos there would be allowed wholesale. So
# the repos live under $HOME/.cache, which must not itself be inside a git work
# tree (the "non-repo cwd" case would silently test nothing); $WORK only serves
# as the $TMPDIR scratch target.
mkdir -p "$HOME/.cache" || { echo "FATAL: cannot create $HOME/.cache" >&2; exit 1; }
FIXBASE=$(mktemp -d "$HOME/.cache/wtguard.XXXXXX") || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
# shellcheck disable=SC2015  # the guard shape check-git-sandbox-guards.sh requires
[ -n "$FIXBASE" ] && [ -d "$FIXBASE" ] || { echo "FATAL: invalid sandbox dir '$FIXBASE'" >&2; exit 1; }
FIXBASE=$(cd -P -- "$FIXBASE" && pwd -P)
if git -C "$FIXBASE" rev-parse --git-dir >/dev/null 2>&1; then
    rm -rf "$FIXBASE"; echo "fixture base $FIXBASE is inside a git work tree" >&2; exit 1
fi
trap 'rm -rf "$WORK" "$FIXBASE"' EXIT
export TMPDIR="$WORK"

setup_repo() {
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config commit.gpgsign false
    git -C "$1" config user.email "test@test.com"
    git -C "$1" config user.name "Test"
    git -C "$1" commit --allow-empty -m "initial" -q
}

REPO="$FIXBASE/infra"
OTHER="$FIXBASE/app"
NOTREPO="$FIXBASE/plain"
setup_repo "$REPO"
setup_repo "$OTHER"
mkdir -p "$NOTREPO"
LINKED="$REPO/.claude/worktrees/existing"
git -C "$REPO" worktree add -q --detach "$LINKED" 2>/dev/null

make_json() {       # $1 command, $2 cwd
    jq -nc --arg cmd "$1" --arg cwd "$2" \
        '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,session_id:"t"}'
}

decision_of() {
    if [ -z "$1" ]; then printf 'none'; else
        printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || printf 'parse_error'
    fi
}

assert_decision() { # $1 desc, $2 expected, $3 json [, $4 VAR=value]
    local out got
    if [ -n "${4:-}" ]; then
        out=$(printf '%s' "$3" | env "$4" bash "$HOOK" 2>/dev/null)
    else
        out=$(printf '%s' "$3" | bash "$HOOK" 2>/dev/null)
    fi
    got=$(decision_of "$out")
    if [ "$got" = "$2" ]; then
        printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$1" "$2" "$got"; FAIL=$((FAIL + 1))
    fi
}

reason_of() {
    printf '%s' "$1" | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null
}

assert_reason_contains() { # $1 desc, $2 needle, $3 json
    case "$(reason_of "$3")" in
        *"$2"*) printf "  PASS: %s\n" "$1"; PASS=$((PASS + 1)) ;;
        *) printf "  FAIL: %s (reason lacks '%s')\n" "$1" "$2"; FAIL=$((FAIL + 1)) ;;
    esac
}

echo "=== Denied: paths outside <repo>/.claude/worktrees ==="
assert_decision "sibling ../infra-wt-x → deny" deny \
    "$(make_json "git worktree add -q -b feat/x ../infra-wt-x origin/main" "$REPO")"
assert_decision "in-repo worktrees/x (not .claude) → deny" deny \
    "$(make_json "git worktree add worktrees/x -b feat/x origin/main" "$REPO")"
assert_decision "absolute sibling path → deny" deny \
    "$(make_json "git worktree add $FIXBASE/infra-task feat/y" "$REPO")"
assert_decision "chained after fetch → deny" deny \
    "$(make_json "git fetch -q origin && git worktree add -b feat/x ../infra-wt-x origin/main && cd ../infra-wt-x" "$REPO")"
assert_decision "inline opt-out prefix is ignored → deny" deny \
    "$(make_json "CLAUDE_HOOKS_DISABLE_WORKTREE_LOCATION_GUARD=1 git worktree add ../x" "$REPO")"
assert_decision "bare .claude/worktrees itself → deny" deny \
    "$(make_json "git worktree add .claude/worktrees" "$REPO")"

echo "=== Cross-repo resolution ==="
assert_decision "git -C <other repo> worktree add ../x from unrelated cwd → deny" deny \
    "$(make_json "git -C $REPO worktree add ../infra-wt-x -b feat/x origin/main" "$OTHER")"
assert_decision "git -C <repo> worktree add <repo>/.claude/worktrees/x from unrelated cwd → allow" none \
    "$(make_json "git -C $REPO worktree add -b feat/x $REPO/.claude/worktrees/x origin/main" "$OTHER")"
assert_decision "relative -C resolved against cwd → allow" none \
    "$(make_json "git -C ../infra worktree add .claude/worktrees/x -b feat/x" "$OTHER")"
assert_reason_contains "cross-repo deny names the -C repo's .claude/worktrees" \
    "$REPO/.claude/worktrees" \
    "$(make_json "git -C $REPO worktree add ../infra-wt-x -b feat/x origin/main" "$OTHER")"

echo "=== Linked-worktree cwd targets the MAIN repo ==="
assert_decision "from linked worktree, nested under its own .claude/worktrees → deny" deny \
    "$(make_json "git worktree add .claude/worktrees/y -b feat/y" "$LINKED")"
assert_decision "from linked worktree, main repo's .claude/worktrees via .. → allow" none \
    "$(make_json "git worktree add ../y -b feat/y" "$LINKED")"

echo "=== Allowed ==="
assert_decision ".claude/worktrees/<name> relative → allow" none \
    "$(make_json "git worktree add -b feat/x .claude/worktrees/x origin/main" "$REPO")"
assert_decision ".claude/worktrees/<name> absolute → allow" none \
    "$(make_json "git worktree add $REPO/.claude/worktrees/x feat/x" "$REPO")"
assert_decision "quoted path into .claude/worktrees → allow" none \
    "$(make_json "git worktree add \"$REPO/.claude/worktrees/x\" feat/x" "$REPO")"
assert_decision "-- separator before the path → allow" none \
    "$(make_json "git worktree add -b feat/x -- .claude/worktrees/x origin/main" "$REPO")"
assert_decision "--lock --reason <s> before path → allow" none \
    "$(make_json "git worktree add --lock --reason keep .claude/worktrees/x" "$REPO")"
assert_decision "\$TMPDIR scratch worktree → allow" none \
    "$(make_json "git worktree add --detach $WORK/scratch HEAD" "$REPO")"
assert_decision "/tmp scratch worktree → allow" none \
    "$(make_json "git worktree add --detach /tmp/wt-check HEAD" "$REPO")"

echo "=== Silent (not applicable) ==="
assert_decision "\$VAR path (unresolvable) → silent" none \
    "$(make_json "git worktree add \"\$WT\" -b feat/x" "$REPO")"
assert_decision "command substitution path → silent" none \
    "$(make_json "git worktree add \$(mktemp -d) HEAD" "$REPO")"
assert_decision "git worktree list → silent" none "$(make_json "git worktree list" "$REPO")"
assert_decision "git worktree remove ../x → silent" none "$(make_json "git worktree remove ../infra-wt-x" "$REPO")"
assert_decision "quoted mention in commit message → silent" none \
    "$(make_json "git commit -m 'git worktree add ../x'" "$REPO")"
assert_decision "non-repo cwd → silent" none "$(make_json "git worktree add ../x" "$NOTREPO")"
assert_decision "remote-exec → silent" none "$(make_json "ssh host git worktree add ../x" "$REPO")"
assert_decision "non-Bash tool → silent" none \
    "$(jq -nc --arg cwd "$REPO" '{tool_name:"Read",tool_input:{file_path:"x"},cwd:$cwd}')"
assert_decision "string tool_input → silent" none '{"tool_name":"Bash","tool_input":"git worktree add ../x"}'
assert_decision "opt-out env from operator shell → silent" none \
    "$(make_json "git worktree add ../x" "$REPO")" CLAUDE_HOOKS_DISABLE_WORKTREE_LOCATION_GUARD=1

echo "=== Deny message ==="
J=$(make_json "git worktree add -q -b feat/x ../infra-wt-cost-shed origin/main" "$REPO")
assert_reason_contains "headline tag" "WORKTREE LOCATION:" "$J"
assert_reason_contains "names the resolved target" "$FIXBASE/infra-wt-cost-shed" "$J"
assert_reason_contains "strips <repo>-wt- prefix in the suggested name" "$REPO/.claude/worktrees/cost-shed" "$J"
assert_reason_contains "keeps the branch and start-point" "-b feat/x" "$J"
assert_reason_contains "points at the audit recipe" "worktree-audit" "$J"

# The suggested fix must itself be allowed — extract it, never retype it.
FIX=$(reason_of "$J" | sed -n 's/^  \(git -C .* worktree add .*\)$/\1/p' | head -1)
if [ -n "$FIX" ]; then
    assert_decision "suggested fix (extracted from message) → allow" none "$(make_json "$FIX" "$OTHER")"
else
    printf "  FAIL: could not extract suggested fix from deny message\n"; FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
