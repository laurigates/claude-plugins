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
#   - The block message's post-#2454 shape: preflight findings (REAL counts, not
#     a fixed template) + the single in-band tar escape + a pointer to
#     git-plugin:git-repo-delete-check, with ABSENCE assertions so the skill's
#     option list cannot be re-inlined here, and a commit-less repo whose
#     headline must not claim to be the only copy of a history that has no
#     commits
#   - The self-extinguishing backup escape — including the round trip that runs
#     the message's own tar command and re-runs the hook, so "the blocked user
#     can act on the message alone" is exercised rather than asserted by literal
#   - Silent degradation when git is unavailable or the tool is not Bash
#   - The macOS symlink-resolved temp path (#2465): operands are resolved with
#     `pwd -P`, so /var/folders/… (where /var is a symlink to /private/var)
#     arrives as /private/var/folders/… and must still be exempt
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/repo-deletion-safety.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
NOGIT_BIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
SIM=""
trap 'rm -rf "$WORK" "$NOGIT_BIN" ${SIM:+"$SIM"}' EXIT

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

# no-commits: `git init` and nothing else — the shape whose findings report is
# all zeros, so the block message must not claim to be the only copy of a
# history that does not exist (#2454).
mkdir -p "$WORK/no-commits"
git -C "$WORK/no-commits" init -q
git -C "$WORK/no-commits" config commit.gpgsign false
git -C "$WORK/no-commits" config user.email "test@test.com"
git -C "$WORK/no-commits" config user.name "Test"

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

# The ABSENCE half of the #2454 shed. Without it "the message no longer restates
# the skill's option list" is an unenforced claim: a later edit could re-inline
# the push option or a numbered list and every positive assertion above would
# still pass.
assert_stderr_lacks() { # $1 desc, $2 needle, $3 json
    local d="$1" needle="$2" json="$3"
    local err
    err=$(env "${HOOK_ENV[@]}" bash "$HOOK" 2>&1 >/dev/null <<<"$json" || true)
    case "$err" in
        *"$needle"*) printf "  FAIL: %s (stderr still carries %s)\n" "$d" "$needle"; FAIL=$((FAIL + 1)) ;;
        *) printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1)) ;;
    esac
}

# The temp-dir exemption is a `case` inside check_path(). Extract it verbatim
# and evaluate it against literal paths: on Linux `/private/var/folders/…`
# cannot be created, so this is the only way to actually EXERCISE that prefix
# rather than grep for its text — the syntactic-guard lesson of #1417.
EXEMPT_CASE=$(awk '/case "\$abs" in/{f=1} f{print} f && /esac/{exit}' "$HOOK")
case "$EXEMPT_CASE" in
    *esac*) ;;
    *) echo "FATAL: could not extract the temp-dir exemption case from $HOOK" >&2; exit 1 ;;
esac

path_is_exempt() { # $1 resolved path, $2 TMPROOT, $3 TMPROOT_REAL
    # shellcheck disable=SC2034  # all three are read by the eval'd case below
    local abs="$1" TMPROOT="$2" TMPROOT_REAL="$3"
    eval "$EXEMPT_CASE"
    return 1
}

assert_exempt() { # $1 desc, $2 want (yes|no), $3 path, $4 TMPROOT, $5 TMPROOT_REAL
    local d="$1" want="$2"
    shift 2
    local got=no
    path_is_exempt "$@" && got=yes
    if [ "$got" = "$want" ]; then
        printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exempt=%s, got %s)\n" "$d" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
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
# Shape after #2454: findings + the ONE in-band escape + a pointer to the skill
# that owns the option list. The absence assertions are the regression gate —
# re-inlining any of the skill's other options is exactly the drift this shed
# removed, and it must fail here rather than go unnoticed.
echo ""
echo "block message reports findings and points at the skill (not a second copy of it):"
assert_stderr_contains "names the blocked path" "$WORK/lonely" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "reports the preflight findings" "git rev-list --all --count" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "counts the repo's local branches" "git for-each-ref refs/heads" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "keeps the tar escape verbatim" "$WORK/backups/lonely-" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "names the skill as the option-list authority" "git-repo-delete-check" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_contains "warns against self-serving the opt-out" "Do not self-serve" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_lacks "does not restate the skill's push option" "push -u origin --all" "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_lacks "does not re-enumerate a numbered option list" "  2. " "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_lacks "does not restate the skill's delete-with-no-backup option" "handling-blocked-hooks.md" "$(make_json "rm -rf $WORK/lonely")"

# The findings are REAL counts, not a fixed template. Without this the four rows
# could all print 0 and every assertion above would still pass. Parsed by field
# rather than by literal spacing so a column re-align is not a spurious failure.
assert_finding() { # $1 desc, $2 row-label, $3 want, $4 json
    local d="$1" label="$2" want="$3" json="$4"
    local err got
    err=$(env "${HOOK_ENV[@]}" bash "$HOOK" 2>&1 >/dev/null <<<"$json" || true)
    got=$(printf '%s\n' "$err" | awk -v l="$label" '$0 ~ l {print $NF; exit}')
    if [ "$got" = "$want" ]; then
        printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got '%s')\n" "$d" "$want" "$got"; FAIL=$((FAIL + 1))
    fi
}
assert_finding "reports the repo's real commit count" "rev-list --all --count" 2 \
    "$(make_json "rm -rf $WORK/lonely")"
assert_finding "reports the repo's real branch count" "for-each-ref refs/heads" 1 \
    "$(make_json "rm -rf $WORK/lonely")"

# ── Block message on a commit-less repo (#2454 problem 6) ─────────────────────
# A findings block of all zeros beside "the ONLY copy of its history" argues
# against its own block. The headline must adapt instead.
echo ""
echo "block message on a repo with no commits does not contradict itself:"
assert_exit "a commit-less remote-less repo still blocks" 2 "$(make_json "rm -rf $WORK/no-commits")"
assert_stderr_lacks "drops the ONLY-copy-of-its-history claim" "ONLY copy of its history" \
    "$(make_json "rm -rf $WORK/no-commits")"
assert_stderr_contains "says the repo has no commits yet" "no commits yet" \
    "$(make_json "rm -rf $WORK/no-commits")"
assert_stderr_contains "explains why an empty findings report still blocks" "found nothing at all" \
    "$(make_json "rm -rf $WORK/no-commits")"
# Guard integrity: the populated repo must NOT take the empty-repo branch, or the
# two assertions above would hold against a hook that always says "no commits".
assert_stderr_contains "a populated repo keeps the ONLY-copy headline" "ONLY copy of its history" \
    "$(make_json "rm -rf $WORK/lonely")"
assert_stderr_lacks "a populated repo omits the found-nothing note" "found nothing at all" \
    "$(make_json "rm -rf $WORK/lonely")"

# ── Findings probes stay bounded (#2454 problem 7) ────────────────────────────
# emit_block runs on the BLOCKING path, and this hook fails OPEN on timeout — an
# unbounded probe would convert an already-decided hard block into a deletion.
# Measured on a 200,000-commit graph: `git rev-list --all --count` takes 1281 ms
# (26% of the 5000 ms PreToolUse budget, from one probe, scaling with repo size)
# against 21 ms with --max-count=500.
#
# No behavioural assertion can see this: a fixture repo is small, so a capped and
# an uncapped probe print the same number. The bound is therefore pinned
# STRUCTURALLY, over emit_block's body only — classify()'s tier-2 probes sit on
# the opt-in, non-blocking `ask` path and are deliberately not covered.
echo ""
echo "every findings probe on the blocking path is bounded:"
EMIT_BLOCK_BODY=$(awk '/^emit_block\(\) \{/{f=1} f{print} f && /^\}/{exit}' "$HOOK")
case "$EMIT_BLOCK_BODY" in
    *"block \"BLOCKED:"*) ;;
    *) echo "FATAL: could not extract emit_block() from $HOOK" >&2; exit 1 ;;
esac

assert_bounded() { # $1 desc, $2 probe substring, $3 required bound substring
    local d="$1" probe="$2" bound="$3" line
    # Only real invocations: `git -C "$abs" …`. The rendered message quotes the
    # same command names as row labels, and matching those would let a stripped
    # flag hide behind its own documentation.
    line=$(printf '%s\n' "$EMIT_BLOCK_BODY" | grep -F 'git -C "$abs"' | grep -F -- "$probe" | head -1)
    if [ -z "$line" ]; then
        printf "  FAIL: %s (emit_block no longer runs '%s')\n" "$d" "$probe"; FAIL=$((FAIL + 1))
        return 0
    fi
    case "$line" in
        *"$bound"*) printf "  PASS: %s\n" "$d"; PASS=$((PASS + 1)) ;;
        *) printf "  FAIL: %s (unbounded: %s)\n" "$d" "$line"; FAIL=$((FAIL + 1)) ;;
    esac
}

assert_bounded "the object-graph walk is capped" "rev-list --all --count" "--max-count="
assert_bounded "the refs/heads scan is capped" "for-each-ref" "--count="
assert_bounded "the stash reflog read is capped" "stash list" "--max-count="
assert_bounded "the working-tree scan is capped" "status --porcelain" "| head -"

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

# ── macOS symlink-resolved temp paths (#2465) ─────────────────────────────────
# Operands reach the exemption already resolved by `pwd -P`. On macOS /var is a
# symlink to /private/var, so a real `mktemp -d` under $TMPDIR arrives as
# /private/var/folders/… — matching NONE of the unresolved prefixes. The
# exemption then never fired for the actual macOS temp path.
echo ""
echo "temp-dir prefixes, evaluated against symlink-resolved paths (#2465):"
assert_exempt "resolved macOS temp path (/private/var/folders/…) is exempt" yes \
    "/private/var/folders/qz/9k1_/T/lonely" "/tmp" "/tmp"
assert_exempt "unresolved /var/folders/… stays exempt" yes \
    "/var/folders/qz/9k1_/T/lonely" "/tmp" "/tmp"
assert_exempt "resolved /private/tmp stays exempt" yes "/private/tmp/lonely" "/tmp" "/tmp"
assert_exempt "plain /tmp stays exempt" yes "/tmp/lonely" "/tmp" "/tmp"
assert_exempt "a symlink-resolved \$TMPDIR outside /var/folders is exempt" yes \
    "/private/scratch/T/lonely" "/scratch/T" "/private/scratch/T"
assert_exempt "an ordinary checkout is NOT exempt" no \
    "/Users/dev/repos/lonely" "/var/folders/qz/9k1_/T" "/private/var/folders/qz/9k1_/T"

# End-to-end: a tree shaped like macOS's (`var` → `private/var`) with $TMPDIR
# pointing through the symlink. The base must sit OUTSIDE every hardcoded temp
# prefix, or /tmp/* would exempt the fixture on Linux and the assertion would
# pass for the wrong reason.
for sim_cand in "${HOME:-}" "$(cd "$(dirname "$HOOK")/../.." && pwd -P)"; do
    if [ -z "$sim_cand" ] || [ ! -d "$sim_cand" ] || [ ! -w "$sim_cand" ]; then continue; fi
    sim_real=$(cd "$sim_cand" 2>/dev/null && pwd -P) || continue
    case "$sim_real" in /tmp|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) continue ;; esac
    SIM=$(mktemp -d "$sim_real/.repo-del-sim-XXXXXX" 2>/dev/null) || SIM=""
    [ -n "$SIM" ] && break
done

if [ -n "$SIM" ]; then
    mkdir -p "$SIM/private/var/folders/qz/T/lonely"
    ln -s "private/var" "$SIM/var"
    new_repo "$SIM/private/var/folders/qz/T/lonely"
    assert_exit "repo under a symlinked \$TMPDIR is exempt (macOS shape)" 0 \
        "$(make_json "rm -rf $SIM/var/folders/qz/T/lonely")" \
        CLAUDE_HOOKS_REPO_DELETION_TMP_EXEMPT=1 TMPDIR="$SIM/var/folders/qz/T"
    assert_exit "the same repo still blocks with the exemption off" 2 \
        "$(make_json "rm -rf $SIM/var/folders/qz/T/lonely")" TMPDIR="$SIM/var/folders/qz/T"
else
    printf "  SKIP: no writable non-temp base for the symlinked-\$TMPDIR fixture\n"
fi

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
# The round trip first: extract the tar command the block message actually
# PRINTED, RUN it, and re-run the hook. That is the acceptance property of #2454
# — after trimming the option list, the blocked user must still be able to act on
# the message alone — and a literal grep would not catch a command that no longer
# produces a name the escape glob matches.
echo ""
echo "self-extinguishing backup escape (allow, exit 0):"
MSG=$(env "${HOOK_ENV[@]}" bash "$HOOK" 2>&1 >/dev/null <<<"$(make_json "rm -rf $WORK/lonely")" || true)
# `head -1` matters: without it a second `tar -c` line would make TAR_CMD
# multi-line and `eval` would run both.
TAR_CMD=$(printf '%s\n' "$MSG" | grep -F 'tar -c' | head -1 | sed 's/^[[:space:]]*//' || true)
if [ -n "$TAR_CMD" ]; then
    printf "  PASS: %s\n" "the block message carries a runnable backup command"; PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "the block message carries a runnable backup command"; FAIL=$((FAIL + 1))
fi
( eval "$TAR_CMD" ) >/dev/null 2>&1 || true
assert_exit "running the message's own tar command clears the block" 0 "$(make_json "rm -rf $WORK/lonely")"

rm -f "$WORK"/backups/lonely-*.tar.*
touch "$WORK/backups/lonely-2026-08-19.tar.gz"
assert_exit "an existing dated backup tarball clears the block" 0 "$(make_json "rm -rf $WORK/lonely")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
