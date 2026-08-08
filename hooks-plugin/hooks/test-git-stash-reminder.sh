#!/usr/bin/env bash
# Regression tests for git-stash-reminder.sh (+ git-stash-session-init.sh)
#
# Run: bash hooks-plugin/hooks/test-git-stash-reminder.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook contract: print {"decision":"block","reason":…} on stdout to report
# session stashes; print nothing to stay silent. Exit is always 0.
#
# Issue #2306 — a stash created 2025-03-31 was reported as "created during this
# session", twice, in a session that did zero git writes. Two linked defects:
#
#   1. The baseline was keyed by session_id ALONE but compared against whatever
#      repo the Stop-time cwd pointed at. A session that started in one repo and
#      later moved into another judged repo B's stashes against repo A's
#      baseline, so every pre-existing stash in B counted as new.
#   2. An existing-but-EMPTY baseline file passed the `[ ! -f ]` guard and then
#      matched no hash, so every stash counted as new. Defect 1 reliably
#      produced 0-byte baselines (a SessionStart cwd with no stashes), which is
#      how the two compounded.
#
# Narrowing the guard must not neuter it. Every assertion below is paired so the
# suite fails both a hook that reports too much AND a hook that has gone
# permanently silent:
#
#   FALSE POSITIVES the fix must kill
#     - cwd moved to a different repo holding a pre-existing old stash → SILENT
#     - an empty baseline file is UNKNOWN, not "every stash is new" → SILENT
#     - the pre-#2306 legacy FLAT baseline degrades to silence
#     - a stash older than SessionStart in the baseline's own repo → SILENT
#
#   TRUE POSITIVES the fix must keep
#     - a stash created after SessionStart in the baseline's own repo → REPORT
#       (and the pre-existing stash beside it is NOT named)
#     - a repo that was STASH-FREE at SessionStart, in which the session then
#       stashes → REPORT (this is the common real-world case, and it is the
#       gate on the `# <namespace>` header both writers emit: without the
#       header that baseline is 0 bytes, reads as UNKNOWN, and the stash is
#       absorbed forever)
#     - a genuine session stash in a repo entered AFTER SessionStart → REPORT
#     - a stash reached through a LINKED WORKTREE → same verdict as through the
#       main checkout (refs/stash is shared; the baseline key must be too)
#     - a SessionStart RE-FIRE (resume/compact) must not un-report a stash the
#       hook already flagged
#
# Test seams (all default to the real thing):
#   CLAUDE_STASH_BASELINE_DIR   where baselines live (hermetic sandbox here)
#   STASH_REMINDER_HOOK         path to the Stop hook under test
#   STASH_SESSION_INIT_HOOK     path to the SessionStart hook under test
# The last two exist so this suite can be pointed at a pre-fix copy of the
# hooks to prove it actually reproduces #2306 (mutation verification).
set -euo pipefail

# Neutralize any inherited git context before building sandbox repos. An
# exported GIT_DIR overrides `git -C`, which is how a test suite corrupts the
# shared checkout it runs inside (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${STASH_REMINDER_HOOK:-$HOOK_DIR/git-stash-reminder.sh}"
INIT_HOOK="${STASH_SESSION_INIT_HOOK:-$HOOK_DIR/git-stash-session-init.sh}"
PASS=0
FAIL=0

SANDBOX=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
# Guard the sandbox explicitly: an empty value would make every `git -C "$…"`
# below fall back to the CWD and re-init the real repo (issue #1692, enforced
# by scripts/check-git-sandbox-guards.sh).
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
    echo "bad sandbox dir" >&2
    exit 1
fi

# Unique per run so that pointing CLAUDE_STASH_BASELINE_DIR at the real
# /tmp/claude-stash-baselines (which a pre-fix hook uses unconditionally)
# cannot collide with, or clean up after, a live session.
SESSION_ID="test-2306-$$"
BASELINES="${CLAUDE_STASH_BASELINE_DIR:-$SANDBOX/baselines}"
export CLAUDE_STASH_BASELINE_DIR="$BASELINES"

cleanup() {
    rm -rf "$SANDBOX"
    rm -rf "${BASELINES:?}/${SESSION_ID}.d"
    rm -f "${BASELINES:?}/${SESSION_ID}"
    # Written by git-stash-session-init.sh; its path is not env-overridable.
    rm -f "/tmp/claude-test-baselines/${SESSION_ID}"
}
trap cleanup EXIT

# 2025-03-31T12:00:00Z — the stash age actually reported in #2306.
OLD_EPOCH=1743422400
# An hour ahead of now, so the age filter provably cannot be what suppresses a
# stash. Used to isolate the baseline guards from the age guard.
FUTURE_EPOCH=$(( $(date +%s) + 3600 ))

# ---- repo fixtures -------------------------------------------------------
mkrepo() { # mkrepo <dir>
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "test"
    git -C "$dir" config commit.gpgsign false
    printf 'seed\n' > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -q -m init
}

make_stash() { # make_stash <dir> <message> [epoch]
    local dir="$1" msg="$2" epoch="${3:-}"
    printf '%s\n' "$msg" > "$dir/file.txt"
    if [ -n "$epoch" ]; then
        # Git accepts a raw `@<epoch> <tz>` date, which needs no GNU/BSD
        # `date` flag juggling and is deterministic.
        GIT_AUTHOR_DATE="@$epoch +0000" GIT_COMMITTER_DATE="@$epoch +0000" \
            git -C "$dir" stash push -q -m "$msg"
    else
        git -C "$dir" stash push -q -m "$msg"
    fi
}

REPO_A="$SANDBOX/repo-a"      # the repo the session starts in
REPO_B="$SANDBOX/repo-b"      # a separate repo the cwd moves into later
REPO_C="$SANDBOX/repo-c"      # a third repo, entered while it is stash-free
REPO_A_WT="$SANDBOX/repo-a-wt" # a LINKED WORKTREE of repo A
mkrepo "$REPO_A"
mkrepo "$REPO_B"
mkrepo "$REPO_C"
git -C "$REPO_A" worktree add -q "$REPO_A_WT" -b wt
# Sanity: the whole worktree section is meaningless unless refs/stash really is
# shared. Assert the premise rather than assuming it.
make_stash "$REPO_A" "worktree premise probe"
WT_SHARED=$(git -C "$REPO_A_WT" stash list --format='%gs' 2>/dev/null | grep -c 'worktree premise probe' || true)
git -C "$REPO_A" stash clear
# REPO_B carries the #2306 stash: 16 months old, created long before any
# session, and never touched by one.
make_stash "$REPO_B" "old work from 2025" "$OLD_EPOCH"

# ---- baseline manipulation (layout-agnostic on purpose) ------------------
# These helpers touch BOTH the per-(session,repo) layout and the pre-#2306 flat
# layout, so the same suite drives a fixed hook and a pre-fix one.
reset_baselines() {
    rm -rf "${BASELINES:?}/${SESSION_ID}.d"
    rm -f "${BASELINES:?}/${SESSION_ID}"
}

empty_all_baselines() { # truncate every baseline to 0 bytes, keep the marker
    if [ -f "${BASELINES}/${SESSION_ID}" ]; then
        : > "${BASELINES}/${SESSION_ID}"
    fi
    if [ -d "${BASELINES}/${SESSION_ID}.d" ]; then
        find "${BASELINES}/${SESSION_ID}.d" -type f ! -name '.session-start' \
            -exec sh -c ': > "$1"' _ {} \;
    fi
}

# ---- harness -------------------------------------------------------------
run_init() { # run_init <cwd>
    printf '{"cwd":"%s","session_id":"%s"}' "$1" "$SESSION_ID" \
        | bash "$INIT_HOOK" >/dev/null 2>&1 || true
}

# run_stop <cwd> [stop_hook_active] → prints REPORT/SILENT, sets $LAST_REASON.
#
# NOTE: $LAST_REASON only survives when `run_stop` is called DIRECTLY. Calling
# it as "$(run_stop …)" spawns a subshell, so a later assertion on the reason
# would read a stale value from an earlier direct call — silently asserting the
# wrong thing. Reason assertions therefore call `run_stop` directly and read
# $LAST_VERDICT instead of capturing stdout.
LAST_REASON=""
LAST_VERDICT=""
run_stop() {
    local cwd="$1" active="${2:-false}" out
    out=$(printf '{"cwd":"%s","session_id":"%s","stop_hook_active":%s}' \
              "$cwd" "$SESSION_ID" "$active" \
          | bash "$HOOK" 2>/dev/null || true)
    LAST_REASON=$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)
    if printf '%s' "$out" | grep -q '"decision": *"block"'; then
        LAST_VERDICT=REPORT
    else
        LAST_VERDICT=SILENT
    fi
    echo "$LAST_VERDICT"
}

ck() { # ck <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; PASS=$((PASS + 1))
    else printf '  FAIL %s — expected %s got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); fi
}
ck_reason() { # ck_reason <desc> <substring>
    case "$LAST_REASON" in
        *"$2"*) printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)) ;;
        *) printf '  FAIL %s — reason lacked %s\n' "$1" "$2"; FAIL=$((FAIL + 1)) ;;
    esac
}
ck_reason_lacks() { # ck_reason_lacks <desc> <substring>
    case "$LAST_REASON" in
        *"$2"*) printf '  FAIL %s — reason wrongly named %s\n' "$1" "$2"; FAIL=$((FAIL + 1)) ;;
        *) printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)) ;;
    esac
}

echo "== #2306: cwd moved into a DIFFERENT repo with a pre-existing stash =="
# SessionStart cwd is a repo with no stashes at all, so its baseline is the
# degenerate one #2306 reported (nothing to record). The cwd then moves into a
# separately-cloned repo holding a 16-month-old stash.
reset_baselines
git -C "$REPO_A" stash clear
run_init "$REPO_A"
ck "first Stop in an unseen repo is silent"  SILENT "$(run_stop "$REPO_B")"
ck "and the next Stop there is silent too"   SILENT "$(run_stop "$REPO_B")"

echo "== an absent baseline and no session marker stay silent =="
reset_baselines
ck "no baseline at all → silent"                  SILENT "$(run_stop "$REPO_B")"
ck "capture-on-first-Stop keeps it silent after"  SILENT "$(run_stop "$REPO_B")"

echo "== the baseline is keyed per (session, REPO), not per session =="
# Repo A's stash is dated in the FUTURE, so the age filter provably cannot be
# what suppresses it — only repo A's own populated baseline can. If observing
# repo B rewrote a single session-wide baseline, repo A would start reporting.
reset_baselines
git -C "$REPO_A" stash clear
git -C "$REPO_B" stash clear
make_stash "$REPO_A" "repo-a pre-existing" "$FUTURE_EPOCH"
make_stash "$REPO_B" "repo-b old work" "$OLD_EPOCH"
run_init "$REPO_A"
ck "control: repo A's stash is suppressed by repo A's baseline" SILENT "$(run_stop "$REPO_A")"
ck "repo B's pre-session stash is judged against repo B"        SILENT "$(run_stop "$REPO_B")"
ck "capturing repo B leaves repo A's baseline intact"           SILENT "$(run_stop "$REPO_A")"

echo "== an EMPTY baseline file is UNKNOWN, not 'every stash is new' =="
# The stash here is dated in the FUTURE so the age filter provably cannot be
# what suppresses it — the baseline guard is the only thing under test.
reset_baselines
git -C "$REPO_A" stash clear
make_stash "$REPO_A" "future-dated pre-existing stash" "$FUTURE_EPOCH"
run_init "$REPO_A"
# Guard integrity: without this the empty-baseline assertion below could pass
# against a hook that suppresses everything unconditionally.
ck "control: a populated baseline suppresses it" SILENT "$(run_stop "$REPO_A")"
empty_all_baselines
ck "0-byte baseline → silent"                    SILENT "$(run_stop "$REPO_A")"

echo "== the pre-#2306 legacy FLAT baseline degrades to silence =="
reset_baselines
git -C "$REPO_A" stash clear
make_stash "$REPO_A" "future-dated pre-existing stash" "$FUTURE_EPOCH"
mkdir -p "$BASELINES"
: > "${BASELINES}/${SESSION_ID}"   # flat, 0 bytes — the shape observed in #2306
ck "legacy flat baseline → silent" SILENT "$(run_stop "$REPO_A")"

echo "== a stash created DURING the session is still reported =="
reset_baselines
git -C "$REPO_A" stash clear
make_stash "$REPO_A" "ancient work" "$OLD_EPOCH"
run_init "$REPO_A"
make_stash "$REPO_A" "session work"
# Called directly (not in $()) so $LAST_REASON survives for ck_reason.
run_stop "$REPO_A" >/dev/null
ck "session stash is reported"                REPORT "$LAST_VERDICT"
ck_reason       "names the session stash"     "session work"
ck_reason       "counts exactly one"          "Found 1 git stash"
ck_reason_lacks "does not name the old stash" "ancient work"

echo "== a repo that was STASH-FREE at SessionStart still reports (header gate) =="
# The commonest real-world shape, and the ONLY assertion that fails if either
# writer stops emitting the `# <namespace>` header: without it a stash-free
# repo's baseline is 0 bytes, the Stop hook reads that as UNKNOWN, and the
# session's stash is absorbed into the re-capture on every Stop, forever.
reset_baselines
git -C "$REPO_A" stash clear
run_init "$REPO_A"
make_stash "$REPO_A" "session work in a clean repo"
run_stop "$REPO_A" >/dev/null
ck "clean-at-start repo: session stash reported"     REPORT "$LAST_VERDICT"
ck_reason "names it"                                 "session work in a clean repo"
ck "and it is still reported on the next Stop"       REPORT "$(run_stop "$REPO_A")"

echo "== a genuine session stash in a repo entered AFTER SessionStart =="
# The moved-cwd case in its TRUE-positive direction. Same fixture shape as the
# #2306 case above, differing only in the stash's age — so a hook that stays
# silent for every newly-entered repo fails here while still passing #2306.
reset_baselines
git -C "$REPO_A" stash clear
git -C "$REPO_B" stash clear
run_init "$REPO_A"
make_stash "$REPO_B" "session work in repo B"
run_stop "$REPO_B" >/dev/null
ck "first Stop in a newly-entered repo reports it" REPORT "$LAST_VERDICT"
ck_reason "names the repo-B session stash"         "session work in repo B"
ck "still reported on the next Stop there"         REPORT "$(run_stop "$REPO_B")"

echo "== entering a stash-free repo establishes its bound (no marker) =="
# No SessionStart hook ran at all — the plugin was installed mid-session, so
# there is no .session-start marker and the only bound available is the moment
# the Stop hook first observed the repo. That observation must happen even when
# the repo holds NO stashes; otherwise the first stash created there is
# swallowed by the capture that finally runs.
reset_baselines
git -C "$REPO_C" stash clear
ck "stash-free repo with no marker → silent" SILENT "$(run_stop "$REPO_C")"
make_stash "$REPO_C" "work after first observation"
run_stop "$REPO_C" >/dev/null
ck "a stash created after that observation is reported" REPORT "$LAST_VERDICT"
ck_reason "names it"                                    "work after first observation"

echo "== linked worktrees share one stash namespace =="
ck "premise: refs/stash is visible from the linked worktree" 1 "$WT_SHARED"
# Suppression direction: the stash is FUTURE-dated so only repo A's baseline
# can suppress it. Reaching it through the worktree must find that SAME
# baseline — keying on `--show-toplevel` gives the worktree its own (absent)
# baseline and the stash is reported as new.
reset_baselines
git -C "$REPO_A" stash clear
make_stash "$REPO_A" "shared pre-existing" "$FUTURE_EPOCH"
run_init "$REPO_A"
ck "control: suppressed via the main checkout" SILENT "$(run_stop "$REPO_A")"
ck "suppressed via a linked worktree too"      SILENT "$(run_stop "$REPO_A_WT")"
# Reporting direction: SessionStart seen only from the worktree, stash made in
# the main checkout. Both halves must agree on the key, in both directions.
reset_baselines
git -C "$REPO_A" stash clear
run_init "$REPO_A_WT"
make_stash "$REPO_A" "worktree session work"
ck "SessionStart in the worktree, Stop in the main checkout" REPORT "$(run_stop "$REPO_A")"

echo "== a SessionStart RE-FIRE does not un-report an existing finding =="
# SessionStart fires again on resume / compact / clear. Re-stamping the marker
# or re-recording the baseline would retroactively silence a stash the hook had
# already reported — a state regression on unresolved work.
reset_baselines
git -C "$REPO_A" stash clear
git -C "$REPO_B" stash clear
run_init "$REPO_A"
make_stash "$REPO_A" "real session work"
ck "reported before any re-fire" REPORT "$(run_stop "$REPO_A")"
sleep 1   # so a re-stamped marker would provably move the bound forward
run_init "$REPO_B"
ck "still reported after a re-fire in another repo" REPORT "$(run_stop "$REPO_A")"
sleep 1
run_init "$REPO_A"
ck "still reported after a re-fire in the same repo" REPORT "$(run_stop "$REPO_A")"

echo "== a stash older than SessionStart is not reported =="
# Appears AFTER the baseline was captured, so only the age filter can catch it.
reset_baselines
git -C "$REPO_A" stash clear
run_init "$REPO_A"
make_stash "$REPO_A" "back-dated work" "$OLD_EPOCH"
ck "pre-session timestamp → silent" SILENT "$(run_stop "$REPO_A")"

echo "== unchanged guards =="
reset_baselines
git -C "$REPO_A" stash clear
run_init "$REPO_A"
make_stash "$REPO_A" "session work"
ck "stop_hook_active suppresses the block" SILENT "$(run_stop "$REPO_A" true)"
ck "non-git cwd is silent"                 SILENT "$(run_stop "$SANDBOX")"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
