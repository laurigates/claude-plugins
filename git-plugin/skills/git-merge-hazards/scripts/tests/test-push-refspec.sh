#!/usr/bin/env bash
# test-push-refspec.sh — semantic regression test for the push-by-SHA refspec
# form prescribed by the git-merge-hazards skill (issue #2478).
#
# The skill told readers to push a resolved tip as `<sha>:<branch>`. That short
# form is only accepted when `<branch>` ALREADY EXISTS on the remote: the left
# side is a bare commit object, so git has no ref namespace to infer the
# destination from and refuses rather than guessing:
#
#   error: The destination you provided is not a full refname (i.e.,
#   starting with "refs/").
#
# The gap was easy to miss because the stacked-chain scenario the guidance was
# written from always has the child branch already pushed — and it landed
# hardest in the auto-close RECOVERY path, which explicitly opens a fresh PR
# from a branch that may not exist remotely yet.
#
# A grep for `refs/heads/` in the SKILL.md would be a syntactic-only gate — it
# would pass just as happily against a wrong claim about git (the #1417 → #1819
# lesson in `.claude/rules/regression-testing.md`). So this test EXECUTES git:
#
#   1. `<sha>:<branch>` FAILS for a branch absent from the remote  (the defect)
#   2. `<sha>:refs/heads/<branch>` SUCCEEDS in the same situation  (the fix)
#   3. `<sha>:<branch>` still succeeds once the branch exists      (guard
#      integrity — without it, a git that rejected every SHA refspec would
#      satisfy assertion 1 and the test would prove nothing)
#   4. the VERBATIM prescribed command — `--force-with-lease`, not a plain
#      push — behaves the same way. Without a value, `--force-with-lease`
#      protects the destination against its remote-tracking ref, and a branch
#      absent from the remote has none, so "can the prescribed command create
#      it?" is a genuinely separate question from 1/2.
#   5. the refspec EXTRACTED FROM the SKILL.md recovery bullet, pushed with the
#      prescribed flag, actually creates the branch — the bridge that stops the
#      file assertions below from degrading into the grep gate.
#
# and only then asserts the SKILL.md prescribes the form git accepts, both in
# aggregate and — anchored to its own bullet, so the aggregate cannot stand in
# for it — in the recovery step.
#
# Needs nothing but `git`, so it must never skip on any runner that can run the
# repo's own tooling — it is listed in scripts/required-to-run-tests.txt.

set -uo pipefail

# Neutralize inherited git context (#1745): an exported GIT_DIR overrides
# `git -C`, so without this the sandbox ops below could reach the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="${SCRIPT_DIR}/../../SKILL.md"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

# Setup steps are not assertions: a failure here means the test never ran, and
# must say so instead of surfacing as a confusing assertion mismatch. This file
# is in scripts/required-to-run-tests.txt (it may never skip), so a runner that
# cannot build the sandbox has to fail loudly and specifically.
setup() { # setup <description> <cmd> [args...]
    local desc="$1"
    shift
    "$@" || {
        printf 'FAIL: setup step failed (%s): %s\n' "$desc" "$*" >&2
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Part 1 — EXECUTE git and pin the real refspec behaviour
# ---------------------------------------------------------------------------

# An empty $sandbox would make `git -C ""` act on the CWD — the real shared
# checkout (#1692). Guard before any git op touches it.
sandbox="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
[ -n "$sandbox" ] && [ -d "$sandbox" ] || { echo "FAIL: bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT

# Neutralize the operator's own git config: a global `commit.gpgsign`,
# `core.hooksPath`, or `url.*.insteadOf` would otherwise break the sandbox
# setup on a perfectly healthy runner.
: > "$sandbox/gitconfig" || { echo "FAIL: cannot write sandbox gitconfig" >&2; exit 1; }
export GIT_CONFIG_GLOBAL="$sandbox/gitconfig"
export GIT_CONFIG_SYSTEM="$sandbox/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

# `-c` covers git versions predating GIT_CONFIG_GLOBAL/SYSTEM (< 2.32), where
# the exports above are silently ignored.
g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

setup "bare origin" g init --bare -q "$sandbox/origin"
setup "work clone" g init -q "$sandbox/work"
setup "remote add" g -C "$sandbox/work" remote add origin "$sandbox/origin"
setup "base commit" g -C "$sandbox/work" commit -q --allow-empty -m base
setup "rename to main" g -C "$sandbox/work" branch -M main
setup "seed origin/main" g -C "$sandbox/work" push -q origin main

setup "work commit" g -C "$sandbox/work" commit -q --allow-empty -m work
sha="$(g -C "$sandbox/work" rev-parse HEAD)" \
    || { echo "FAIL: setup step failed (rev-parse HEAD)" >&2; exit 1; }
[ -n "$sha" ] || { echo "FAIL: setup produced an empty sha" >&2; exit 1; }

# 1. Short form against a branch the remote does not have yet.
short_out="$(g -C "$sandbox/work" push origin "${sha}:feat/newbranch" 2>&1)"
short_rc=$?
check "short <sha>:<branch> refspec fails for a branch absent from the remote" \
    "nonzero" "$([ "$short_rc" -ne 0 ] && echo nonzero || echo zero)"
case "$short_out" in
    *"not a full refname"*) refname_msg=present ;;
    *) refname_msg=absent ;;
esac
check "git's rejection names the full-refname requirement" "present" "$refname_msg"
check "the branch was NOT created by the short form" "absent" \
    "$(g -C "$sandbox/origin" rev-parse --verify --quiet refs/heads/feat/newbranch >/dev/null 2>&1 && echo present || echo absent)"

# 2. Full refname in the identical situation.
g -C "$sandbox/work" push -q origin "${sha}:refs/heads/feat/newbranch" 2>/dev/null
full_rc=$?
check "full <sha>:refs/heads/<branch> refspec creates the branch" \
    "zero" "$([ "$full_rc" -eq 0 ] && echo zero || echo nonzero)"
check "remote now carries the created branch at the pushed sha" "$sha" \
    "$(g -C "$sandbox/origin" rev-parse refs/heads/feat/newbranch 2>/dev/null)"

# 3. Guard integrity — the short form is NOT universally rejected. Without
#    this, a git that refused every <sha>:<dst> refspec would satisfy
#    assertion 1 and the test would be pinning the wrong reason.
setup "second work commit" g -C "$sandbox/work" commit -q --allow-empty -m more
sha2="$(g -C "$sandbox/work" rev-parse HEAD)" \
    || { echo "FAIL: setup step failed (rev-parse HEAD, second)" >&2; exit 1; }
[ -n "$sha2" ] || { echo "FAIL: setup produced an empty sha2" >&2; exit 1; }
g -C "$sandbox/work" push -q origin "${sha2}:feat/newbranch" 2>/dev/null
existing_rc=$?
check "short <sha>:<branch> refspec still succeeds once the branch exists" \
    "zero" "$([ "$existing_rc" -eq 0 ] && echo zero || echo nonzero)"

# 4. The VERBATIM prescribed command. Assertions 1–3 run a plain `git push`;
#    the skill prescribes `--force-with-lease`, whose valueless form compares
#    the destination against its remote-tracking ref — which a branch absent
#    from the remote does not have. That it still creates the branch is a
#    separate fact about git, and the guidance depends on it.
g -C "$sandbox/work" push -q --force-with-lease origin "${sha}:feat/lease-short" 2>/dev/null
lease_short_rc=$?
check "prescribed flag does not rescue the short form (--force-with-lease, absent branch)" \
    "nonzero" "$([ "$lease_short_rc" -ne 0 ] && echo nonzero || echo zero)"

g -C "$sandbox/work" push -q --force-with-lease origin "${sha}:refs/heads/feat/lease-full" 2>/dev/null
lease_full_rc=$?
check "verbatim prescribed command succeeds for a branch absent from the remote" \
    "zero" "$([ "$lease_full_rc" -eq 0 ] && echo zero || echo nonzero)"
check "verbatim prescribed command created the branch at the pushed sha" "$sha" \
    "$(g -C "$sandbox/origin" rev-parse refs/heads/feat/lease-full 2>/dev/null)"

# ---------------------------------------------------------------------------
# Part 2 — the SKILL.md prescribes the form git accepts
# ---------------------------------------------------------------------------

if [ ! -f "$SKILL_FILE" ]; then
    echo "FAIL: SKILL.md not found at $SKILL_FILE" >&2
    exit 1
fi

# A PRESCRIBED refspec is a `git push … origin <sha-ish>:` instruction. The
# zsh word-modifier table rows also contain `$sha:` but carry no `git push`,
# so they are correctly out of scope — that table documents the mangling, it
# does not prescribe a command.
prescribed_re='git push[^`]*origin +"?(\$\{?sha\}?|<sha>):'
prescribed="$(grep -nE "$prescribed_re" "$SKILL_FILE")"
prescribed_count="$(printf '%s' "$prescribed" | grep -c . )"

# Non-vacuity: if the extraction ever stops matching, every "names refs/heads/"
# assertion below passes over an empty set and proves nothing.
check "SKILL.md still prescribes push-by-SHA refspecs (extraction non-vacuous)" \
    "yes" "$([ "$prescribed_count" -ge 3 ] && echo yes || echo "no($prescribed_count)")"

missing="$(printf '%s' "$prescribed" | grep -v 'refs/heads/' | grep -c . )"
if [ "$missing" -ne 0 ]; then
    printf 'prescribed refspecs missing refs/heads/:\n%s\n' \
        "$(printf '%s' "$prescribed" | grep -v 'refs/heads/')" >&2
fi
check "every prescribed push refspec names refs/heads/<branch>" "0" "$missing"

# The recovery path is where the branch is most likely absent remotely, so pin
# it SEPARATELY — and anchor the pin to the recovery bullet's own text. A
# whole-file grep for the recovery command is not a separate pin at all: the
# brace bullet prescribes a byte-identical command, so reverting only the
# recovery step would leave such a grep satisfied by the other occurrence.
recovery_block="$(awk '
    /^- \*\*Recovery\*\*/ { inblk = 1; print; next }
    inblk && (/^- / || /^#/ || /^$/) { exit }
    inblk { print }
' "$SKILL_FILE")"

recovery_lines="$(printf '%s\n' "$recovery_block" | grep -E "$prescribed_re")"
recovery_count="$(printf '%s' "$recovery_lines" | grep -c . )"
check "the recovery bullet still prescribes a push (anchor non-vacuous)" \
    "yes" "$([ "$recovery_count" -ge 1 ] && echo yes || echo "no($recovery_count)")"

recovery_missing="$(printf '%s' "$recovery_lines" | grep -v 'refs/heads/' | grep -c . )"
if [ "$recovery_missing" -ne 0 ]; then
    printf 'recovery bullet prescribes a refspec without refs/heads/:\n%s\n' \
        "$recovery_lines" >&2
fi
check "the auto-close recovery step uses the full refname" "0" "$recovery_missing"

# Bridge the file back to git: take the refspec the recovery bullet actually
# prescribes, substitute the placeholders it tells the reader to substitute,
# and push it with the flag it prescribes. Only the refspec is lifted from the
# file — nothing read from SKILL.md is ever eval'd as a command.
skill_refspec="$(printf '%s' "$recovery_lines" | grep -oE '(\$\{sha\}|<sha>):[^"`]+' | head -1)"
skill_refspec="${skill_refspec/'${sha}'/$sha}"
skill_refspec="${skill_refspec/'<sha>'/$sha}"
skill_refspec="${skill_refspec//<branch>/feat/as-prescribed}"
check "the recovery refspec is extractable for execution (bridge non-vacuous)" \
    "yes" "$([ "$skill_refspec" != "${skill_refspec#"$sha":}" ] && echo yes || echo "no($skill_refspec)")"

g -C "$sandbox/work" push -q --force-with-lease origin "$skill_refspec" 2>/dev/null
as_prescribed_rc=$?
check "the refspec SKILL.md prescribes creates a branch absent from the remote" \
    "$sha" "$([ "$as_prescribed_rc" -eq 0 ] && g -C "$sandbox/origin" rev-parse refs/heads/feat/as-prescribed 2>/dev/null || echo "push rc=$as_prescribed_rc")"

printf '%s\n' "test-push-refspec.sh: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
