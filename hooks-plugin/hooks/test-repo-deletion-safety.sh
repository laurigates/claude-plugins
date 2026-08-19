#!/usr/bin/env bash
# Regression tests for repo-deletion-safety.sh
#
# Run: bash hooks-plugin/hooks/test-repo-deletion-safety.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers:
#   - Tier 1a (no remote) and 1b (remote configured, never pushed) → exit 2
#   - Flag forms (-rf / -fr / -r -f / --recursive) and prefix stripping
#     (sudo / command / env / leading VAR=value), including the decisive
#     anti-self-serve case: an inline
#     CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY=1 prefix is NOT honored
#   - Safety blocks fire inside compound commands (not narrowed like the
#     context-budget read-blocks of #2148)
#   - The false-positive set that matters more than the positives: a path
#     INSIDE a repo, linked worktrees, symlinks, non-repos, globs,
#     unresolvable $VAR / $(…) / {} operands, remote-exec (#1900), and the
#     command text appearing inside a quoted string
#   - Tier 2 (opt-in `ask` on a remote-backed but dirty repo), default-off
#   - The self-extinguishing backup escape, and silent degradation when git
#     is unavailable or the tool is not Bash
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/repo-deletion-safety.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
NOGIT_BIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$WORK" "$NOGIT_BIN"' EXIT

mkdir -p "$WORK/home" "$WORK/backups" "$WORK/plain"

# The fixture tree lives under mktemp -d, which the hook exempts by DEFAULT.
# Turning the exemption off is what makes every positive assertion below real
# rather than a silent false pass.
HOOK_ENV=(
    HOME="$WORK/home"
    CLAUDE_REPO_BACKUP_DIR="$WORK/backups"
    CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT=0
)

new_repo() { # $1 dir
    git -C "$1" init -q
    git -C "$1" config commit.gpgsign false
    git -C "$1" config user.email "test@test.com"
    git -C "$1" config user.name "Test"
    git -C "$1" commit --allow-empty -m "initial" -q
    git -C "$1" branch -M main >/dev/null 2>&1 || true
}

# ── Fixtures ──────────────────────────────────────────────────────────────────
# lonely: a repo with NO remote — the headline case.
mkdir -p "$WORK/lonely"; new_repo "$WORK/lonely"
echo "# readme" > "$WORK/lonely/README.md"
git -C "$WORK/lonely" add README.md
git -C "$WORK/lonely" commit -q -m "docs: readme"

# backed: a repo with a real bare origin and pushed refs. The `wt/` and
# `node_modules/` fixtures live inside it, so they are gitignored (committed
# BEFORE the push) to keep the tier-2 "clean tree" assertion honest.
mkdir -p "$WORK/backed"; new_repo "$WORK/backed"
printf 'wt/\nnode_modules/\ndirty.txt\n' > "$WORK/backed/.gitignore"
git -C "$WORK/backed" add .gitignore
git -C "$WORK/backed" commit -q -m "chore: ignore fixture dirs"
git init -q --bare "$WORK/origin.git"
git -C "$WORK/backed" remote add origin "$WORK/origin.git"
git -C "$WORK/backed" push -q -u origin main
git -C "$WORK/backed" fetch -q origin
git -C "$WORK/backed" worktree add --detach "$WORK/backed/wt" -q >/dev/null 2>&1
mkdir -p "$WORK/backed/node_modules"

# added-never-pushed: tier 1b — a remote is configured but nothing reached it.
mkdir -p "$WORK/added-never-pushed"; new_repo "$WORK/added-never-pushed"
git -C "$WORK/added-never-pushed" remote add origin "$WORK/never-created.git"

# bare.git: a remote-less bare repo is also the only copy of its history.
git init -q --bare "$WORK/bare.git"

# parent/inner: a remote-less repo one level below a plain directory.
mkdir -p "$WORK/parent/inner"; new_repo "$WORK/parent/inner"

# link: a symlink to a remote-less repo.
ln -s "$WORK/lonely" "$WORK/link"

# A PATH containing jq but NOT git, for the degradation assertion.
ln -s "$(command -v jq)" "$NOGIT_BIN/jq"
ln -s "$(command -v cat)" "$NOGIT_BIN/cat"

# ── Helpers ───────────────────────────────────────────────────────────────────
make_json() { # $1 command, $2 cwd
    jq -nc --arg cmd "$1" --arg cwd "${2:-$WORK}" --arg sid "test-$RANDOM-$RANDOM" \
        '{tool_name:"Bash",tool_input:{command:$cmd},cwd:$cwd,session_id:$sid}'
}

assert_exit() { # $1 desc, $2 want-exit, $3 json, [extra VAR=val ...]
    local d="$1" want="$2" json="$3"
    shift 3
    local got=0
    # Here-string, not a pipe: the hook may exit before reading stdin (missing
    # git, non-Bash tool), and a pipe would then hand the writer SIGPIPE and
    # report 141 as if the hook had failed.
    env "${HOOK_ENV[@]}" "$@" bash "$HOOK" >/dev/null 2>&1 <<<"$json" || got=$?
    if [ "$got" -eq "$want" ]; then
        printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$d" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}

assert_decision() { # $1 desc, $2 want-decision, $3 json, [extra VAR=val ...]
    local d="$1" want="$2" json="$3"
    shift 3
    local out got
    out=$(env "${HOOK_ENV[@]}" "$@" bash "$HOOK" 2>/dev/null <<<"$json")
    if [ -z "$out" ]; then
        got=none
    else
        got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo parse_error)
    fi
    if [ "$got" = "$want" ]; then
        printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$d" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}

assert_stderr_contains() { # $1 desc, $2 needle, $3 json
    local d="$1" needle="$2" json="$3"
    local err
    err=$(env "${HOOK_ENV[@]}" bash "$HOOK" 2>&1 >/dev/null <<<"$json" || true)
    case "$err" in
        *"$needle"*) printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1)) ;;
        *) printf "  FAIL: %s (stderr missing %s)\n" "$d" "$needle"; FAIL=$((FAIL + 1)) ;;
    esac
}

echo "=== repo-deletion-safety hook tests ==="

# ── Tier 1a: remote-less repo → block ─────────────────────────────────────────
echo ""
echo "tier 1a — remote-less repo (block, exit 2):"
assert_exit "rm -rf on a remote-less repo blocks" 2 "$(make_json "rm -rf $WORK/lonely")"
assert_exit "trailing slash is normalised" 2 "$(make_json "rm -rf $WORK/lonely/")"
assert_exit "relative operand resolves against hook cwd" 2 "$(make_json "rm -rf lonely" "$WORK")"
assert_exit "the .git dir of a remote-less repo blocks" 2 "$(make_json "rm -rf $WORK/lonely/.git")"
assert_exit "remote-less bare repo blocks" 2 "$(make_json "rm -rf $WORK/bare.git")"

# ── Flag forms ────────────────────────────────────────────────────────────────
echo ""
echo "recursion flag forms (block, exit 2):"
assert_exit "rm -fr blocks" 2 "$(make_json "rm -fr $WORK/lonely")"
assert_exit "rm -r -f blocks" 2 "$(make_json "rm -r -f $WORK/lonely")"
assert_exit "rm -R blocks" 2 "$(make_json "rm -R $WORK/lonely")"
assert_exit "rm --recursive --force blocks" 2 "$(make_json "rm --recursive --force $WORK/lonely")"
assert_exit "rm -rf -- <path> blocks (-- separator)" 2 "$(make_json "rm -rf -- $WORK/lonely")"

# ── Prefix stripping ──────────────────────────────────────────────────────────
echo ""
echo "command prefixes are stripped (block, exit 2):"
assert_exit "sudo rm -rf blocks" 2 "$(make_json "sudo rm -rf $WORK/lonely")"
assert_exit "command rm -rf blocks" 2 "$(make_json "command rm -rf $WORK/lonely")"
assert_exit "env rm -rf blocks" 2 "$(make_json "env rm -rf $WORK/lonely")"
assert_exit "inline opt-out prefix is NOT honored" 2 \
    "$(make_json "CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY=1 rm -rf $WORK/lonely")"

# ── Compound commands ─────────────────────────────────────────────────────────
echo ""
echo "safety blocks fire inside compound commands (block, exit 2):"
assert_exit "cd /tmp && rm -rf <repo> blocks" 2 "$(make_json "cd /tmp && rm -rf $WORK/lonely")"
assert_exit "make clean && rm -rf <repo> blocks" 2 "$(make_json "make clean && rm -rf $WORK/lonely")"
assert_exit "; separated statement blocks" 2 "$(make_json "ls -1; rm -rf $WORK/lonely")"
assert_exit "|| separated statement blocks" 2 "$(make_json "test -d x || rm -rf $WORK/lonely")"
assert_exit "newline separated statement blocks" 2 "$(make_json "ls -1
rm -rf $WORK/lonely")"
assert_exit "subshell statement blocks" 2 "$(make_json "(cd /tmp && rm -rf $WORK/lonely)")"

# ── Tier 1b and the parent scan ───────────────────────────────────────────────
echo ""
echo "tier 1b + parent scan (block, exit 2):"
assert_exit "remote added but never pushed blocks" 2 "$(make_json "rm -rf $WORK/added-never-pushed")"
assert_exit "parent dir holding a remote-less repo blocks" 2 "$(make_json "rm -rf $WORK/parent")"
assert_exit "multi-operand: second operand still fires" 2 "$(make_json "rm -rf $WORK/plain $WORK/lonely")"

# ── Block message content ─────────────────────────────────────────────────────
echo ""
echo "block message carries the three-option remediation:"
assert_stderr_contains "names the blocked path" "$WORK/lonely" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "option 1 — push to a remote" "push -u origin --all" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "option 2 — tar to a labelled backup" "$WORK/backups/lonely-" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "option 3 — delegate per handling-blocked-hooks" "handling-blocked-hooks.md" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "warns against self-serving the opt-out" "Do not self-serve" "$(make_json "rm -rf $WORK/lonely")"

# ── False positives: the half that matters ────────────────────────────────────
echo ""
echo "false positives (allow, exit 0):"
assert_exit "repo with a pushed remote is not blocked" 0 "$(make_json "rm -rf $WORK/backed")"
assert_exit "a path INSIDE a repo is not blocked" 0 "$(make_json "rm -rf $WORK/backed/node_modules")"
assert_exit "a linked worktree is not blocked" 0 "$(make_json "rm -rf $WORK/backed/wt")"
assert_exit "the .git of a remote-backed repo is not blocked" 0 "$(make_json "rm -rf $WORK/backed/.git")"
assert_exit "a plain non-repo directory is not blocked" 0 "$(make_json "rm -rf $WORK/plain")"
assert_exit "a missing path is not blocked" 0 "$(make_json "rm -rf $WORK/does-not-exist")"
assert_exit "a symlink to a repo is not blocked" 0 "$(make_json "rm -rf $WORK/link")"
assert_exit "rm -f (no recursion) is not blocked" 0 "$(make_json "rm -f $WORK/lonely/README.md")"
assert_exit "rm without flags is not blocked" 0 "$(make_json "rm $WORK/lonely/README.md")"
assert_exit "a glob operand is skipped" 0 "$(make_json "rm -rf $WORK/lonely/*")"
# shellcheck disable=SC2016  # literal $SOME_VAR is the point of the assertion
assert_exit "an unexpanded \$VAR operand fails open" 0 "$(make_json 'rm -rf "$SOME_VAR"')"
# shellcheck disable=SC2016
assert_exit "a \$(…) operand fails open" 0 "$(make_json 'rm -rf $(mktemp -d)')"
assert_exit "find -exec {} fails open" 0 "$(make_json 'find . -name build -exec rm -rf {} \;')"
assert_exit "ssh remote-exec is suppressed" 0 "$(make_json "ssh host 'rm -rf $WORK/lonely'")"
assert_exit "docker remote-exec is suppressed" 0 "$(make_json "docker exec c rm -rf $WORK/lonely")"
assert_exit "quoted occurrence in echo does not fire" 0 "$(make_json "echo \"rm -rf $WORK/lonely\"")"
assert_exit "quoted occurrence in a commit message does not fire" 0 \
    "$(make_json "git commit -m \"rm -rf the old repo\"")"
assert_exit "a separator inside a quoted string does not split" 0 \
    "$(make_json "git commit -m \"cleanup; rm -rf $WORK/lonely\"")"
assert_exit "temp-dir exemption (default on) allows a remote-less repo" 0 \
    "$(make_json "rm -rf $WORK/lonely")" CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT=1

# ── Tier 2: opt-in ask on a dirty but remote-backed repo ──────────────────────
echo ""
echo "tier 2 — dirty remote-backed repo (opt-in ask):"
assert_decision "clean tree with WARN_DIRTY=1 stays silent" none \
    "$(make_json "rm -rf $WORK/backed")" CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY=1
echo "scratch" > "$WORK/backed/untracked.txt"
assert_decision "untracked file with WARN_DIRTY=1 asks" ask \
    "$(make_json "rm -rf $WORK/backed")" CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY=1
assert_decision "same dirty tree is silent by default (WARN_DIRTY unset)" none \
    "$(make_json "rm -rf $WORK/backed")"
assert_exit "tier 2 never escalates to exit 2" 0 \
    "$(make_json "rm -rf $WORK/backed")" CLAUDE_HOOKS_REPO_DELETION_WARN_DIRTY=1
rm -f "$WORK/backed/untracked.txt"

# ── Degradation ───────────────────────────────────────────────────────────────
echo ""
echo "degradation (allow silently, exit 0):"
assert_exit "non-Bash tool passes through" 0 \
    "$(jq -nc --arg cmd "rm -rf $WORK/lonely" --arg cwd "$WORK" \
        '{tool_name:"Read",tool_input:{command:$cmd},cwd:$cwd,session_id:"x"}')"
assert_exit "empty command passes through" 0 \
    "$(jq -nc --arg cwd "$WORK" '{tool_name:"Bash",tool_input:{command:""},cwd:$cwd,session_id:"x"}')"
assert_exit "non-rm command passes through" 0 "$(make_json "ls -la $WORK/lonely")"
assert_exit "operator opt-out from the environment is honored" 0 \
    "$(make_json "rm -rf $WORK/lonely")" CLAUDE_HOOKS_DISABLE_REPO_DELETION_SAFETY=1

GOT=0
env "${HOOK_ENV[@]}" PATH="$NOGIT_BIN" "$BASH" "$HOOK" >/dev/null 2>&1 \
    <<<"$(make_json "rm -rf $WORK/lonely")" || GOT=$?
if [ "$GOT" -eq 0 ]; then
    printf "  PASS: %s\n" "missing git degrades silently"; PASS=$((PASS + 1))
else
    printf "  FAIL: %s (expected exit 0, got %d)\n" "missing git degrades silently" "$GOT"; FAIL=$((FAIL + 1))
fi

# ── Self-extinguishing backup escape (run last: it clears the block) ──────────
echo ""
echo "self-extinguishing backup escape (allow, exit 0):"
touch "$WORK/backups/lonely-2026-08-19.tar.gz"
assert_exit "an existing dated backup tarball clears the block" 0 "$(make_json "rm -rf $WORK/lonely")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
