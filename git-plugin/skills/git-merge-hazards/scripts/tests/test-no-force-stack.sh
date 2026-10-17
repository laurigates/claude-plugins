#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2317,SC2329  # SC2016: single-quoted literals are grep/order patterns, not expansions; SC2317 (0.10 name) and SC2329 (0.11 name): helpers are reached through yn/rc's "$@" dispatch
# test-no-force-stack.sh — semantic regression test for the no-force stacked-merge
# route in the git-merge-hazards skill (references/no-force-push-stack.md, #2826),
# and for the rollup gate in references/stacked-chain-push.md.
#
# Part 1 executes the reference's own bash blocks. The Classify block assigns the
# route. The two Case A blocks (update-branch, and the local merge) and the Case B
# block run against sandbox repositories with their placeholders bound. A reference
# that loses, reorders or weakens a block changes an outcome asserted here, so the
# assertions bind to the document rather than to a copy of the recipe.
#
#   route A  main gained nothing after the squash, the squash tree equals the
#            pre-squash tree, the child contains the pre-squash tip, and the child
#            is still the reviewed head. `merge -X ours` changes nothing here.
#   route B  every other shape. Case B merges the pre-squash tip, proves tree
#            identity, resolves the squash to the child's side per file, merges
#            main, and compares the child's own change with the reviewed one.
#
# Scenarios, each with a positive or negative control:
#   A  route A; the local Case A recipe pushes a tree equal to the reviewed tree,
#      and update-branch is never reached when the prediction shows a conflict.
#   B  main moved after the squash; the Case B recipe completes. The Case A recipe
#      refuses a merge that adds main's line, on its route guard, and with the
#      guard removed the child-tip gate refuses it too.
#   N  main edits a line the child also edited. The naive -X ours passes the
#      child-tip gate and drops main's change. Case B stops at step 3, with
#      origin/main as the merge in progress, and pushes nothing.
#   L  the base gained a commit after the child branched, and the squash carries
#      it. n is 0 and the trees match, yet the route must be B. Case A refuses on
#      its route guard, with or without a route. Without the guard the child-tip
#      gate passes and the base's line is dropped. Case B stops at step 1.
#   T  the squash carries content the base never had; Case B stops at its
#      tree-identity precondition, before it creates a worktree.
#   K  the child moved after review (a bot commit); Case B stops at step 4.
#   C  the bot removes the line '-- a/b note', which main carries and the review did not change.
#      Against origin/main that removal prints as '--- a/b note', a line a header-shaped filter
#      drops, so step 4 must stop on it and nothing may be pushed.
#   M  the base merged a non-overlapping main change after the child branched,
#      then main gained an unrelated commit. Case B completes, keeps main's line,
#      the child's line and the new line, and its change matches the reviewed one.
#      A two-dot baseline would not match.
#   R  the child reverted a base line and main gained an unrelated commit. The
#      squash merge in Case B is clean and re-adds the line, so its clean-merge gate
#      stops the route.
#   Q  main's later commit already carries the child's change: the update-branch
#      prediction is clean, but main moved, so route B and update-branch must not run.
#   D  the child edits a line the squash never touched: route A, the prediction is
#      clean, and update-branch runs through the gh stub, which emulates GitHub's
#      merge update. The three controls each break one post-update check (no
#      move, a rewrite, added content), and the chain must stop on each.
#   E  the child reverted a second file, g.txt, that the base had edited, and the squash
#      re-applies that edit cleanly beside a conflict on file.txt. With <source paths>
#      narrowed to file.txt, only Case B step 2's resolved-index gate sees g.txt, so it
#      must stop there. Without the gate the push lands and the reverted line returns.
#      With the whole-tree default, step 4 stops the same ungated run instead.
#   S  origin/main is stale, at the squash's parent, so `ahead` is 0. The containment
#      check routes it to B, and both Case A and Case B refuse before any push.
#   B2 the whole-tree default completes the scenario-B merge, so it adds no false stop.
#   F  a bot pushes to the child after the tip was read (the route's no-force property).
#      Case A's local push and Case B's push are refused as non-fast-forward, and the
#      bot commit stays reachable from the remote child. A forced push would clobber it.
#   J  the "If the push is rejected" block, executed after a refused Case B push. A bot
#      merge of an older main changes no tree, so the block accepts it, keeps the bot
#      commit and lands the push. A bot content commit changes the tree, so the block
#      stops and pushes nothing. A pin checks that no push line in any bash block of the
#      route carries --force, -f or a + refspec.
#   H  the operator's git config sets diff.external and color.ui=always. The content
#      diffs behind `reviewed` and step 4 pass --no-ext-diff --no-color, so K still stops
#      on the bot's line, E's ungated run still stops at step 4, and M still completes.
#   X  the empty-diff gates compare tree SHAs. A --quiet gate can be told "empty" by repo or
#      operator settings: a committed `ignore = all` hides a gitlink even with --no-ext-diff (SM),
#      and diff.trustExitCode (git 2.46+) reaches a --quiet diff that allows external drivers.
#      The no-quiet rule is pinned structurally: git 2.43 in the sandbox ignores trustExitCode.
#   O  the bot changes only file.txt's mode (MO), or rewrites a binary the child added (BN).
#      Neither changes a +/- content line, so only the raw listing sees them, and step 4
#      must stop on each. BP runs the binary child with no bot, so BN is not a blanket refusal.
#   W  the operator's config sets merge.ff=only, which refuses a merge that needs a merge
#      commit (FF1 is Case A, FF2 is Case B). Every merge in the route passes --no-ff, so both
#      recipes complete under that config.
#   SM the child reverts the base's submodule bump under a committed .gitmodules `ignore = all`,
#      which hides the gitlink from `git diff --quiet`. The merge re-applies the bump: Case A and
#      Case B must stop on it, with nothing pushed. A control shows the change the old gate hid.
#   SL under `-c diff.submodule=log` the bot re-points the gitlink the child bumped. The reviewed
#      baseline must name the bump as a Subproject line, and step 4 must stop.
#   EB the reviewed baseline is empty (reviewed_tip is the pre-squash tip) and step 4's diff is
#      empty too. Both sides compare equal, so step 4 must refuse; a control shows the push it stops.
#   G  the rollup gate in stacked-chain-push.md, executed on fixture sequences: two
#      equal reads pass, an extra IN_PROGRESS entry on the second read blocks, a
#      MERGED PR stops at its first read, and a gate that never settles stops at
#      its deadline. The gate's sleep is stubbed to advance SECONDS.
#
# Part 2 pins the text the recipes cannot express, each pin with a control.
#
# Every scenario runs git in a sandbox (mktemp guard; the GIT_DIR family unset,
# #1745). Needs git, jq and python3, all present on the runner, so a missing one
# fails the run instead of skipping it.

set -uo pipefail

# Neutralize inherited git context (#1745): an exported GIT_DIR overrides
# `git -C`, so without this the sandbox ops below could reach the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
export GIT_TERMINAL_PROMPT=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_DIR="$(cd "${SKILL_DIR}/../../.." && pwd)"
SKILL_FILE="${SKILL_DIR}/SKILL.md"
REF_DIR="${SKILL_DIR}/references"
NOFORCE_FILE="${REF_DIR}/no-force-push-stack.md"
GATE_FILE="${REF_DIR}/stacked-chain-push.md"
SYNC_FILE="${REF_DIR}/sync-notes.md"
FIELDS_FILE="${ROOT_DIR}/.claude/rules/gh-json-fields.md"
README_FILE="${ROOT_DIR}/git-plugin/README.md"
MANIFEST_FILE="${ROOT_DIR}/scripts/required-to-run-tests.txt"
WORKFLOW_FILE="${ROOT_DIR}/.github/workflows/test-skill-scripts.yml"

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

# yn <cmd...>: prints yes|no by exit status and never aborts the run.
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
# rc <cmd...>: prints zero|nonzero by exit status and never aborts the run.
rc() { if "$@" >/dev/null 2>&1; then echo zero; else echo nonzero; fi; }

# Setup steps are not assertions: a failure here means the test never ran, and
# must say so instead of surfacing as a confusing assertion mismatch.
setup() { # setup <description> <cmd...>
    local desc="$1"
    shift
    "$@" || { printf 'FAIL: setup step failed (%s): %s\n' "$desc" "$*" >&2; exit 1; }
}

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required by the rollup gate fixtures" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required by the body-size band check" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Sandbox
# ---------------------------------------------------------------------------

# An empty $sandbox would make `git -C ""` act on the CWD (#1692). Guard first.
sandbox="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then echo "FAIL: bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$sandbox"' EXIT

# Neutralize the operator's own git config (commit.gpgsign, hooksPath). The recipes
# run plain `git`, so the file pins the same settings the g() wrapper passes.
{ printf '[commit]\n\tgpgsign = false\n[core]\n\thooksPath = /dev/null\n'; } > "$sandbox/gitconfig" \
    || { echo "FAIL: cannot write sandbox gitconfig" >&2; exit 1; }
export GIT_CONFIG_GLOBAL="$sandbox/gitconfig"
export GIT_CONFIG_SYSTEM="$sandbox/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

g() { git -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }

# The operator's own git config can rewrite porcelain diff output. gitconfig-hostile adds the
# two settings that do: a diff.external helper (difftastic's documented setup) and
# color.ui=always. Scenario H runs recipes under it through hostile().
printf '#!/bin/sh\nprintf "external diff of %%s\\n" "$1"\n' > "$sandbox/extdiff" \
    || { echo "FAIL: cannot write the external diff helper" >&2; exit 1; }
chmod +x "$sandbox/extdiff" || { echo "FAIL: cannot mark the external diff helper executable" >&2; exit 1; }
{ cat "$sandbox/gitconfig"; printf '[diff]\n\texternal = %s\n[color]\n\tui = always\n' "$sandbox/extdiff"; } \
    > "$sandbox/gitconfig-hostile" \
    || { echo "FAIL: cannot write the hostile gitconfig" >&2; exit 1; }

# hostile <cmd...>: runs the command with the operator config above in place of the sandbox one.
hostile() {
    GIT_CONFIG_GLOBAL="$sandbox/gitconfig-hostile" GIT_CONFIG_SYSTEM="$sandbox/gitconfig-hostile" "$@"
}

# gitconfig-submodlog: the sandbox config plus diff.submodule=log, which prints a submodule change as
# the log of its commits instead of a Subproject line. Scenario SL runs the recipes under it through
# submodlog().
{ cat "$sandbox/gitconfig"; printf '[diff]\n\tsubmodule = log\n'; } > "$sandbox/gitconfig-submodlog" \
    || { echo "FAIL: cannot write the submodule-log gitconfig" >&2; exit 1; }
submodlog() {
    GIT_CONFIG_GLOBAL="$sandbox/gitconfig-submodlog" GIT_CONFIG_SYSTEM="$sandbox/gitconfig-submodlog" "$@"
}

# gitconfig-ffonly: the sandbox config plus merge.ff=only, which refuses any merge that would
# need a merge commit. Scenario W runs the recipes under it through ffonly().
{ cat "$sandbox/gitconfig"; printf '[merge]\n\tff = only\n'; } > "$sandbox/gitconfig-ffonly" \
    || { echo "FAIL: cannot write the ff-only gitconfig" >&2; exit 1; }

# ffonly <cmd...>: runs the command with the merge.ff=only config in place of the sandbox one.
ffonly() {
    GIT_CONFIG_GLOBAL="$sandbox/gitconfig-ffonly" GIT_CONFIG_SYSTEM="$sandbox/gitconfig-ffonly" "$@"
}

# write_gh_stub <file>: the gh stub, put first on PATH so no network is touched. Every
# call is logged to $GH_STUB_LOG. `pr update-branch` emulates GitHub's merge-style
# update of the child inside the sandbox origin. GH_STUB_MODE picks one deviation for
# a negative control: noop (the branch does not move), rewrite (someone else
# force-pushes an equal tree), content (the update adds a line), or merge (default).
# A --rebase update is refused, because the chain must never send one.
write_gh_stub() {
    cat > "$1" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_LOG"
[ "$1 $2" = "pr update-branch" ] || exit 0
child="$3"
for arg in "$@"; do
    if [ "$arg" = "--rebase" ]; then echo "gh stub: only the merge update is emulated" >&2; exit 1; fi
done
update_child() {
    local clone="$1" new
    case "${GH_STUB_MODE:-merge}" in
        noop) return 0 ;;
        rewrite)
            new="$(git -C "$clone" commit-tree "$(git -C "$clone" rev-parse 'HEAD^{tree}')" -m rewritten)" || return 1
            git -C "$clone" push -q -f origin "$new:refs/heads/$child"
            return ;;
    esac
    git -C "$clone" merge -q --no-edit origin/main || return 1
    if [ "${GH_STUB_MODE:-merge}" = content ]; then
        echo extra >> "$clone/file.txt" && git -C "$clone" commit -q -am "bot: extra line" || return 1
    fi
    git -C "$clone" push -q origin "HEAD:refs/heads/$child"
}
url="$(git config --get remote.origin.url)" || exit 1
tmp="$(mktemp -d)" || exit 1
[ -n "$tmp" ] && [ -d "$tmp" ] || exit 1
rc=1
if git clone -q "$url" "$tmp/clone" >/dev/null 2>&1 \
    && git -C "$tmp/clone" checkout -q -B "$child" "origin/$child" \
    && update_child "$tmp/clone"; then rc=0; fi
rm -rf "$tmp"
exit "$rc"
STUB
    chmod +x "$1"
}

GH_BIN="$sandbox/bin"
export GH_STUB_LOG="$sandbox/gh-calls"
setup "mkdir gh stub dir" mkdir -p "$GH_BIN"
setup "write gh stub" write_gh_stub "$GH_BIN/gh"

# write_lines <file> <line>... : file content, one argument per line.
write_lines() {
    local file="$1"
    shift
    printf '%s\n' "$@" > "$file"
}

# write_binary <file> <seed>: a binary file (a NUL byte, then the seed, then 0xFF), so git
# reports it as binary and prints no +/- lines for it.
write_binary() {
    printf '\000%s\377' "$2" > "$1"
}

# tree_eq <repo> <rev-a> <rev-b>: the tree-identity gate of Case B step 2.
tree_eq() {
    [ "$(g -C "$1" rev-parse "$2^{tree}")" = "$(g -C "$1" rev-parse "$3^{tree}")" ]
}

# same <a> <b>: exit 0 when the two strings are equal.
same() { [ "$1" = "$2" ]; }

# changed_lines <repo> <rev-a> <rev-b>: the content lines of file.txt between two revs
# (two-dot), the lines the indicators mark. The same flags and filter the reference's
# `reviewed` and step 4 apply, so the helper is immune to the operator's diff.external
# and color settings too.
changed_lines() {
    g -C "$1" diff --no-ext-diff --no-color -U0 --ignore-submodules=none --submodule=short --no-textconv --output-indicator-new='>' --output-indicator-old='<' "$2" "$3" -- file.txt | grep -E '^[<>]'
}

# squash_base <work>: git prints a squash notice on stderr even with -q.
squash_base() {
    g -C "$1" merge -q --squash base >/dev/null 2>&1
}

# merge_main <work>: the base merges main (a clean, non-adjacent merge in merged mode).
merge_main() {
    g -C "$1" merge -q --no-edit main >/dev/null 2>&1
}

# make_repo <dir> <mode>: origin + work clone where
#   main  = m0 (a b c)
#   base  = m0 + B1 (a B c), pushed; child = B1 + C1 (a X c), pushed
#   late  = base gains B2 (a Q c) after the child branched, so PRE_SHA is B2
#   merged = main gains M1 (a b c m), then base merges it, so PRE_SHA is that merge
#   revert = the child reverts B1 (a b c) instead of editing it
#   extra = the squash adds a line the base never had
#   distant = m0 has four lines; the base edits line 2 and the child edits line 4, so
#            the child's edit is not adjacent to anything the squash touched
#   twofile = std, plus g.txt: main has 1 2 3, the base edits it to 1 G 3, the child
#            reverts it to 1 2 3, and the squash re-applies 1 G 3 beside file.txt
#   main  = the squash of base; the base branch is then deleted remotely
# The squash is the commit a squash-merge puts on main; PRE_SHA is the base's
# pre-squash tip, which survives only as a local object once the branch is gone.
make_repo() {
    local d="$1" mode="${2:-std}" child_line=X
    local -a m0_text=(a b c) base_text=(a B c)
    [ "$mode" = revert ] && child_line=b
    local -a child_text=(a "$child_line" c)
    if [ "$mode" = distant ]; then
        m0_text=(a b c d)
        base_text=(a B c d)
        child_text=(a B c D)
    fi
    if [ "$mode" = note ]; then
        m0_text=(a b c '-- a/b note')
        base_text=(a B c '-- a/b note')
        child_text=(a X c '-- a/b note')
    fi
    setup "mkdir $d" mkdir -p "$d"
    setup "origin $d" g init --bare -q "$d/origin"
    setup "work $d" g init -q "$d/work"
    setup "remote $d" g -C "$d/work" remote add origin "$d/origin"
    write_lines "$d/work/file.txt" "${m0_text[@]}"
    setup "m0 add" g -C "$d/work" add file.txt
    if [ "$mode" = twofile ]; then
        write_lines "$d/work/g.txt" 1 2 3
        setup "m0 g add" g -C "$d/work" add g.txt
    fi
    setup "m0 commit" g -C "$d/work" commit -q -m m0
    setup "main name" g -C "$d/work" branch -M main
    setup "push main" g -C "$d/work" push -q origin main
    setup "base branch" g -C "$d/work" checkout -q -b base
    write_lines "$d/work/file.txt" "${base_text[@]}"
    setup "base add" g -C "$d/work" add file.txt
    if [ "$mode" = twofile ]; then
        write_lines "$d/work/g.txt" 1 G 3
        setup "base g add" g -C "$d/work" add g.txt
    fi
    setup "base commit" g -C "$d/work" commit -q -m base
    setup "push base" g -C "$d/work" push -q origin base
    setup "child branch" g -C "$d/work" checkout -q -b child
    write_lines "$d/work/file.txt" "${child_text[@]}"
    setup "child add" g -C "$d/work" add file.txt
    if [ "$mode" = twofile ]; then
        write_lines "$d/work/g.txt" 1 2 3
        setup "child g add" g -C "$d/work" add g.txt
    fi
    setup "child commit" g -C "$d/work" commit -q -m child
    setup "push child" g -C "$d/work" push -q origin child
    if [ "$mode" = late ]; then
        setup "back to base" g -C "$d/work" checkout -q base
        write_lines "$d/work/file.txt" a Q c
        setup "late add" g -C "$d/work" add file.txt
        setup "late commit" g -C "$d/work" commit -q -m "base: review fix"
        setup "push late base" g -C "$d/work" push -q origin base
    fi
    if [ "$mode" = merged ]; then
        setup "main first" g -C "$d/work" checkout -q main
        write_lines "$d/work/file.txt" a b c m
        setup "main add" g -C "$d/work" add file.txt
        setup "main commit" g -C "$d/work" commit -q -m "main: appended line"
        setup "push main first" g -C "$d/work" push -q origin main
        setup "base checkout" g -C "$d/work" checkout -q base
        setup "base merges main" merge_main "$d/work"
        setup "push base merged" g -C "$d/work" push -q origin base
    fi
    PRE_SHA="$(g -C "$d/work" rev-parse base)"
    setup "back to main" g -C "$d/work" checkout -q main
    setup "squash base" squash_base "$d/work"
    if [ "$mode" = extra ]; then
        write_lines "$d/work/file.txt" a B c extra
    fi
    setup "squash add" g -C "$d/work" add file.txt
    if [ "$mode" = twofile ]; then setup "squash g add" g -C "$d/work" add g.txt; fi
    setup "squash commit" g -C "$d/work" commit -q -m "squash base"
    setup "push squash" g -C "$d/work" push -q origin main
    SQUASH_SHA="$(g -C "$d/work" rev-parse main)"
    setup "drop base branch" g -C "$d/work" push -q origin --delete base
}

# make_gitlink_repo <dir> <revert|bump>: origin + work clone with a submodule pointer `sub`.
#   revert  .gitmodules sets `ignore = all` for sub, and main pins sub at GL_X. The base bumps sub
#           to GL_Y. The child reverts the bump to GL_X and touches nothing else. The squash of the
#           base carries GL_Y, so a merge of the squash into the child re-applies the bump.
#   bump    no .gitmodules. The base touches only file.txt. The child bumps sub to GL_Y, so its
#           review is the bump alone.
# GL_X, GL_Y and GL_Z are commits of the empty tree, so every gitlink names a real object. PRE_SHA
# and SQUASH_SHA are set as make_repo sets them.
make_gitlink_repo() {
    local d="$1" mode="$2" empty
    setup "mkdir $d" mkdir -p "$d"
    setup "origin $d" g init --bare -q "$d/origin"
    setup "work $d" g init -q "$d/work"
    setup "remote $d" g -C "$d/work" remote add origin "$d/origin"
    empty="$(g -C "$d/work" mktree < /dev/null)"
    GL_X="$(g -C "$d/work" commit-tree "$empty" -m sub-x)"
    GL_Y="$(g -C "$d/work" commit-tree "$empty" -m sub-y)"
    GL_Z="$(g -C "$d/work" commit-tree "$empty" -m sub-z)"
    if [ "$mode" = revert ]; then
        printf '[submodule "sub"]\n\tpath = sub\n\turl = ./nowhere\n\tignore = all\n' > "$d/work/.gitmodules"
        setup "m0 gitmodules" g -C "$d/work" add .gitmodules
    fi
    write_lines "$d/work/file.txt" a b c
    setup "m0 add" g -C "$d/work" add file.txt
    setup "m0 gitlink" g -C "$d/work" update-index --add --cacheinfo "160000,$GL_X,sub"
    setup "m0 commit" g -C "$d/work" commit -q -m m0
    setup "main name" g -C "$d/work" branch -M main
    setup "push main" g -C "$d/work" push -q origin main
    setup "base branch" g -C "$d/work" checkout -q -b base
    write_lines "$d/work/file.txt" a B c
    setup "base add" g -C "$d/work" add file.txt
    if [ "$mode" = revert ]; then
        setup "base bump" g -C "$d/work" update-index --cacheinfo "160000,$GL_Y,sub"
    fi
    setup "base commit" g -C "$d/work" commit -q -m base
    setup "push base" g -C "$d/work" push -q origin base
    setup "child branch" g -C "$d/work" checkout -q -b child
    if [ "$mode" = revert ]; then
        setup "child revert" g -C "$d/work" update-index --cacheinfo "160000,$GL_X,sub"
    else
        setup "child bump" g -C "$d/work" update-index --cacheinfo "160000,$GL_Y,sub"
    fi
    setup "child commit" g -C "$d/work" commit -q -m child
    setup "push child" g -C "$d/work" push -q origin child
    PRE_SHA="$(g -C "$d/work" rev-parse base)"
    setup "back to main" g -C "$d/work" checkout -q main
    setup "squash base" squash_base "$d/work"
    setup "squash commit" g -C "$d/work" commit -q -m "squash base"
    setup "push squash" g -C "$d/work" push -q origin main
    SQUASH_SHA="$(g -C "$d/work" rev-parse main)"
    setup "drop base branch" g -C "$d/work" push -q origin --delete base
}

# bot_push <work>: a bot commit lands on the child after review (appends a line).
bot_push() {
    local w="$1"
    setup "bot checkout" g -C "$w" checkout -q child
    write_lines "$w/file.txt" a X c e
    setup "bot add" g -C "$w" add file.txt
    setup "bot commit" g -C "$w" commit -q -m "bot: merge main"
    setup "bot push" g -C "$w" push -q origin child
    setup "bot back to main" g -C "$w" checkout -q main
}

# strip_push <work>: the bot removes the line '-- a/b note' from the child after review, and pushes.
# A removal the review never saw: the child's own change is untouched, only the note is deleted.
strip_push() {
    local w="$1"
    setup "strip checkout" g -C "$w" checkout -q child
    write_lines "$w/file.txt" a X c
    setup "strip add" g -C "$w" add file.txt
    setup "strip commit" g -C "$w" commit -q -m "bot: strips the note"
    setup "strip push" g -C "$w" push -q origin child
    setup "strip back to main" g -C "$w" checkout -q main
}

# main_gains <work> <file> <line>...: main gains one unrelated commit on <file> and pushes
# it, so the route sees a main that moved past the squash.
main_gains() {
    local w="$1" f="$2"
    shift 2
    write_lines "$w/$f" "$@"
    setup "main gains add" g -C "$w" add "$f"
    setup "main gains commit" g -C "$w" commit -q -m "main: unrelated commit"
    setup "main gains push" g -C "$w" push -q origin main
}

# merge_quiet <repo> <rev>: merge <rev>; git prints "Auto-merging" even with -q.
merge_quiet() {
    g -C "$1" merge -q --no-edit "$2" >/dev/null 2>&1
}

# bot_remote <scenario-dir> <content|merge|mode|binary|gitlink> [rev]: a bot, working from its own
# clone, pushes to the child after the recipe's tip was read. The work clone never fetches again, so
# its origin/child stays at the tip it read, as in the field. `content` commits a new file;
# `merge` merges <rev>, an older main; `mode` changes only file.txt's mode; `binary` rewrites
# blob.bin, which the child must have added; `gitlink` re-points sub to <rev>. Sets BOT_SHA to the
# commit now at the remote child.
bot_remote() {
    local d="$1" bot_mode="$2" rev="${3:-}" b="$1/bot"
    setup "bot clone" g clone -q -b main "$d/origin" "$b"
    setup "bot checkout" g -C "$b" checkout -q child
    case "$bot_mode" in
        merge)
            setup "bot merge" merge_quiet "$b" "$rev" ;;
        mode)
            setup "bot chmod" chmod +x "$b/file.txt"
            setup "bot add" g -C "$b" add file.txt
            setup "bot commit" g -C "$b" commit -q -m "bot: mode only" ;;
        binary)
            setup "bot binary" write_binary "$b/blob.bin" 9
            setup "bot add" g -C "$b" add blob.bin
            setup "bot commit" g -C "$b" commit -q -m "bot: rewrites the binary" ;;
        gitlink)
            setup "bot gitlink" g -C "$b" update-index --cacheinfo "160000,$rev,sub"
            setup "bot gitlink commit" g -C "$b" commit -q -m "bot: re-points the submodule" ;;
        *)
            write_lines "$b/botfile" bot
            setup "bot add" g -C "$b" add botfile
            setup "bot commit" g -C "$b" commit -q -m "bot: content" ;;
    esac
    setup "bot push" g -C "$b" push -q origin child
    BOT_SHA="$(g -C "$b" rev-parse HEAD)"
}

# binary_repo <dir>: make_repo's std repository, with the child adding a binary blob.bin. Sets
# BIN_PRE, BIN_SQ and BIN_REVIEWED. The work clone is left on main with origin/child fetched.
binary_repo() {
    make_repo "$1" std
    setup "binary child checkout" g -C "$1/work" checkout -q child
    setup "binary write" write_binary "$1/work/blob.bin" 1
    setup "binary add" g -C "$1/work" add blob.bin
    setup "binary commit" g -C "$1/work" commit -q -m "child: adds a binary"
    setup "binary push child" g -C "$1/work" push -q origin child
    setup "binary back to main" g -C "$1/work" checkout -q main
    setup "binary fetch" g -C "$1/work" fetch -q origin main child
    BIN_PRE="$PRE_SHA"
    BIN_SQ="$SQUASH_SHA"
    BIN_REVIEWED="$(g -C "$1/work" rev-parse origin/child)"
}

# ---------------------------------------------------------------------------
# Reading the reference's own blocks
# ---------------------------------------------------------------------------

# doc_block_of <file> <heading-regex> <n>: the nth ```bash fence under the first "## "
# heading that matches. Fences may sit under a list item, so they may be indented;
# bash ignores the leading blanks. Empty output means the fence is absent, and the
# assertions that depend on it then fail.
doc_block_of() {
    awk -v h="$2" -v n="$3" '
        /^## / { in_sec = ($0 ~ h); next }
        in_sec && /^[ \t]*```bash$/ { count++; take = (count == n); inside = 1; next }
        inside && /^[ \t]*```$/ { inside = 0; if (take) exit; next }
        inside && take { print }
    ' "$1"
}

# bind <block> <dir>: fills the placeholders the reference leaves for the reader.
# <source paths> is file.txt, or SRC_PATHS when a scenario sets it (`.` is the default).
bind() {
    local block="$1" dir="$2"
    block=${block//<dir>/$dir}
    block=${block//<child>/child}
    block=${block//<source paths>/${SRC_PATHS:-file.txt}}
    printf '%s\n' "$block"
}

# refs <pre> <squash> <tip> <reviewed_tip>: the shell variables a recipe reads.
refs() {
    printf "pre='%s'\nsquash='%s'\ntip='%s'\nreviewed_tip='%s'\n" "$@"
}

NF="$NOFORCE_FILE"
GF="$GATE_FILE"
SF="$SKILL_FILE"
SNF="$SYNC_FILE"

CLASSIFY_RAW="$(doc_block_of "$NF" '^## Classify$' 1)"
CASE_A_UPDATE_RAW="$(doc_block_of "$NF" '^## Case A' 1)"   # update-branch chain: needs gh
CASE_A_LOCAL_RAW="$(doc_block_of "$NF" '^## Case A' 2)"    # local merge in a worktree
CASE_B_RAW="$(doc_block_of "$NF" '^## Case B' 1)"
REJECT_RAW="$(doc_block_of "$NF" '^## If the push is rejected' 1)"   # the recovery after a refused push
GATE_RAW="$(doc_block_of "$GF" '^## 3[.]' 1)"              # the rollup gate

# The four empty-diff gates, as the reference writes them. They compare tree SHAs: Case A's update-branch
# check and merge, then Case B's before-merge and resolved-index gates. Pins and controls match them.
GATE_A1=$'[ "$(git rev-parse "${tip}^{tree}")" = "$(git rev-parse "${new}^{tree}")" ]'
GATE_A2=$'[ "$(git rev-parse "${tip}^{tree}")" = "$(git -C <dir> rev-parse \'HEAD^{tree}\')" ]'
GATE_B1=$'[ "$(git -C <dir> rev-parse "${before}^{tree}")" = "$(git -C <dir> rev-parse \'HEAD^{tree}\')" ]'
GATE_B2=$'[ "$(git -C <dir> write-tree)" = "$(git -C <dir> rev-parse \'HEAD^{tree}\')" ]'
# Case B step 4 refuses an empty reviewed baseline before it compares anything.
EB_GUARD='[ -z "$reviewed$reviewed_meta" ] && false'
# The flags of the raw listing (meta_of) in the reference.
META_FLAGS='diff --no-ext-diff --no-color --ignore-submodules=none --no-textconv --no-renames'

# classify_of <work> <var> <refs...>: runs Classify in <work> and prints $var.
# classify_with <raw-block> <work> <var> <refs...>: as classify_of, for a given block.
classify_with() {
    local raw="$1" work="$2" var="$3" script
    shift 3
    script="$(refs "$@")
$(bind "$raw" /unused)
printf '%s\n' \"\${$var}\""
    (cd "$work" && bash -c "$script") 2>/dev/null
}
classify_of() { classify_with "$CLASSIFY_RAW" "$@"; }

# route_of <work> <refs...>: the route the Classify recipe assigns.
route_of() { classify_of "$1" route "${@:2}"; }
# reviewed_of <work> <refs...>: the reviewed baseline the Classify recipe assigns.
reviewed_of() { classify_of "$1" reviewed "${@:2}"; }

# recipe <work> <dir> <raw-block> <refs...>: Classify, then the block, in one shell.
# The block's exit status is the recipe's.
recipe() {
    local work="$1" dir="$2" block="$3" script
    shift 3
    script="$(refs "$@")
$(bind "$CLASSIFY_RAW" "$dir")
$(bind "$block" "$dir")"
    (cd "$work" && bash -c "$script")
}

# bare <work> <dir> <raw-block> <refs...>: the block alone, so $route is unset.
bare() {
    local work="$1" dir="$2" block="$3" script
    shift 3
    script="$(refs "$@")
$(bind "$block" "$dir")"
    (cd "$work" && bash -c "$script")
}

# block_in <work> <dir> <raw-block>: the block alone, run from <work>. For blocks that read
# none of the recipe's variables, such as the rejected-push recovery.
block_in() {
    local work="$1" dir="$2" block="$3" script
    script="$(bind "$block" "$dir")"
    (cd "$work" && bash -c "$script")
}

# gh_invoked <cmd...>: exit 0 when the command reached the gh stub.
gh_invoked() {
    rm -f "$sandbox/gh-calls"
    PATH="$GH_BIN:$PATH" "$@" >/dev/null 2>&1
    [ -e "$sandbox/gh-calls" ]
}

# update_chain <work> <mode> <refs...>: the Case A update-branch chain, run against the
# gh stub in <mode>. Prints zero|nonzero. The chain's gh calls are left in gh-calls.
update_chain() {
    local work="$1" mode="$2"
    shift 2
    rm -f "$sandbox/gh-calls"
    PATH="$GH_BIN:$PATH" GH_STUB_MODE="$mode" rc recipe "$work" /unused "$CASE_A_UPDATE_RAW" "$@"
}

# The gate block polls gh. The stub answers the nth gh call with the nth fixture, and the
# last fixture repeats. gh runs inside $(...), so its count comes from the call log, not
# from a variable. sleep advances SECONDS by ten minutes, so the block's deadline is
# reached in a few reads. sleep runs in the block's own shell, where a run of more than
# 50 reads exits 99, so a gate that lost its deadline or its escape ends the test
# instead of hanging it.
GATE_STUB='FX=("$@"); total=${#FX[@]}
gh() {
    echo x >> "$GATE_CALL_LOG"
    local i
    i=$(wc -l < "$GATE_CALL_LOG" | tr -d " ")
    [ "$i" -gt "$total" ] && i=$total
    printf "%s" "${FX[$((i - 1))]}"
}
sleep() {
    SECONDS=$((SECONDS + 600))
    [ "$(wc -l < "$GATE_CALL_LOG" | tr -d " ")" -gt 50 ] && exit 99
}'

# gate_run <fixture>...: runs the rollup gate's bash block with the stub above. Exit 0
# when the gate passes. The pushed SHA is GATE_SHA and the PR is 7.
GATE_SHA=1111111111111111111111111111111111111111
OLD_SHA=2222222222222222222222222222222222222222
gate_run() {
    local script
    script="$GATE_STUB"$'\n'"n=7"$'\n'"sha='$GATE_SHA'"$'\n'"$GATE_RAW"
    : > "$sandbox/gate-calls"
    GATE_CALL_LOG="$sandbox/gate-calls" bash -c "$script" gate "$@" >/dev/null 2>&1
}
# gate_calls: how many gh reads the last gate_run made.
gate_calls() { wc -l < "$sandbox/gate-calls" | tr -d ' '; }
# bounded_calls: yes when the last gate_run made one to five reads.
bounded_calls() {
    local c
    c="$(gate_calls)"
    if [ "$c" -ge 1 ] && [ "$c" -le 5 ]; then echo yes; else echo no; fi
}

# fixture <head-sha> <rollup-json>: a `gh pr view --json state,headRefOid,statusCheckRollup`
# payload for an OPEN PR. fixture_in <state> <head-sha> <rollup-json> takes the state too.
fixture_in() { printf '{"state":"%s","headRefOid":"%s","statusCheckRollup":%s}' "$1" "$2" "$3"; }
fixture() { fixture_in OPEN "$1" "$2"; }

E_OK='[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"e2e","status":"COMPLETED","conclusion":"SKIPPED"},{"name":"docs","status":"COMPLETED","conclusion":"NEUTRAL"}]'
E_EMPTY='[]'
E_RUNNING='[{"name":"lint","status":"IN_PROGRESS","conclusion":null}]'
E_FAILED='[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]'
E_STALE='[{"name":"lint","status":"IN_PROGRESS","conclusion":"SUCCESS"}]'
E_LEGACY_OK='[{"context":"ci/legacy","state":"SUCCESS"}]'
E_LEGACY_PENDING='[{"context":"ci/legacy","state":"PENDING"}]'
# E_OK with one more entry still registering, and a passing rollup with a different count.
E_OK_PLUS='[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"e2e","status":"COMPLETED","conclusion":"SKIPPED"},{"name":"docs","status":"COMPLETED","conclusion":"NEUTRAL"},{"name":"lint-2","status":"IN_PROGRESS","conclusion":null}]'
E_OK_TWO='[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"e2e","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"docs","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"lint-2","status":"COMPLETED","conclusion":"SUCCESS"}]'

# ---------------------------------------------------------------------------
# Part 1 — execute the reference's own recipes
# ---------------------------------------------------------------------------

check "reference: the Classify, Case A (both), Case B, rejected-push and gate recipes are present" yes \
    "$(yn test -n "$CLASSIFY_RAW" -a -n "$CASE_A_UPDATE_RAW" -a -n "$CASE_A_LOCAL_RAW" -a -n "$CASE_B_RAW" -a -n "$REJECT_RAW" -a -n "$GATE_RAW")"
check "control: the gh stub records a direct call" yes "$(yn gh_invoked "$GH_BIN/gh" pr view child)"

# A: main gained nothing after the squash, and the child holds the base's tip.
make_repo "$sandbox/a" std
A_W="$sandbox/a/work"
setup "fetch A" g -C "$A_W" fetch -q origin main child
A_PRE="$PRE_SHA"
A_SQ="$SQUASH_SHA"
A_TIP="$(g -C "$A_W" rev-parse origin/child)"
check "A: route is A" A "$(route_of "$A_W" "$A_PRE" "$A_SQ" "$A_TIP" "$A_TIP")"
check "A: update-branch is never reached when the prediction shows a conflict" no \
    "$(yn gh_invoked recipe "$A_W" "$sandbox/a/upd" "$CASE_A_UPDATE_RAW" "$A_PRE" "$A_SQ" "$A_TIP" "$A_TIP")"
check "A: the local Case A recipe completes" zero \
    "$(rc recipe "$A_W" "$sandbox/a/wt" "$CASE_A_LOCAL_RAW" "$A_PRE" "$A_SQ" "$A_TIP" "$A_TIP")"
A_NEW="$(g -C "$sandbox/a/wt" rev-parse HEAD)"
check "A: the remote child sits at the verified merge" "$A_NEW" \
    "$(g -C "$sandbox/a/origin" rev-parse refs/heads/child)"
check "A: the pushed tree is byte-identical to the reviewed tree" yes \
    "$(yn tree_eq "$A_W" "$A_NEW" "$A_TIP")"

# B: main moved after the squash. Route B. Case A refuses on its guard, and the
# child-tip gate refuses too when the guard is removed; Case B completes.
make_repo "$sandbox/b" std
B_W="$sandbox/b/work"
write_lines "$B_W/file.txt" a B c d
setup "B main edit" g -C "$B_W" add file.txt
setup "B main commit" g -C "$B_W" commit -q -m "main: unrelated append"
setup "B push main" g -C "$B_W" push -q origin main
setup "fetch B" g -C "$B_W" fetch -q origin main child
B_PRE="$PRE_SHA"
B_SQ="$SQUASH_SHA"
B_TIP="$(g -C "$B_W" rev-parse origin/child)"
check "B: route is B (main moved after the squash)" B \
    "$(route_of "$B_W" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
check "B control: the Case A recipe refuses a merge that adds main's line" nonzero \
    "$(rc recipe "$B_W" "$sandbox/b/wt-a" "$CASE_A_LOCAL_RAW" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
B_UNGUARDED="${CASE_A_LOCAL_RAW/'[ "$route" = A ]'/true}"
check "B control: with the guard removed, the child-tip gate alone refuses that merge" nonzero \
    "$(rc recipe "$B_W" "$sandbox/b/wt-g" "$B_UNGUARDED" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
check "B control: the child is unchanged after the refused Case A pushes" "$B_TIP" \
    "$(g -C "$sandbox/b/origin" rev-parse refs/heads/child)"
check "B control: update-branch is never reached" no \
    "$(yn gh_invoked recipe "$B_W" "$sandbox/b/upd" "$CASE_A_UPDATE_RAW" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
check "B: the Case B recipe completes" zero \
    "$(rc recipe "$B_W" "$sandbox/b/wt" "$CASE_B_RAW" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
B_NEW="$(g -C "$sandbox/b/wt" rev-parse HEAD)"
check "B: the remote child sits at the Case B merge" "$B_NEW" \
    "$(g -C "$sandbox/b/origin" rev-parse refs/heads/child)"
B_CONTENT="$(g -C "$sandbox/b/wt" show HEAD:file.txt)"
check "B: main's new line survives the merge" yes "$(yn grep -qxF -- d <<<"$B_CONTENT")"
check "B control: a line main never wrote is absent" no "$(yn grep -qxF -- zz <<<"$B_CONTENT")"
B_REVIEWED="$(reviewed_of "$B_W" "$B_PRE" "$B_SQ" "$B_TIP" "$B_TIP")"
check "B control: the reviewed change is non-empty" yes "$(yn test -n "$B_REVIEWED")"
check "B: the pushed change against main equals the reviewed change" "$B_REVIEWED" \
    "$(changed_lines "$sandbox/b/wt" origin/main HEAD)"

# N (negative control): main edits the line the child also edited.
make_repo "$sandbox/n" std
N_W="$sandbox/n/work"
write_lines "$N_W/file.txt" a Q c
setup "N main edit" g -C "$N_W" add file.txt
setup "N main commit" g -C "$N_W" commit -q -m "main: edits the line the child edited"
setup "N push main" g -C "$N_W" push -q origin main
setup "fetch N" g -C "$N_W" fetch -q origin main child
N_PRE="$PRE_SHA"
N_SQ="$SQUASH_SHA"
N_TIP="$(g -C "$N_W" rev-parse origin/child)"
check "N: route is B (main moved, and edited a line the child edited)" B \
    "$(route_of "$N_W" "$N_PRE" "$N_SQ" "$N_TIP" "$N_TIP")"
setup "worktree N naive" g -C "$N_W" worktree add -q --detach "$sandbox/n/naive" "$N_TIP"
check "N control: the naive -X ours merge completes" zero \
    "$(rc g -C "$sandbox/n/naive" merge -q --no-edit -X ours origin/main)"
check "N control: the child-tip gate PASSES on the naive merge" zero \
    "$(rc g -C "$sandbox/n/naive" diff --quiet "$N_TIP" HEAD)"
check "N control: main's Q is silently dropped by -X ours" no \
    "$(yn grep -qxF -- Q <<<"$(g -C "$sandbox/n/naive" show HEAD:file.txt)")"
check "N: the Case B recipe stops at step 3" nonzero \
    "$(rc recipe "$N_W" "$sandbox/n/b" "$CASE_B_RAW" "$N_PRE" "$N_SQ" "$N_TIP" "$N_TIP")"
check "N: origin/main is the merge in progress (MERGE_HEAD), so step 3 stopped it" \
    "$(g -C "$N_W" rev-parse origin/main)" "$(g -C "$sandbox/n/b" rev-parse MERGE_HEAD)"
check "N: nothing is pushed" "$N_TIP" "$(g -C "$sandbox/n/origin" rev-parse refs/heads/child)"

# L (negative control): the base gained a commit after the child branched, and the
# squash carries it. n is 0 and the trees match, so only ancestry tells B from A.
make_repo "$sandbox/l" late
L_W="$sandbox/l/work"
setup "fetch L" g -C "$L_W" fetch -q origin main child
L_PRE="$PRE_SHA"
L_SQ="$SQUASH_SHA"
L_TIP="$(g -C "$L_W" rev-parse origin/child)"
L_COUNT="$(g -C "$L_W" rev-list --count "${L_SQ}..origin/main")"
check "L: the shape is n=0 with equal trees" "0 yes" \
    "$L_COUNT $(yn tree_eq "$L_W" "$L_SQ" "$L_PRE")"
check "L control: the child does not contain the pre-squash tip" no \
    "$(yn g -C "$L_W" merge-base --is-ancestor "$L_PRE" "$L_TIP")"
check "L: route is B, so the -X ours route is never taken" B \
    "$(route_of "$L_W" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L: the Case A recipe refuses on its route guard" nonzero \
    "$(rc recipe "$L_W" "$sandbox/l/wt-a" "$CASE_A_LOCAL_RAW" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L: the Case A recipe refuses when the route is unset" nonzero \
    "$(rc bare "$L_W" "$sandbox/l/wt-u" "$CASE_A_LOCAL_RAW" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L: update-branch is never reached" no \
    "$(yn gh_invoked recipe "$L_W" "$sandbox/l/upd" "$CASE_A_UPDATE_RAW" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L: the Case B recipe stops at step 1 (the base tip conflicts)" nonzero \
    "$(rc recipe "$L_W" "$sandbox/l/b" "$CASE_B_RAW" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L: the conflict is on the base tip (MERGE_HEAD)" "$L_PRE" \
    "$(g -C "$sandbox/l/b" rev-parse MERGE_HEAD)"
check "L: nothing is pushed" "$L_TIP" "$(g -C "$sandbox/l/origin" rev-parse refs/heads/child)"
# Control, run last because it pushes: without the guard, the child-tip gate passes
# and the base's Q is dropped. This is the silent loss the guard refuses.
L_UNGUARDED="${CASE_A_LOCAL_RAW/'[ "$route" = A ]'/true}"
check "L control: without the guard, the child-tip gate passes and the push goes through" zero \
    "$(rc recipe "$L_W" "$sandbox/l/wt-x" "$L_UNGUARDED" "$L_PRE" "$L_SQ" "$L_TIP" "$L_TIP")"
check "L control: without the guard, the base's Q is silently dropped" no \
    "$(yn grep -qxF -- Q <<<"$(g -C "$sandbox/l/origin" show 'refs/heads/child:file.txt')")"

# T (negative control): the squash carries content the base never had. n is 0, but
# the trees differ, so tree identity must route to B and stop Case B at its
# tree-identity precondition, before the worktree exists.
make_repo "$sandbox/t" extra
T_W="$sandbox/t/work"
setup "fetch T" g -C "$T_W" fetch -q origin main child
T_PRE="$PRE_SHA"
T_SQ="$SQUASH_SHA"
T_TIP="$(g -C "$T_W" rev-parse origin/child)"
check "T: route is B (the squash tree differs from the pre-squash tree)" B \
    "$(route_of "$T_W" "$T_PRE" "$T_SQ" "$T_TIP" "$T_TIP")"
check "T control: the tree-identity gate sees the difference" no \
    "$(yn tree_eq "$T_W" "$T_SQ" "$T_PRE")"
check "T: the Case B recipe stops at its tree-identity precondition" nonzero \
    "$(rc recipe "$T_W" "$sandbox/t/wt" "$CASE_B_RAW" "$T_PRE" "$T_SQ" "$T_TIP" "$T_TIP")"
check "T: no worktree is created, so a stop leaves nothing to clean up" no \
    "$(yn test -e "$sandbox/t/wt")"
check "T: git lists no linked worktree" 1 \
    "$(g -C "$T_W" worktree list --porcelain | grep -c '^worktree ')"
check "T: nothing is pushed" "$T_TIP" "$(g -C "$sandbox/t/origin" rev-parse refs/heads/child)"

# K (negative control): the child moved after review, as a bot commit does. The
# reviewed head is recorded before the bot pushes.
make_repo "$sandbox/k" std
K_W="$sandbox/k/work"
setup "fetch K" g -C "$K_W" fetch -q origin main child
K_PRE="$PRE_SHA"
K_SQ="$SQUASH_SHA"
K_REVIEWED="$(g -C "$K_W" rev-parse origin/child)"
bot_push "$K_W"
setup "fetch K after the bot" g -C "$K_W" fetch -q origin main child
K_TIP="$(g -C "$K_W" rev-parse origin/child)"
check "K: route is B (the child moved after review)" B \
    "$(route_of "$K_W" "$K_PRE" "$K_SQ" "$K_TIP" "$K_REVIEWED")"
check "K: the Case B recipe stops at step 4 (the bot's line is outside the review)" nonzero \
    "$(rc recipe "$K_W" "$sandbox/k/wt" "$CASE_B_RAW" "$K_PRE" "$K_SQ" "$K_TIP" "$K_REVIEWED")"
check "K: nothing is pushed" "$K_TIP" "$(g -C "$sandbox/k/origin" rev-parse refs/heads/child)"

# C (negative control): the bot removes the line '-- a/b note', which main carries and the review did
# not change. Against origin/main the removal prints as `--- a/b note`, which a header-shaped filter
# reads as a file header and drops. The content comparison then passes, and the push would land the
# bot's unreviewed deletion. Step 4 must stop on it, and nothing may be pushed.
make_repo "$sandbox/c" note
C_W="$sandbox/c/work"
setup "fetch C" g -C "$C_W" fetch -q origin main child
C_PRE="$PRE_SHA"
C_SQ="$SQUASH_SHA"
C_REVIEWED="$(g -C "$C_W" rev-parse origin/child)"
strip_push "$C_W"
setup "fetch C after the bot" g -C "$C_W" fetch -q origin main child
C_TIP="$(g -C "$C_W" rev-parse origin/child)"
check "C: route is B (the child moved after review)" B \
    "$(route_of "$C_W" "$C_PRE" "$C_SQ" "$C_TIP" "$C_REVIEWED")"
check "C control: the bot's removal is a '---' line in the unfiltered diff against main" yes \
    "$(yn grep -qxF -- '--- a/b note' <<<"$(g -C "$C_W" diff --no-ext-diff --no-color -U0 "$C_SQ" "$C_TIP" -- file.txt)")"
check "C control: the review did not change the note line" no \
    "$(yn grep -qF -- 'note' <<<"$(reviewed_of "$C_W" "$C_PRE" "$C_SQ" "$C_TIP" "$C_REVIEWED")")"
check "C: the Case B recipe stops at step 4 (the bot's removal is outside the review)" nonzero \
    "$(rc recipe "$C_W" "$sandbox/c/wt" "$CASE_B_RAW" "$C_PRE" "$C_SQ" "$C_TIP" "$C_REVIEWED")"
check "C: the recipe reached step 4 (the squash merge is the worktree's second parent)" "$C_SQ" \
    "$(g -C "$sandbox/c/wt" rev-parse -q --verify 'HEAD^2' || true)"
check "C: the step-4 content lines carry the bot's removal" yes \
    "$(yn grep -qF -- '-- a/b note' <<<"$(changed_lines "$sandbox/c/wt" origin/main HEAD)")"
check "C: nothing is pushed" "$C_TIP" "$(g -C "$sandbox/c/origin" rev-parse refs/heads/child)"

# O (negative control): the bot changes only file.txt's mode, so the child's +/- content lines
# still match the reviewed change. Step 4 must stop on the mode alone. The control shows the
# content lines really are blind to it.
make_repo "$sandbox/o" std
O_W="$sandbox/o/work"
setup "fetch O" g -C "$O_W" fetch -q origin main child
O_PRE="$PRE_SHA"
O_SQ="$SQUASH_SHA"
O_REVIEWED="$(g -C "$O_W" rev-parse origin/child)"
bot_remote "$sandbox/o" mode
setup "fetch O after the bot" g -C "$O_W" fetch -q origin main child
O_TIP="$(g -C "$O_W" rev-parse origin/child)"
check "O control: the bot's commit has no +/- content line, so the content comparison is blind to it" "" \
    "$(g -C "$O_W" diff --no-ext-diff --no-color -U0 --output-indicator-new='>' --output-indicator-old='<' "$O_REVIEWED" "$O_TIP" -- file.txt | grep -E '^[<>]' || true)"
check "O: route is B (the child moved after review)" B \
    "$(route_of "$O_W" "$O_PRE" "$O_SQ" "$O_TIP" "$O_REVIEWED")"
check "O: the Case B recipe stops at step 4 (the mode change is outside the reviewed change)" nonzero \
    "$(rc recipe "$O_W" "$sandbox/o/wt" "$CASE_B_RAW" "$O_PRE" "$O_SQ" "$O_TIP" "$O_REVIEWED")"
check "O: nothing is pushed" "$O_TIP" "$(g -C "$sandbox/o/origin" rev-parse refs/heads/child)"
check "O: the stop comes after the step-3 merge, with no merge in progress" no \
    "$(yn g -C "$sandbox/o/wt" rev-parse -q --verify MERGE_HEAD)"
# Control, run last because it pushes: without the raw listing, the content lines alone let the
# mode change through. So the raw comparison is the check that stops O, not some other gate.
O_UNRAW="${CASE_B_RAW/'[ "$(meta_of <dir> origin/main HEAD -- <source paths>)" = "$reviewed_meta" ]'/true}"
check "O control: without the raw listing, the content lines alone push the mode change" zero \
    "$(rc recipe "$O_W" "$sandbox/o/wt-u" "$O_UNRAW" "$O_PRE" "$O_SQ" "$O_TIP" "$O_REVIEWED")"

# BN (negative control) and BP (its positive control). The child adds a binary, and the bot then
# rewrites it. A binary prints no +/- line, so the content comparison passes it; the raw
# listing compares the binary's blob. The source paths are the whole tree, so blob.bin is in
# the review. BP runs the same recipe on the same child with no bot push and must complete.
binary_repo "$sandbox/bn"
BN_W="$sandbox/bn/work"
BN_PRE="$BIN_PRE"
BN_SQ="$BIN_SQ"
BN_REVIEWED="$BIN_REVIEWED"
bot_remote "$sandbox/bn" binary
setup "fetch BN after the bot" g -C "$BN_W" fetch -q origin main child
BN_TIP="$(g -C "$BN_W" rev-parse origin/child)"
check "BN control: the bot's commit changes the binary, and the content lines show nothing" "" \
    "$(g -C "$BN_W" diff --no-ext-diff --no-color -U0 --output-indicator-new='>' --output-indicator-old='<' "$BN_REVIEWED" "$BN_TIP" -- blob.bin | grep -E '^[<>]' || true)"
check "BN: route is B (the child moved after review)" B \
    "$(SRC_PATHS=.; route_of "$BN_W" "$BN_PRE" "$BN_SQ" "$BN_TIP" "$BN_REVIEWED")"
check "BN: the Case B recipe stops at step 4 (the bot rewrote a binary the review covers)" nonzero \
    "$(SRC_PATHS=.; rc recipe "$BN_W" "$sandbox/bn/wt" "$CASE_B_RAW" "$BN_PRE" "$BN_SQ" "$BN_TIP" "$BN_REVIEWED")"
check "BN: nothing is pushed" "$BN_TIP" "$(g -C "$sandbox/bn/origin" rev-parse refs/heads/child)"
check "BN: the stop comes after the step-3 merge, with no merge in progress" no \
    "$(yn g -C "$sandbox/bn/wt" rev-parse -q --verify MERGE_HEAD)"
# Control, run last because it pushes: without the raw listing, the content lines pass the
# rewritten binary, so the blob comparison is the check that stops BN.
BN_UNRAW="${CASE_B_RAW/'[ "$(meta_of <dir> origin/main HEAD -- <source paths>)" = "$reviewed_meta" ]'/true}"
check "BN control: without the raw listing, the content lines alone push the rewritten binary" zero \
    "$(SRC_PATHS=.; rc recipe "$BN_W" "$sandbox/bn/wt-u" "$BN_UNRAW" "$BN_PRE" "$BN_SQ" "$BN_TIP" "$BN_REVIEWED")"

binary_repo "$sandbox/bp"
BP_W="$sandbox/bp/work"
BP_PRE="$BIN_PRE"
BP_SQ="$BIN_SQ"
BP_REVIEWED="$BIN_REVIEWED"
check "BP: the Case B recipe completes on the binary child with no bot push" zero \
    "$(SRC_PATHS=.; rc recipe "$BP_W" "$sandbox/bp/wt" "$CASE_B_RAW" "$BP_PRE" "$BP_SQ" "$BP_REVIEWED" "$BP_REVIEWED")"
check "BP: the pushed child carries the binary, so the raw comparison let the clean run through" yes \
    "$(yn g -C "$sandbox/bp/origin" cat-file -e 'refs/heads/child:blob.bin')"

# M: the base merged a non-overlapping main change after the child branched, then
# main gained an unrelated commit. The final diff must be measured against the
# merge-base, as GitHub's PR diff is; a two-dot baseline would carry the reversal.
make_repo "$sandbox/m" merged
M_W="$sandbox/m/work"
write_lines "$M_W/file.txt" a B c m u
setup "M main edit" g -C "$M_W" add file.txt
setup "M main commit" g -C "$M_W" commit -q -m "main: unrelated append"
setup "M push main" g -C "$M_W" push -q origin main
setup "fetch M" g -C "$M_W" fetch -q origin main child
M_PRE="$PRE_SHA"
M_SQ="$SQUASH_SHA"
M_TIP="$(g -C "$M_W" rev-parse origin/child)"
check "M: route is B (main moved after the squash)" B \
    "$(route_of "$M_W" "$M_PRE" "$M_SQ" "$M_TIP" "$M_TIP")"
check "M: the Case B recipe completes" zero \
    "$(rc recipe "$M_W" "$sandbox/m/wt" "$CASE_B_RAW" "$M_PRE" "$M_SQ" "$M_TIP" "$M_TIP")"
M_NEW="$(g -C "$sandbox/m/wt" rev-parse HEAD)"
check "M: the remote child sits at the Case B merge" "$M_NEW" \
    "$(g -C "$sandbox/m/origin" rev-parse refs/heads/child)"
check "M: the pushed file keeps main's appended line, the child's line and main's new line" \
    "$(printf '%s\n' a X c m u)" "$(g -C "$sandbox/m/wt" show HEAD:file.txt)"
M_REVIEWED="$(reviewed_of "$M_W" "$M_PRE" "$M_SQ" "$M_TIP" "$M_TIP")"
check "M: the reviewed change is the child's own line swap" "$(printf '%s\n' '<B' '>X')" "$M_REVIEWED"
check "M: the pushed change against main equals the reviewed change" "$M_REVIEWED" \
    "$(changed_lines "$sandbox/m/wt" origin/main HEAD)"
check "M control: a two-dot baseline would not match the final change" no \
    "$(yn same "$(changed_lines "$M_W" "$M_PRE" "$M_TIP")" "$(changed_lines "$sandbox/m/wt" origin/main HEAD)")"

# R (negative control): the child reverted a base line, and main gained an unrelated
# commit. Case B's squash merge is clean and re-adds the base line. Its clean-merge
# gate must refuse, because the merge must add nothing.
make_repo "$sandbox/r" revert
R_W="$sandbox/r/work"
write_lines "$R_W/file.txt" a B c u
setup "R main edit" g -C "$R_W" add file.txt
setup "R main commit" g -C "$R_W" commit -q -m "main: unrelated append"
setup "R push main" g -C "$R_W" push -q origin main
setup "fetch R" g -C "$R_W" fetch -q origin main child
R_PRE="$PRE_SHA"
R_SQ="$SQUASH_SHA"
R_TIP="$(g -C "$R_W" rev-parse origin/child)"
check "R: route is B (main moved after the squash)" B \
    "$(route_of "$R_W" "$R_PRE" "$R_SQ" "$R_TIP" "$R_TIP")"
check "R control: the child lacks the base's line" no \
    "$(yn grep -qxF -- B <<<"$(g -C "$R_W" show "$R_TIP:file.txt")")"
check "R: the Case B recipe stops at its clean-merge gate" nonzero \
    "$(rc recipe "$R_W" "$sandbox/r/wt" "$CASE_B_RAW" "$R_PRE" "$R_SQ" "$R_TIP" "$R_TIP")"
check "R: the squash merge did complete, so HEAD now carries the squash tree" yes \
    "$(yn tree_eq "$sandbox/r/wt" HEAD "$R_SQ")"
check "R: the recipe stopped at step 2, before the base merge (HEAD's second parent is the squash)" \
    "$R_SQ" "$(g -C "$sandbox/r/wt" rev-parse 'HEAD^2')"
check "R: nothing is pushed" "$R_TIP" "$(g -C "$sandbox/r/origin" rev-parse refs/heads/child)"

# Q: main's later commit already carries the child's change, so the update-branch
# prediction is clean (the merge adds nothing), but main moved past the squash: route
# B. Only the route guard keeps update-branch from running here.
make_repo "$sandbox/q" std
Q_W="$sandbox/q/work"
write_lines "$Q_W/file.txt" a X c
setup "Q main edit" g -C "$Q_W" add file.txt
setup "Q main commit" g -C "$Q_W" commit -q -m "main: carries the child's line"
setup "Q push main" g -C "$Q_W" push -q origin main
setup "fetch Q" g -C "$Q_W" fetch -q origin main child
Q_PRE="$PRE_SHA"
Q_SQ="$SQUASH_SHA"
Q_TIP="$(g -C "$Q_W" rev-parse origin/child)"
check "Q: route is B (main moved past the squash)" B \
    "$(route_of "$Q_W" "$Q_PRE" "$Q_SQ" "$Q_TIP" "$Q_TIP")"
check "Q control: the update-branch prediction is clean (the merge would add nothing)" yes \
    "$(yn same "$(g -C "$Q_W" merge-tree --write-tree "$Q_TIP" origin/main)" "$(g -C "$Q_W" rev-parse "${Q_TIP}^{tree}")")"
check "Q: update-branch is never reached on route B" no \
    "$(yn gh_invoked recipe "$Q_W" "$sandbox/q/upd" "$CASE_A_UPDATE_RAW" "$Q_PRE" "$Q_SQ" "$Q_TIP" "$Q_TIP")"
check "Q: the Case A local recipe refuses on route B" nonzero \
    "$(rc recipe "$Q_W" "$sandbox/q/wt" "$CASE_A_LOCAL_RAW" "$Q_PRE" "$Q_SQ" "$Q_TIP" "$Q_TIP")"

# D: the child edits a line the squash never touched. Route A, and the prediction is
# clean, so update-branch runs and its post-update checks pass. The three controls each
# break one post-update check on a fresh repository, and the chain must stop on each.
make_repo "$sandbox/d" distant
D_W="$sandbox/d/work"
setup "fetch D" g -C "$D_W" fetch -q origin main child
D_PRE="$PRE_SHA"
D_SQ="$SQUASH_SHA"
D_TIP="$(g -C "$D_W" rev-parse origin/child)"
check "D: route is A (the child edits a line the squash did not touch)" A \
    "$(route_of "$D_W" "$D_PRE" "$D_SQ" "$D_TIP" "$D_TIP")"
check "D control: the local prediction is clean and equals the child's own tree" yes \
    "$(yn same "$(g -C "$D_W" merge-tree --write-tree "$D_TIP" origin/main)" "$(g -C "$D_W" rev-parse "${D_TIP}^{tree}")")"
check "D: the update-branch chain completes" zero \
    "$(update_chain "$D_W" merge "$D_PRE" "$D_SQ" "$D_TIP" "$D_TIP")"
check "D: the chain's one gh call is the merge update, with no --rebase" "pr update-branch child" \
    "$(cat "$sandbox/gh-calls")"
D_NEW="$(g -C "$sandbox/d/origin" rev-parse refs/heads/child)"
check "D: the child moved past the reviewed tip" no "$(yn same "$D_NEW" "$D_TIP")"
check "D: the new child head descends from the reviewed tip" yes \
    "$(yn g -C "$sandbox/d/origin" merge-base --is-ancestor "$D_TIP" "$D_NEW")"
check "D: the pushed tree is byte-identical to the reviewed tree" yes \
    "$(yn tree_eq "$sandbox/d/origin" "$D_NEW" "$D_TIP")"

make_repo "$sandbox/d2" distant
D2_W="$sandbox/d2/work"
setup "fetch D2" g -C "$D2_W" fetch -q origin main child
D2_PRE="$PRE_SHA"
D2_SQ="$SQUASH_SHA"
D2_TIP="$(g -C "$D2_W" rev-parse origin/child)"
check "D control: an update that leaves the branch where it was stops the chain" nonzero \
    "$(update_chain "$D2_W" noop "$D2_PRE" "$D2_SQ" "$D2_TIP" "$D2_TIP")"
check "D control: the branch is unchanged after that stop" "$D2_TIP" \
    "$(g -C "$sandbox/d2/origin" rev-parse refs/heads/child)"

make_repo "$sandbox/d3" distant
D3_W="$sandbox/d3/work"
setup "fetch D3" g -C "$D3_W" fetch -q origin main child
D3_PRE="$PRE_SHA"
D3_SQ="$SQUASH_SHA"
D3_TIP="$(g -C "$D3_W" rev-parse origin/child)"
check "D control: a branch rewritten by someone else (not a fast-forward) stops the chain" nonzero \
    "$(update_chain "$D3_W" rewrite "$D3_PRE" "$D3_SQ" "$D3_TIP" "$D3_TIP")"

make_repo "$sandbox/d4" distant
D4_W="$sandbox/d4/work"
setup "fetch D4" g -C "$D4_W" fetch -q origin main child
D4_PRE="$PRE_SHA"
D4_SQ="$SQUASH_SHA"
D4_TIP="$(g -C "$D4_W" rev-parse origin/child)"
check "D control: an update that adds content stops the chain" nonzero \
    "$(update_chain "$D4_W" content "$D4_PRE" "$D4_SQ" "$D4_TIP" "$D4_TIP")"

# E (negative control): the child reverted g.txt, which the base had edited, and the
# squash re-applies that edit cleanly beside a conflict on file.txt. With <source paths>
# narrowed to file.txt, only Case B step 2's resolved-index gate sees g.txt.
make_repo "$sandbox/e" twofile
E_W="$sandbox/e/work"
main_gains "$E_W" h.txt unrelated
setup "fetch E" g -C "$E_W" fetch -q origin main child
E_PRE="$PRE_SHA"
E_SQ="$SQUASH_SHA"
E_TIP="$(g -C "$E_W" rev-parse origin/child)"
check "E: route is B (main moved past the squash)" B \
    "$(route_of "$E_W" "$E_PRE" "$E_SQ" "$E_TIP" "$E_TIP")"
check "E: the Case B recipe stops (the conflict on file.txt leaves g.txt staged for the gate)" nonzero \
    "$(rc recipe "$E_W" "$sandbox/e/wt" "$CASE_B_RAW" "$E_PRE" "$E_SQ" "$E_TIP" "$E_TIP")"
check "E: MERGE_HEAD is the squash, so the stop is at step 2" "$E_SQ" \
    "$(g -C "$sandbox/e/wt" rev-parse MERGE_HEAD)"
check "E: the index holds the squash's re-add of g.txt, which the gate refuses" "$(printf '%s\n' 1 G 3)" \
    "$(g -C "$sandbox/e/wt" show :g.txt)"
check "E: nothing is pushed" "$E_TIP" "$(g -C "$sandbox/e/origin" rev-parse refs/heads/child)"
check "E: the remote child keeps its reverted g.txt" "$(printf '%s\n' 1 2 3)" \
    "$(g -C "$sandbox/e/origin" show 'refs/heads/child:g.txt')"

# E controls. The same run with the step-2 gate removed pushes, and the child takes back
# the base's g.txt line that its review removed. With <source paths> bound to `.`, the
# reviewed change covers g.txt too, so step 4 stops the ungated run.
E2_UNGATED="${CASE_B_RAW/"$GATE_B2"/true}"
make_repo "$sandbox/e2" twofile
E2_W="$sandbox/e2/work"
main_gains "$E2_W" h.txt unrelated
setup "fetch E2" g -C "$E2_W" fetch -q origin main child
E2_PRE="$PRE_SHA"
E2_SQ="$SQUASH_SHA"
E2_TIP="$(g -C "$E2_W" rev-parse origin/child)"
check "E control: with the step-2 gate removed, the same run pushes" zero \
    "$(rc recipe "$E2_W" "$sandbox/e2/wt" "$E2_UNGATED" "$E2_PRE" "$E2_SQ" "$E2_TIP" "$E2_TIP")"
check "E control: the pushed child carries the base's g.txt line back" "$(printf '%s\n' 1 G 3)" \
    "$(g -C "$sandbox/e2/origin" show 'refs/heads/child:g.txt')"

make_repo "$sandbox/e3" twofile
E3_W="$sandbox/e3/work"
main_gains "$E3_W" h.txt unrelated
setup "fetch E3" g -C "$E3_W" fetch -q origin main child
E3_PRE="$PRE_SHA"
E3_SQ="$SQUASH_SHA"
E3_TIP="$(g -C "$E3_W" rev-parse origin/child)"
check "E control: the whole-tree default stops the ungated run at step 4" nonzero \
    "$(SRC_PATHS=.; rc recipe "$E3_W" "$sandbox/e3/wt" "$E2_UNGATED" "$E3_PRE" "$E3_SQ" "$E3_TIP" "$E3_TIP")"
check "E control: nothing is pushed under the whole-tree default" "$E3_TIP" \
    "$(g -C "$sandbox/e3/origin" rev-parse refs/heads/child)"

# B2: the whole-tree default on the scenario-B merge. It completes, so the default adds no
# false stop on a clean route B.
make_repo "$sandbox/b2" std
B2_W="$sandbox/b2/work"
main_gains "$B2_W" file.txt a B c d
setup "fetch B2" g -C "$B2_W" fetch -q origin main child
B2_PRE="$PRE_SHA"
B2_SQ="$SQUASH_SHA"
B2_TIP="$(g -C "$B2_W" rev-parse origin/child)"
check "B2: the Case B recipe completes under the whole-tree default" zero \
    "$(SRC_PATHS=.; rc recipe "$B2_W" "$sandbox/b2/wt" "$CASE_B_RAW" "$B2_PRE" "$B2_SQ" "$B2_TIP" "$B2_TIP")"
check "B2: the remote child sits at the Case B merge" \
    "$(g -C "$sandbox/b2/wt" rev-parse HEAD)" "$(g -C "$sandbox/b2/origin" rev-parse refs/heads/child)"

# S (negative control): origin/main is stale. It sits at the squash's parent, so the squash
# is not in it and `ahead` is 0. Without the containment check the route would be A; with
# it the route is B, and both Case A and Case B refuse before any push.
make_repo "$sandbox/s" std
S_W="$sandbox/s/work"
setup "fetch S" g -C "$S_W" fetch -q origin main child
S_PRE="$PRE_SHA"
S_SQ="$SQUASH_SHA"
S_TIP="$(g -C "$S_W" rev-parse origin/child)"
setup "S stale main" g -C "$S_W" update-ref refs/remotes/origin/main "${S_SQ}^"
S_OLD_CLASSIFY="${CLASSIFY_RAW/'git merge-base --is-ancestor "$squash" origin/main'/true}"
check "S: origin/main does not contain the squash" no \
    "$(yn g -C "$S_W" merge-base --is-ancestor "$S_SQ" origin/main)"
check "S control: without the containment check the stale main classifies as A" A \
    "$(classify_with "$S_OLD_CLASSIFY" "$S_W" route "$S_PRE" "$S_SQ" "$S_TIP" "$S_TIP")"
check "S: the route is B" B "$(route_of "$S_W" "$S_PRE" "$S_SQ" "$S_TIP" "$S_TIP")"
check "S: the Case A local recipe refuses on its route guard" nonzero \
    "$(rc recipe "$S_W" "$sandbox/s/wt-a" "$CASE_A_LOCAL_RAW" "$S_PRE" "$S_SQ" "$S_TIP" "$S_TIP")"
check "S: the Case B recipe refuses" nonzero \
    "$(rc recipe "$S_W" "$sandbox/s/wt" "$CASE_B_RAW" "$S_PRE" "$S_SQ" "$S_TIP" "$S_TIP")"
check "S: the Case B refusal comes before its first merge (no worktree is created)" no \
    "$(yn test -e "$sandbox/s/wt")"
check "S: nothing is pushed" "$S_TIP" "$(g -C "$sandbox/s/origin" rev-parse refs/heads/child)"

# F (negative control for a forced push): a bot pushes to the child after the tip was read.
# Scenarios A and B are the positive controls: the same recipes complete on the same
# repositories when no bot pushes. Here each push must be refused as non-fast-forward and
# the bot commit must stay reachable from the remote child. A forced push exits zero and
# clobbers it. The worktree checks prove each recipe reached its push, so the refusal is
# the push's and not an earlier gate's.
make_repo "$sandbox/fa" std
FA_W="$sandbox/fa/work"
setup "fetch FA" g -C "$FA_W" fetch -q origin main child
FA_PRE="$PRE_SHA"
FA_SQ="$SQUASH_SHA"
FA_TIP="$(g -C "$FA_W" rev-parse origin/child)"
check "F: route is A before the bot pushes" A "$(route_of "$FA_W" "$FA_PRE" "$FA_SQ" "$FA_TIP" "$FA_TIP")"
bot_remote "$sandbox/fa" content
check "F control: the bot commit is the remote child, and it is not the tip the recipe read" no \
    "$(yn same "$BOT_SHA" "$FA_TIP")"
check "F: the Case A local push is refused after a bot push" nonzero \
    "$(rc recipe "$FA_W" "$sandbox/fa/wt" "$CASE_A_LOCAL_RAW" "$FA_PRE" "$FA_SQ" "$FA_TIP" "$FA_TIP")"
check "F: the Case A recipe reached its push (the worktree holds the verified merge of the squash)" "$FA_SQ" \
    "$(g -C "$sandbox/fa/wt" rev-parse 'HEAD^2')"
check "F: the remote child is still the bot commit after Case A" "$BOT_SHA" \
    "$(g -C "$sandbox/fa/origin" rev-parse refs/heads/child)"

make_repo "$sandbox/fb" std
FB_W="$sandbox/fb/work"
main_gains "$FB_W" file.txt a B c d
setup "fetch FB" g -C "$FB_W" fetch -q origin main child
FB_PRE="$PRE_SHA"
FB_SQ="$SQUASH_SHA"
FB_TIP="$(g -C "$FB_W" rev-parse origin/child)"
check "F: route is B before the bot pushes" B "$(route_of "$FB_W" "$FB_PRE" "$FB_SQ" "$FB_TIP" "$FB_TIP")"
bot_remote "$sandbox/fb" content
check "F: the Case B push is refused after a bot push" nonzero \
    "$(rc recipe "$FB_W" "$sandbox/fb/wt" "$CASE_B_RAW" "$FB_PRE" "$FB_SQ" "$FB_TIP" "$FB_TIP")"
check "F: the Case B recipe reached its push (the worktree holds main's line)" yes \
    "$(yn grep -qxF -- d <<<"$(g -C "$sandbox/fb/wt" show HEAD:file.txt)")"
check "F: the remote child is still the bot commit after Case B" "$BOT_SHA" \
    "$(g -C "$sandbox/fb/origin" rev-parse refs/heads/child)"
check "F: the bot's file is still in the remote child" yes \
    "$(yn g -C "$sandbox/fb/origin" cat-file -e 'refs/heads/child:botfile')"

# J: the "If the push is rejected" block, run after a refused Case B push. The base merged
# main, the child branched earlier, and main gained an unrelated commit (scenario M's shape).
# A bot merge of the older main adds no content, so the block merges it, keeps the tree and
# lands the push on top of the bot commit. A bot content commit changes the tree, so the
# block must stop before it pushes.
make_repo "$sandbox/j" merged
J_W="$sandbox/j/work"
main_gains "$J_W" file.txt a B c m u
setup "fetch J" g -C "$J_W" fetch -q origin main child
J_PRE="$PRE_SHA"
J_SQ="$SQUASH_SHA"
J_TIP="$(g -C "$J_W" rev-parse origin/child)"
J_OLDER_MAIN="$(g -C "$J_W" rev-list -1 --grep='main: appended line' main)"
check "J control: the older main is a commit the child does not contain" no \
    "$(yn g -C "$J_W" merge-base --is-ancestor "$J_OLDER_MAIN" "$J_TIP")"
bot_remote "$sandbox/j" merge "$J_OLDER_MAIN"
check "J: the Case B push is refused after the bot merge" nonzero \
    "$(rc recipe "$J_W" "$sandbox/j/wt" "$CASE_B_RAW" "$J_PRE" "$J_SQ" "$J_TIP" "$J_TIP")"
J_BUILT_TREE="$(g -C "$sandbox/j/wt" rev-parse 'HEAD^{tree}')"
check "J control: the bot merge added no content to the tree Case B built" yes \
    "$(yn same "$(g -C "$sandbox/j/origin" show "${BOT_SHA}:file.txt")" "$(printf '%s\n' a X c m)")"
check "J: the rejected-push block accepts a merge that changes no tree" zero \
    "$(rc block_in "$J_W" "$sandbox/j/wt" "$REJECT_RAW")"
J_NOW="$(g -C "$sandbox/j/origin" rev-parse refs/heads/child)"
check "J: the bot commit stays reachable from the remote child" yes \
    "$(yn g -C "$sandbox/j/origin" merge-base --is-ancestor "$BOT_SHA" "$J_NOW")"
check "J: the push landed (the remote child moved past the bot commit)" no "$(yn same "$J_NOW" "$BOT_SHA")"
check "J: the pushed tree is the tree Case B built" "$J_BUILT_TREE" \
    "$(g -C "$sandbox/j/origin" rev-parse "${J_NOW}^{tree}")"

make_repo "$sandbox/j2" merged
J2_W="$sandbox/j2/work"
main_gains "$J2_W" file.txt a B c m u
setup "fetch J2" g -C "$J2_W" fetch -q origin main child
J2_PRE="$PRE_SHA"
J2_SQ="$SQUASH_SHA"
J2_TIP="$(g -C "$J2_W" rev-parse origin/child)"
bot_remote "$sandbox/j2" content
check "J: the Case B push is refused after a bot content commit" nonzero \
    "$(rc recipe "$J2_W" "$sandbox/j2/wt" "$CASE_B_RAW" "$J2_PRE" "$J2_SQ" "$J2_TIP" "$J2_TIP")"
check "J: the rejected-push block stops when the bot changed content" nonzero \
    "$(rc block_in "$J2_W" "$sandbox/j2/wt" "$REJECT_RAW")"
check "J control: the merge did bring the bot's file into the worktree, so the tree check stopped it" yes \
    "$(yn test -e "$sandbox/j2/wt/botfile")"
check "J: nothing is pushed by the block (the remote child is still the bot commit)" "$BOT_SHA" \
    "$(g -C "$sandbox/j2/origin" rev-parse refs/heads/child)"

# H: the operator's git config sets diff.external and color.ui=always. An unflagged porcelain
# diff then has no +/- lines, so a comparison built on it compares two empty strings. K, M and
# E's whole-tree run repeat under that config: K must still stop on the bot's line, M must
# still complete, and E's ungated run must still stop at step 4.
make_repo "$sandbox/hk" std
HK_W="$sandbox/hk/work"
setup "fetch HK" g -C "$HK_W" fetch -q origin main child
HK_PRE="$PRE_SHA"
HK_SQ="$SQUASH_SHA"
HK_REVIEWED="$(g -C "$HK_W" rev-parse origin/child)"
bot_push "$HK_W"
setup "fetch HK after the bot" g -C "$HK_W" fetch -q origin main child
HK_TIP="$(g -C "$HK_W" rev-parse origin/child)"
check "H control: under the hostile config an unflagged content diff has no +/- lines" "" \
    "$(hostile g -C "$HK_W" diff -U0 "$HK_REVIEWED" "$HK_TIP" -- file.txt | grep -E '^[-+]' || true)"
check "H control: the flagged content diff still shows the bot's line" ">e" \
    "$(hostile g -C "$HK_W" diff --no-ext-diff --no-color -U0 --output-indicator-new='>' --output-indicator-old='<' "$HK_REVIEWED" "$HK_TIP" -- file.txt \
        | grep -E '^[<>]')"
check "H: the reviewed baseline is the child's own line swap under the hostile config" "$(printf '%s\n' '<B' '>X')" \
    "$(hostile reviewed_of "$HK_W" "$HK_PRE" "$HK_SQ" "$HK_TIP" "$HK_REVIEWED")"
check "H: K's Case B recipe still stops at step 4 under the hostile config" nonzero \
    "$(hostile rc recipe "$HK_W" "$sandbox/hk/wt" "$CASE_B_RAW" "$HK_PRE" "$HK_SQ" "$HK_TIP" "$HK_REVIEWED")"
check "H: K's bot line is not pushed" "$HK_TIP" "$(g -C "$sandbox/hk/origin" rev-parse refs/heads/child)"

make_repo "$sandbox/hm" merged
HM_W="$sandbox/hm/work"
main_gains "$HM_W" file.txt a B c m u
setup "fetch HM" g -C "$HM_W" fetch -q origin main child
HM_PRE="$PRE_SHA"
HM_SQ="$SQUASH_SHA"
HM_TIP="$(g -C "$HM_W" rev-parse origin/child)"
check "H: M's Case B recipe still completes under the hostile config" zero \
    "$(hostile rc recipe "$HM_W" "$sandbox/hm/wt" "$CASE_B_RAW" "$HM_PRE" "$HM_SQ" "$HM_TIP" "$HM_TIP")"
check "H: M's remote child sits at the Case B merge" \
    "$(g -C "$sandbox/hm/wt" rev-parse HEAD)" "$(g -C "$sandbox/hm/origin" rev-parse refs/heads/child)"

make_repo "$sandbox/he" twofile
HE_W="$sandbox/he/work"
main_gains "$HE_W" h.txt unrelated
setup "fetch HE" g -C "$HE_W" fetch -q origin main child
HE_PRE="$PRE_SHA"
HE_SQ="$SQUASH_SHA"
HE_TIP="$(g -C "$HE_W" rev-parse origin/child)"
check "H: E's ungated whole-tree run still stops at step 4 under the hostile config" nonzero \
    "$(SRC_PATHS=.; hostile rc recipe "$HE_W" "$sandbox/he/wt" "$E2_UNGATED" "$HE_PRE" "$HE_SQ" "$HE_TIP" "$HE_TIP")"
check "H: E's nothing is pushed" "$HE_TIP" "$(g -C "$sandbox/he/origin" rev-parse refs/heads/child)"

make_repo "$sandbox/hmo" std
HMO_W="$sandbox/hmo/work"
setup "fetch HMO" g -C "$HMO_W" fetch -q origin main child
HMO_PRE="$PRE_SHA"
HMO_SQ="$SQUASH_SHA"
HMO_REVIEWED="$(g -C "$HMO_W" rev-parse origin/child)"
bot_remote "$sandbox/hmo" mode
setup "fetch HMO after the bot" g -C "$HMO_W" fetch -q origin main child
HMO_TIP="$(g -C "$HMO_W" rev-parse origin/child)"
check "H: the raw comparison still stops O's mode-only bot change under the hostile config" nonzero \
    "$(hostile rc recipe "$HMO_W" "$sandbox/hmo/wt" "$CASE_B_RAW" "$HMO_PRE" "$HMO_SQ" "$HMO_TIP" "$HMO_REVIEWED")"

# W: an operator's merge.ff=only refuses any merge that needs a merge commit. The route's merges
# pass --no-ff, so the same Case A and Case B recipes complete under that config.
make_repo "$sandbox/ff1" std
FF1_W="$sandbox/ff1/work"
setup "fetch FF1" g -C "$FF1_W" fetch -q origin main child
FF1_PRE="$PRE_SHA"
FF1_SQ="$SQUASH_SHA"
FF1_TIP="$(g -C "$FF1_W" rev-parse origin/child)"
setup "FF1 control worktree" g -C "$FF1_W" worktree add -q --detach "$sandbox/ff1/ctl" "$FF1_TIP"
check "FF1 control: under merge.ff=only a plain merge of main that needs a merge commit is refused" nonzero \
    "$(ffonly rc g -C "$sandbox/ff1/ctl" merge --no-edit origin/main)"
check "FF1: route is A" A "$(route_of "$FF1_W" "$FF1_PRE" "$FF1_SQ" "$FF1_TIP" "$FF1_TIP")"
check "FF1: the Case A local recipe completes under merge.ff=only" zero \
    "$(ffonly rc recipe "$FF1_W" "$sandbox/ff1/wt" "$CASE_A_LOCAL_RAW" "$FF1_PRE" "$FF1_SQ" "$FF1_TIP" "$FF1_TIP")"
check "FF1: the pushed tree is the reviewed tree" yes \
    "$(yn tree_eq "$FF1_W" "$(g -C "$sandbox/ff1/wt" rev-parse HEAD)" "$FF1_TIP")"
check "FF1: the Case A merge is a two-parent merge whose second parent is the squash" "$FF1_SQ" \
    "$(g -C "$sandbox/ff1/wt" rev-parse -q --verify 'HEAD^2' || true)"
check "FF1: the remote child moved off the tip the recipe read" no \
    "$(yn same "$(g -C "$sandbox/ff1/origin" rev-parse refs/heads/child)" "$FF1_TIP")"
# Control: without --no-ff, merge.ff=only refuses the merge. HEAD then stays at the tip, so the tree
# check above passes that run too. The two checks above are what tell a refused merge from a pushed one.
FF1_REFUSED="${CASE_A_LOCAL_RAW/'merge --no-ff --no-edit -X ours origin/main'/'merge --no-edit -X ours origin/main'}"
check "FF1 control: without --no-ff the route's merge is refused and the recipe stops" nonzero \
    "$(ffonly rc recipe "$FF1_W" "$sandbox/ff1/wt-r" "$FF1_REFUSED" "$FF1_PRE" "$FF1_SQ" "$FF1_TIP" "$FF1_TIP")"
check "FF1 control: the refused run's tree equals the reviewed tree, so the tree check alone passes it" yes \
    "$(yn tree_eq "$FF1_W" "$(g -C "$sandbox/ff1/wt-r" rev-parse HEAD)" "$FF1_TIP")"
check "FF1 control: the merge-commit check fails on the refused run" no \
    "$(yn same "$(g -C "$sandbox/ff1/wt-r" rev-parse -q --verify 'HEAD^2' || true)" "$FF1_SQ")"

make_repo "$sandbox/ff2" merged
FF2_W="$sandbox/ff2/work"
main_gains "$FF2_W" file.txt a B c m u
setup "fetch FF2" g -C "$FF2_W" fetch -q origin main child
FF2_PRE="$PRE_SHA"
FF2_SQ="$SQUASH_SHA"
FF2_TIP="$(g -C "$FF2_W" rev-parse origin/child)"
check "FF2: route is B (main moved past the squash)" B \
    "$(route_of "$FF2_W" "$FF2_PRE" "$FF2_SQ" "$FF2_TIP" "$FF2_TIP")"
check "FF2: the Case B recipe completes under merge.ff=only" zero \
    "$(ffonly rc recipe "$FF2_W" "$sandbox/ff2/wt" "$CASE_B_RAW" "$FF2_PRE" "$FF2_SQ" "$FF2_TIP" "$FF2_TIP")"
check "FF2: the remote child sits at the Case B merge" \
    "$(g -C "$sandbox/ff2/wt" rev-parse HEAD)" "$(g -C "$sandbox/ff2/origin" rev-parse refs/heads/child)"

# SM (negative control): the child reverts the base's submodule bump. The committed .gitmodules sets
# `ignore = all`, so `git diff --quiet` never sees the gitlink, and the old gates passed a merge that
# re-applies the bump. Case A and Case B must stop on it, with nothing pushed.
make_gitlink_repo "$sandbox/sm" revert
SM_W="$sandbox/sm/work"
setup "fetch SM" g -C "$SM_W" fetch -q origin main child
SM_PRE="$PRE_SHA"
SM_SQ="$SQUASH_SHA"
SM_TIP="$(g -C "$SM_W" rev-parse origin/child)"
check "SM: route is A (main has nothing after the squash, and the squash equals the base)" A \
    "$(route_of "$SM_W" "$SM_PRE" "$SM_SQ" "$SM_TIP" "$SM_TIP")"
setup "SM control worktree" g -C "$SM_W" worktree add -q --detach "$sandbox/sm/ctl" "$SM_TIP"
setup "SM control merge" merge_quiet "$sandbox/sm/ctl" origin/main
check "SM control: the merge re-applies the bump, so its tree differs from the child tip" no \
    "$(yn tree_eq "$sandbox/sm/ctl" HEAD "$SM_TIP")"
check "SM control: under ignore = all the old diff gate passes the re-applied bump" zero \
    "$(rc g -C "$sandbox/sm/ctl" diff --no-ext-diff --quiet "$SM_TIP" HEAD)"
check "SM: the Case A recipe stops on the re-applied bump" nonzero \
    "$(rc recipe "$SM_W" "$sandbox/sm/wt-a" "$CASE_A_LOCAL_RAW" "$SM_PRE" "$SM_SQ" "$SM_TIP" "$SM_TIP")"
check "SM: the Case A merge was built (the worktree's second parent is the squash)" "$SM_SQ" \
    "$(g -C "$sandbox/sm/wt-a" rev-parse -q --verify 'HEAD^2' || true)"
check "SM: update-branch is never reached on the re-applied bump" no \
    "$(yn gh_invoked recipe "$SM_W" "$sandbox/sm/upd" "$CASE_A_UPDATE_RAW" "$SM_PRE" "$SM_SQ" "$SM_TIP" "$SM_TIP")"
check "SM: nothing is pushed by Case A" "$SM_TIP" "$(g -C "$sandbox/sm/origin" rev-parse refs/heads/child)"
# Case B runs in its own copy of the scenario, so a push that Case A made cannot stand in for it.
make_gitlink_repo "$sandbox/smb" revert
SMB_W="$sandbox/smb/work"
main_gains "$SMB_W" file.txt a B c d
setup "fetch SMB" g -C "$SMB_W" fetch -q origin main child
SMB_PRE="$PRE_SHA"
SMB_SQ="$SQUASH_SHA"
SMB_TIP="$(g -C "$SMB_W" rev-parse origin/child)"
check "SM: route is B once main has moved past the squash" B \
    "$(SRC_PATHS=.; route_of "$SMB_W" "$SMB_PRE" "$SMB_SQ" "$SMB_TIP" "$SMB_TIP")"
check "SM: the Case B recipe stops on the re-applied bump" nonzero \
    "$(SRC_PATHS=.; rc recipe "$SMB_W" "$sandbox/smb/wt" "$CASE_B_RAW" "$SMB_PRE" "$SMB_SQ" "$SMB_TIP" "$SMB_TIP")"
check "SM: nothing is pushed by Case B" "$SMB_TIP" "$(g -C "$sandbox/smb/origin" rev-parse refs/heads/child)"

# SL (negative control): under `-c diff.submodule=log` a submodule change prints as a commit log,
# which the content filter drops. The bot re-points the gitlink the child bumped. The old step 4 then
# compared two empty content lines and two matching raw listings, and pushed. The reviewed baseline
# must name the bump as a Subproject line under that config, and step 4 must stop.
make_gitlink_repo "$sandbox/sl" bump
SL_W="$sandbox/sl/work"
main_gains "$SL_W" file.txt a B c d
setup "fetch SL" g -C "$SL_W" fetch -q origin main child
SL_PRE="$PRE_SHA"
SL_SQ="$SQUASH_SHA"
SL_REV="$(g -C "$SL_W" rev-parse origin/child)"
bot_remote "$sandbox/sl" gitlink "$GL_Z"
setup "fetch SL after the bot" g -C "$SL_W" fetch -q origin child
SL_TIP="$(g -C "$SL_W" rev-parse origin/child)"
check "SL: route is B (the child moved after review, and main moved past the squash)" B \
    "$(SRC_PATHS=.; route_of "$SL_W" "$SL_PRE" "$SL_SQ" "$SL_TIP" "$SL_REV")"
check "SL control: under diff.submodule=log the reviewed baseline names the bump as a Subproject line" yes \
    "$(yn grep -qxF -- ">Subproject commit $GL_Y" <<<"$(SRC_PATHS=.; submodlog reviewed_of "$SL_W" "$SL_PRE" "$SL_SQ" "$SL_TIP" "$SL_REV")")"
check "SL: the Case B recipe stops at step 4 (the bot re-pointed the bumped gitlink)" nonzero \
    "$(SRC_PATHS=.; submodlog rc recipe "$SL_W" "$sandbox/sl/wt" "$CASE_B_RAW" "$SL_PRE" "$SL_SQ" "$SL_TIP" "$SL_REV")"
check "SL: the stop comes after the step-3 merge, with no merge in progress" no \
    "$(yn g -C "$sandbox/sl/wt" rev-parse -q --verify MERGE_HEAD)"
check "SL: nothing is pushed" "$SL_TIP" "$(g -C "$sandbox/sl/origin" rev-parse refs/heads/child)"

# EB (negative control): the reviewed head is the pre-squash tip, so the review covers nothing and the
# reviewed baseline is empty. Step 4's diff against main is empty as well. Both sides compare equal, so
# the old step 4 passed and pushed a merge that changes nothing. Step 4 must refuse the empty baseline.
make_repo "$sandbox/eb" std
EB_W="$sandbox/eb/work"
main_gains "$EB_W" file.txt a B c d
setup "fetch EB" g -C "$EB_W" fetch -q origin main child
EB_PRE="$PRE_SHA"
EB_SQ="$SQUASH_SHA"
setup "EB child moved to the pre-squash tip" g -C "$sandbox/eb/origin" update-ref refs/heads/child "$EB_PRE"
check "EB: the reviewed baseline is empty" "" \
    "$(classify_of "$EB_W" reviewed "$EB_PRE" "$EB_SQ" "$EB_PRE" "$EB_PRE")"
check "EB: the reviewed listing is empty too" "" \
    "$(classify_of "$EB_W" reviewed_meta "$EB_PRE" "$EB_SQ" "$EB_PRE" "$EB_PRE")"
check "EB: the Case B recipe stops at the empty-baseline guard" nonzero \
    "$(rc recipe "$EB_W" "$sandbox/eb/wt" "$CASE_B_RAW" "$EB_PRE" "$EB_SQ" "$EB_PRE" "$EB_PRE")"
check "EB: the stop comes after the step-3 merge, with no merge in progress" no \
    "$(yn g -C "$sandbox/eb/wt" rev-parse -q --verify MERGE_HEAD)"
check "EB: nothing is pushed (the remote child stays at the pre-squash tip)" "$EB_PRE" \
    "$(g -C "$sandbox/eb/origin" rev-parse refs/heads/child)"
check "EB: Classify refuses an empty pre (no route is assigned from a missing ref)" "" \
    "$(route_of "$EB_W" "" "$EB_SQ" "$EB_PRE" "$EB_PRE")"
# The control runs in its own repository, so the refusal above cannot leave its remote child moved.
make_repo "$sandbox/eb2" std
EB2_W="$sandbox/eb2/work"
main_gains "$EB2_W" file.txt a B c d
setup "fetch EB2" g -C "$EB2_W" fetch -q origin main child
EB2_PRE="$PRE_SHA"
EB2_SQ="$SQUASH_SHA"
setup "EB2 child moved to the pre-squash tip" g -C "$sandbox/eb2/origin" update-ref refs/heads/child "$EB2_PRE"
EB_UNGUARDED="${CASE_B_RAW/"$EB_GUARD"/true}"
check "EB control: without the guard, the same run pushes the change-free merge" zero \
    "$(rc recipe "$EB2_W" "$sandbox/eb2/wt" "$EB_UNGUARDED" "$EB2_PRE" "$EB2_SQ" "$EB2_PRE" "$EB2_PRE")"

# G: the rollup gate. The block reads the PR again after 30 seconds and passes only when
# two reads agree. Each fixture sequence exercises one rule the gate names.
check "G: a head at the pushed SHA, with every entry COMPLETED and passing, passes on two equal reads" zero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_OK")" "$(fixture "$GATE_SHA" "$E_OK")")"
check "G: a passing read followed by one with an extra IN_PROGRESS entry blocks" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_OK")" "$(fixture "$GATE_SHA" "$E_OK_PLUS")")"
check "G: a passing read followed by a passing read with another count waits for a third to agree" zero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_OK")" "$(fixture "$GATE_SHA" "$E_OK_TWO")")"
check "G: a head that is not the pushed SHA blocks (a read after a push can return the old tip)" nonzero \
    "$(rc gate_run "$(fixture "$OLD_SHA" "$E_OK")")"
check "G: an empty rollup blocks (zero entries before a second run registers)" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_EMPTY")")"
check "G: a null rollup blocks" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" null)")"
check "G: an entry still IN_PROGRESS with a null conclusion blocks" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_RUNNING")")"
check "G: a FAILURE conclusion blocks" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_FAILED")")"
check "G: a passing conclusion does not count while the status is not COMPLETED" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_STALE")")"
check "G: a legacy commit status in SUCCESS passes (it has no status field)" zero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_LEGACY_OK")")"
check "G: a legacy commit status still PENDING blocks" nonzero \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_LEGACY_PENDING")")"
check "G: an empty gh read blocks (no state, so the loop never passes)" nonzero \
    "$(rc gate_run "")"
check "G: a PR that merged while the gate waits blocks at its first read" "nonzero 1" \
    "$(rc gate_run "$(fixture_in MERGED "$GATE_SHA" "$E_OK")") $(gate_calls)"
check "G: a PR that closed while the gate waits blocks at its first read" "nonzero 1" \
    "$(rc gate_run "$(fixture_in CLOSED "$GATE_SHA" "$E_RUNNING")") $(gate_calls)"
check "G: an open PR that never settles stops at the deadline, within a few reads" "nonzero yes" \
    "$(rc gate_run "$(fixture "$GATE_SHA" "$E_RUNNING")") $(bounded_calls)"

# ---------------------------------------------------------------------------
# Part 2 — structural pins the recipes cannot express, each with a control
# ---------------------------------------------------------------------------

# has <file> <literal>: yes when the file contains the literal (a missing file is no).
has() { yn grep -qF -- "$2" "$1"; }
# lacks <file> <literal>: exit 0 only when the file exists AND lacks the literal.
lacks() { [ -f "$1" ] && ! grep -qF -- "$2" "$1"; }
# count_of <file> <literal>: how many lines contain the literal.
count_of() {
    local n
    n=$(grep -cF -- "$2" "$1" || true)
    printf '%s\n' "${n:-0}"
}
# guard_pinned <file>: exit 0 when the route guard opens at least two chains.
guard_pinned() { [ "$(count_of "$1" '[ "$route" = A ]')" -ge 2 ]; }
# pointer_free <file>: exit 0 only when the file exists and has no positional pointer.
DIRECTION_RE='(^|[^[:alpha:]])(above|below|earlier|following)([^[:alpha:]]|$)'
pointer_free() { [ -f "$1" ] && ! grep -qiE -- "$DIRECTION_RE" "$1"; }
# under_warn <file>: exit 0 when the file's characters (not bytes) are at or under 10,000.
under_warn() {
    [ "$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$1")" -le 10000 ]
}

# order_ok <file> <first-literal> <second-literal>: yes when the first literal's
# first line comes before the second's. A missing literal is no.
order_ok() {
    local first_line second_line
    first_line="$(grep -nF -m1 -- "$2" "$1" | cut -d: -f1)"
    second_line="$(grep -nF -m1 -- "$3" "$1" | cut -d: -f1)"
    if [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ]; then
        echo yes
    else
        echo no
    fi
}

# step3_plain <text>: exit 0 when the recipe's merge of origin/main takes no -X or -s. The line
# is the first `merge <args> origin/main` command; `merge-base ... origin/main` is a different
# command and the precondition line, so the pattern needs a space after `merge`.
step3_plain() {
    local line
    line="$(grep -E 'merge[[:space:]].*origin/main' <<<"$1" | head -1)"
    [ -n "$line" ] && ! grep -qE -- ' -(X|s)[ =]' <<<"$line"
}

# DIFF_FLAGS: the flags every content diff carries. The operator's diff.external and color settings can
# empty a porcelain diff's +/- lines; a committed `ignore = all` or diff.submodule=log can hide or
# reshape a gitlink change; a diff.<driver>.textconv can rewrite text. The flags name each of these.
DIFF_FLAGS='diff --no-ext-diff --no-color -U0 --ignore-submodules=none --submodule=short --no-textconv'
# diffs_flagged <file>: exit 0 when the file has at least two content diffs that carry DIFF_FLAGS, and
# no content diff without them.
diffs_flagged() {
    [ "$(count_of "$1" "$DIFF_FLAGS")" -ge 2 ] && ! grep -qF -- 'diff -U0' "$1"
}

# merges_no_ff <file>: exit 0 when the file's bash blocks hold at least five `git merge` commands
# and every one passes --no-ff, so an operator's merge.ff=only cannot refuse one. merge-base and
# merge-tree are different commands and do not count.
merges_no_ff() {
    local lines plain
    lines="$(awk '/^[ \t]*```bash$/ { inside = 1; next } /^[ \t]*```$/ { inside = 0; next } inside { print }' "$1" \
        | grep -E '(^|[[:space:];&|(])git( -C [^[:space:]]+)? merge([[:space:]]|$)' || true)"
    plain="$(grep -vE -- '--no-ff' <<<"$lines" || true)"
    [ "$(grep -c . <<<"$lines")" -ge 5 ] && [ -z "$plain" ]
}

# workflow_paths <file> <event>: the `paths:` entries of one trigger in a workflow file, one per
# line, quotes removed. Comment lines inside the list do not end it.
workflow_paths() {
    awk -v ev="$2" '
        /^[^ #]/ { in_ev = 0; inp = 0 }
        /^  [A-Za-z_]+:/ { in_ev = ($0 ~ ("^  " ev ":")); inp = 0; next }
        in_ev && /^    paths:/ { inp = 1; next }
        inp && /^[ \t]*#/ { next }
        inp && /^      - / { sub(/^      - +/, ""); print; next }
        inp { inp = 0 }
    ' "$1" | tr -d "'\""
}
# workflow_has <file> <event> <path>: exit 0 when the trigger's paths name exactly that entry. The
# list is read from a here-string, not piped into `grep -q`, which would turn an early exit into
# a SIGPIPE failure under pipefail.
workflow_has() {
    local paths
    paths="$(workflow_paths "$1" "$2")"
    grep -qxF -- "$3" <<<"$paths"
}

# bash_blocks <file>: every bash fence in the file, concatenated.
bash_blocks() {
    awk '/^[ \t]*```bash$/ { inside = 1; next } /^[ \t]*```$/ { inside = 0; next } inside { print }' "$1"
}
# push_plain <text>: exit 0 when the text has at least three `git push` commands and none of
# them forces: no --force, --force-with-lease or -f flag, and no + refspec.
FORCE_RE='(--force|(^|[[:space:]])-[A-Za-z]*f[A-Za-z]*([[:space:]]|$)|[[:space:]]"?\+[^[:space:]])'
push_plain() {
    local lines
    lines="$(grep -E '(^|[[:space:];&|(])git( -C [^[:space:]]+)? push([[:space:]]|$)' <<<"$1" || true)"
    [ "$(grep -c . <<<"$lines")" -ge 3 ] && ! grep -qE -- "$FORCE_RE" <<<"$lines"
}

# no_quiet_gates <file>: exit 0 when no bash block of the file runs `diff --quiet`. A --quiet gate asks
# the diff machinery, and so the operator's diff settings, whether a change is empty; the route compares
# tree SHAs instead.
no_quiet_gates() {
    ! grep -qE -- 'diff[^;&|]*--quiet' <<<"$(bash_blocks "$1")"
}
# tree_gates_pinned <file>: exit 0 when the file carries all four tree-identity gates.
tree_gates_pinned() {
    local gate
    for gate in "$GATE_A1" "$GATE_A2" "$GATE_B1" "$GATE_B2"; do
        [ "$(has "$1" "$gate")" = yes ] || return 1
    done
}

# gate_timeout_ok <file>: exit 0 when the explicit background `timeout` (milliseconds) exceeds
# the gate's own deadline (seconds), so the block ends by its own exit, not by a harness kill.
gate_timeout_ok() {
    local deadline_s timeout_ms
    deadline_s="$(grep -oE 'SECONDS \+ [0-9]+' "$1" | head -1 | grep -oE '[0-9]+$' || true)"
    timeout_ms="$(grep -oE 'timeout` of `[0-9]+' "$1" | head -1 | grep -oE '[0-9]+$' || true)"
    [ -n "$deadline_s" ] && [ -n "$timeout_ms" ] && [ "$timeout_ms" -gt $((deadline_s * 1000)) ]
}

# modified_ok <file>: exit 0 when the frontmatter `modified:` date is 2026-10-17 or later.
modified_ok() {
    local d
    d="$(sed -n 's/^modified: *//p' "$1" | head -1)"
    [[ "$d" > "2026-10-16" ]]
}

# The reversed and unguarded fixtures are the negative controls for the pins below.
write_lines "$sandbox/reversed-skill.md" \
    'gh pr edit <child> --base main' \
    'gh pr view <base> --json state,mergeStateStatus,mergeable'
write_lines "$sandbox/reversed-ref.md" \
    'merge --no-ff --no-edit "$squash"' \
    'merge --no-ff --no-edit "$pre"'
write_lines "$sandbox/reversed-upd.md" \
    'gh pr update-branch <child>' \
    'git merge-tree --write-tree "$tip" origin/main'
write_lines "$sandbox/unguarded-ref.md" \
    '[ "$route" = A ] && git worktree add --detach <dir> "$tip"' \
    'git -C <dir> merge --no-edit -X ours origin/main'
write_lines "$sandbox/twodot-ref.md" \
    'reviewed=$(git diff -U0 "$pre" "$reviewed_tip" -- <source paths>)'
write_lines "$sandbox/count-gate.md" \
    'gh pr view "$n" --json statusCheckRollup --jq '"'"'length'"'"''
write_lines "$sandbox/reversed-gate.md" \
    'and all(.statusCheckRollup[]; .status == "COMPLETED")'

# Fixtures for the pins added with the polish round: a bash block of plain merges (a control for
# the --no-ff pin), the same block with --no-ff, a bare direction pointer, and a workflow whose
# trigger omits the reference.
write_lines "$sandbox/merge-plain.md" '```bash' \
    'git -C <dir> merge --no-edit "$pre"' \
    'if git -C <dir> merge --no-edit "$squash"; then' \
    'git -C <dir> merge --no-edit -X ours origin/main' \
    'git -C <dir> merge --no-edit origin/main' \
    'git -C <dir> merge --no-edit origin/<child>' \
    '```'
write_lines "$sandbox/merge-noff.md" '```bash' \
    'git -C <dir> merge --no-ff --no-edit "$pre"' \
    'if git -C <dir> merge --no-ff --no-edit "$squash"; then' \
    'git -C <dir> merge --no-ff --no-edit -X ours origin/main' \
    'git -C <dir> merge --no-ff --no-edit origin/main' \
    'git -C <dir> merge --no-ff --no-edit origin/<child>' \
    '```'
write_lines "$sandbox/next-bullet.md" '- Diverged, not yet mirrored (next bullet).'
write_lines "$sandbox/wf-no-ref.yml" \
    'on:' \
    '  pull_request:' \
    '    paths:' \
    "      - 'scripts/**'" \
    '  push:' \
    '    paths:' \
    "      - 'scripts/**'" \
    'concurrency:'

check "no-force reference exists" yes "$(yn test -f "$NF")"
check "no-force: squash commit read from mergeCommit.oid" yes "$(has "$NF" 'mergeCommit.oid')"
check "no-force: pre-squash tip read from headRefOid" yes "$(has "$NF" 'headRefOid')"
check "no-force: the pre-squash merge is pinned to the head it read" yes \
    "$(has "$NF" '--match-head-commit "$pre"')"
check "no-force: the approved child head is recorded before the retarget" yes \
    "$(order_ok "$NF" 'reviewed_tip=$(gh pr view <child>' 'gh pr edit <child> --base main')"
check "no-force: the base state is read before the retarget" yes \
    "$(order_ok "$NF" 'gh pr view <base> --json state,mergeStateStatus,mergeable' 'gh pr edit <child> --base main')"
check "no-force: the base-state table proceeds only on an OPEN state" yes \
    "$(has "$NF" '| `state` | `OPEN` |')"
check "no-force: classification counts the commits after the squash" yes "$(has "$NF" 'rev-list --count')"
check "no-force: classification checks the pre-squash tip is an ancestor of the child" yes \
    "$(has "$NF" 'git merge-base --is-ancestor "$pre" "$tip"')"
check "no-force: classification requires the squash in origin/main (a stale main is not route A)" yes \
    "$(has "$NF" '&& git merge-base --is-ancestor "$squash" origin/main')"
check "control: a classification without that containment check fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" '&& git merge-base --is-ancestor "$squash" origin/main')"
check "no-force: <source paths> defaults to the whole tree" yes \
    "$(has "$NF" 'to the whole tree (`.`)')"
check "control: a reference without that default fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" 'to the whole tree (`.`)')"
check "no-force: the child PR state is read from the newest PR for the branch" yes \
    "$(has "$NF" 'sort_by(.number)')"
check "control: a state read over every PR for the branch fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" 'sort_by(.number)')"
check "no-force: the base-state table stops on DRAFT" yes \
    "$(has "$NF" '`BEHIND`, `DIRTY`, `BLOCKED`, `DRAFT`')"
check "control: a base-state table without DRAFT fails the pin" no \
    "$(has "$sandbox/reversed-skill.md" 'DRAFT')"
check "no-force: tree identity compared with ^{tree}" yes "$(has "$NF" '^{tree}')"
check "no-force: Case A's gate compares the child tip's tree with the merged tree" yes \
    "$(has "$NF" "$GATE_A2")"
check "no-force: -X ours is present" yes "$(has "$NF" '-X ours')"
check "no-force: per-file ours resolution with a tree gate on the resolved index" yes \
    "$(has "$NF" "$GATE_B2")"
check "no-force: pushes by full SHA to the child ref" yes "$(has "$NF" 'refs/heads/<child>')"
check "no-force: pre-squash tip merged before the squash (ordering is the safety property)" yes \
    "$(order_ok "$NF" 'merge --no-ff --no-edit "$pre"' 'merge --no-ff --no-edit "$squash"')"
check "control: a squash merge ahead of the pre-squash tip is rejected" no \
    "$(order_ok "$sandbox/reversed-ref.md" 'merge --no-ff --no-edit "$pre"' 'merge --no-ff --no-edit "$squash"')"
check "no-force: Case B step 3 merges origin/main with no -X or -s option" yes \
    "$(yn step3_plain "$CASE_B_RAW")"
check "control: a step-3 merge with -X ours is rejected" no \
    "$(yn step3_plain 'git -C <dir> merge -X ours --no-edit origin/main')"
check "control: the pin reads the merge line, not the merge-base precondition line, of the real block" no \
    "$(yn step3_plain "${CASE_B_RAW/'merge --no-ff --no-edit origin/main'/'merge --no-ff --no-edit -X ours origin/main'}")"
check "no-force: a rejected push has a recipe that merges the child and checks the tree" yes \
    "$(has "$NF" 'merge --no-ff --no-edit origin/<child>')"
check "no-force: the reviewed baseline is three-dot (pre...approved head)" yes \
    "$(has "$NF" '"${pre}...${reviewed_tip}"')"
check "no-force: the two-dot reviewed baseline is absent" yes \
    "$(yn lacks "$NF" 'diff -U0 "$pre" "$reviewed_tip"')"
check "control: a fixture carrying the two-dot baseline fails the absence pin" no \
    "$(yn lacks "$sandbox/twodot-ref.md" 'diff -U0 "$pre" "$reviewed_tip"')"
check "no-force: the route guard opens both Case A chains" yes "$(yn guard_pinned "$NF")"
check "control: a single guard does not satisfy the two-chain pin" no \
    "$(yn guard_pinned "$sandbox/unguarded-ref.md")"
check "no-force: the update-branch prediction is in the reference" yes \
    "$(has "$NF" 'git merge-tree --write-tree "$tip" origin/main')"
check "no-force: the prediction precedes gh pr update-branch" yes \
    "$(order_ok "$NF" 'git merge-tree --write-tree' 'gh pr update-branch <child>')"
check "control: an update-branch ahead of the prediction is rejected" no \
    "$(order_ok "$sandbox/reversed-upd.md" 'git merge-tree --write-tree' 'gh pr update-branch <child>')"
check "no-force: the worktree is removed without --force after the push" yes \
    "$(has "$NF" 'git worktree remove <dir>')"
check "no-force: the reviewed head is not re-read later" yes \
    "$(has "$NF" 'Do not re-read `reviewed_tip` later')"
check "no-force: Re-read runs in the same shell call as Classify and the Case block (tip is set there)" yes \
    "$(has "$NF" 'runs in the same shell call as Classify and the Case block')"
check "control: a reference without that statement fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" 'runs in the same shell call as Classify and the Case block')"
check "no-force: no positional pointers (above, below, earlier, following)" yes "$(yn pointer_free "$NF")"
check "control: the pointer pattern matches a pointer" yes \
    "$(yn grep -qiE -- "$DIRECTION_RE" <<<"see the table above")"
check "no-force: the sync notes carry the skill-only §2 bullets" yes \
    "$(yn sh -c "grep -qF 'Check the base first' '$SNF' && grep -qF 'No-force alternative' '$SNF'")"
check "control: a file without the skill-only marking fails that pin" no \
    "$(has "$sandbox/reversed-ref.md" 'No-force alternative')"

write_lines "$sandbox/rebase-upd.md" 'gh pr update-branch <child> --rebase'
write_lines "$sandbox/fetch-first.md" \
    'git fetch -q origin <base>' \
    'pre=$(gh pr view <base> --json headRefOid --jq .headRefOid)'
check "no-force: the update-branch call carries no --rebase" yes \
    "$(yn lacks "$NF" 'gh pr update-branch <child> --rebase')"
check "control: an update-branch call with --rebase fails that pin" no \
    "$(yn lacks "$sandbox/rebase-upd.md" 'gh pr update-branch <child> --rebase')"
check "no-force: the base tip is read before the base is fetched" yes \
    "$(order_ok "$NF" 'pre=$(gh pr view <base> --json headRefOid' 'git fetch -q origin <base>')"
check "control: a fetch ahead of the tip read is rejected" no \
    "$(order_ok "$sandbox/fetch-first.md" 'pre=$(gh pr view <base> --json headRefOid' 'git fetch -q origin <base>')"
check "no-force: the local object check runs before the base merge" yes \
    "$(order_ok "$NF" 'git cat-file -e "${pre}^{commit}"' 'gh pr merge <base> --squash')"
check "no-force: the child's PR state is read before the route pushes" yes \
    "$(order_ok "$NF" 'gh pr list --state all --head <child>' 'git merge-tree --write-tree "$tip" origin/main')"
check "control: a route with no PR-state read is rejected" no \
    "$(order_ok "$sandbox/reversed-upd.md" 'gh pr list --state all --head <child>' 'git merge-tree --write-tree "$tip" origin/main')"
check "no-force: the merge-tree prediction is labelled a positive-containment check" yes \
    "$(has "$NF" 'positive-containment')"
check "control: a prediction without that label fails the pin" no \
    "$(has "$sandbox/reversed-upd.md" 'positive-containment')"

# The content diffs behind `reviewed` and step 4 must ignore the operator's diff.external, color and
# submodule settings, or both sides become empty strings and step 4 passes on anything.
write_lines "$sandbox/flagged-diffs.md" "git $DIFF_FLAGS -- ." "git -C <dir> $DIFF_FLAGS origin/main HEAD -- ."
write_lines "$sandbox/one-unflagged-diff.md" "git $DIFF_FLAGS -- ." 'git -C <dir> diff -U0 origin/main HEAD -- .'
write_lines "$sandbox/one-flagged-diff.md" "git $DIFF_FLAGS -- ."
write_lines "$sandbox/partly-flagged-diffs.md" "git $DIFF_FLAGS -- ." \
    'git -C <dir> diff --no-ext-diff --no-color -U0 origin/main HEAD -- .'
check "no-force: every content diff carries the operator-proof flags (reviewed and step 4)" yes \
    "$(yn diffs_flagged "$NF")"
check "control: two flagged content diffs pass the pin" yes "$(yn diffs_flagged "$sandbox/flagged-diffs.md")"
check "control: a step-4 diff without the flags fails the pin" no \
    "$(yn diffs_flagged "$sandbox/one-unflagged-diff.md")"
check "control: a single content diff fails the pin (a deleted comparison is not silent)" no \
    "$(yn diffs_flagged "$sandbox/one-flagged-diff.md")"
check "control: a step-4 diff without the submodule and textconv flags fails the pin" no \
    "$(yn diffs_flagged "$sandbox/partly-flagged-diffs.md")"
check "control: the two-dot fixture has an unflagged content diff" no "$(yn diffs_flagged "$sandbox/twodot-ref.md")"
check "no-force: the raw listing is compared beside the content lines (--raw --numstat)" yes \
    "$(has "$NF" '--raw --numstat')"
check "no-force: the raw listing carries --no-ext-diff --no-color, --ignore-submodules=none and --no-textconv" yes \
    "$(has "$NF" "$META_FLAGS")"
check "control: a reference without the raw listing fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" '--raw --numstat')"

# The content lines are the ones an indicator marks. A removed line whose text starts with `-- a/`
# prints as `--- a/`, which a header-shaped filter reads as a file header and drops (scenario C).
# Indicators that no header can carry keep it, so the content filter keeps only the marked lines.
check "no-force: both content diffs take indicators no header can carry" yes \
    "$(yn test "$(count_of "$NF" "--output-indicator-new='>' --output-indicator-old='<'")" -ge 2)"
check "no-force: both content filters keep only the indicator lines" yes \
    "$(yn test "$(count_of "$NF" "grep -E '^[<>]'")" -ge 2)"
check "no-force: no content filter drops lines by their header shape" yes \
    "$(yn lacks "$NF" '^(\+\+\+|---) (a/|b/|/dev/null)')"
printf '%s\n' "grep -vE '^(\\+\\+\\+|---) (a/|b/|/dev/null)'" > "$sandbox/header-filter.md"
check "control: a fixture filtering by header shape fails that pin" no \
    "$(yn lacks "$sandbox/header-filter.md" '^(\+\+\+|---) (a/|b/|/dev/null)')"

# The empty-diff gates compare tree SHAs. A --quiet gate asks the diff machinery whether a change is
# empty, and repo or operator settings can answer for it: a committed `ignore = all` hides a gitlink
# (scenario SM), and diff.trustExitCode (git 2.46+) returns a diff.external helper's exit code when
# external drivers are allowed.
# git 2.43 in the sandbox ignores trustExitCode, so these pins are the structural check, each with a control.
write_lines "$sandbox/quiet-gates.md" '```bash' \
    'git -C <dir> diff --no-ext-diff --quiet "$tip" HEAD' \
    '```'
write_lines "$sandbox/tree-gates.md" '```bash' "$GATE_A1" "$GATE_A2" "$GATE_B1" "$GATE_B2" '```'
write_lines "$sandbox/three-tree-gates.md" '```bash' "$GATE_A1" "$GATE_A2" "$GATE_B1" '```'
check "no-force: no empty-diff gate in the route runs diff --quiet" yes "$(yn no_quiet_gates "$NF")"
check "no-force: the four empty-diff gates compare tree SHAs (Case A chain and merge, Case B before-merge and resolved index)" \
    yes "$(yn tree_gates_pinned "$NF")"
check "control: a --quiet gate fails the no-quiet pin" no "$(yn no_quiet_gates "$sandbox/quiet-gates.md")"
check "control: the four tree gates pass the tree pin" yes "$(yn tree_gates_pinned "$sandbox/tree-gates.md")"
check "control: three tree gates fail the tree pin (the resolved-index gate is missing)" no \
    "$(yn tree_gates_pinned "$sandbox/three-tree-gates.md")"
check "no-force: the note no longer claims --quiet skips external helpers" yes \
    "$(yn lacks "$NF" 'skips external helpers')"
check "no-force: the note names diff.trustExitCode as a reason to compare trees" yes \
    "$(has "$NF" 'diff.trustExitCode')"
check "control: a reference without the trustExitCode note fails that pin" no \
    "$(has "$sandbox/reversed-ref.md" 'diff.trustExitCode')"

# Classify opens by refusing an unset or empty ref, so no route is assigned from a missing SHA.
CLASSIFY_GUARD=': "${pre:?}" "${squash:?}" "${reviewed_tip:?}" "${tip:?}"'
check "no-force: Classify opens by refusing an unset or empty ref" yes "$(has "$NF" "$CLASSIFY_GUARD")"
check "control: a reference without that guard fails the pin" no "$(has "$sandbox/reversed-ref.md" "$CLASSIFY_GUARD")"
# Case B step 4 refuses an empty reviewed baseline (scenario EB).
check "no-force: Case B step 4 refuses an empty reviewed baseline" yes "$(has "$NF" "$EB_GUARD")"
check "control: a reference without the empty-baseline guard fails that pin" no \
    "$(has "$sandbox/reversed-ref.md" "$EB_GUARD")"
# The minimum git version is stated once, not repeated through the prose.
check "no-force: the git 2.38 minimum is stated once" yes "$(yn test "$(count_of "$NF" '2.38')" -eq 1)"
write_lines "$sandbox/twice-min.md" 'The recipes need git 2.38 or later.' 'Again: git 2.38 or later.'
check "control: a reference that repeats the minimum fails the once pin" no \
    "$(yn test "$(count_of "$sandbox/twice-min.md" '2.38')" -eq 1)"
# Line relocation is the fourth blind spot of the step-4 content lines; the serial-merge-chain guard covers it.
check "no-force: line relocation is named as a blind spot of the step-4 content lines" yes \
    "$(has "$NF" 'line relocation')"
check "no-force: the relocation blind spot points to the serial-merge-chain guard for a non-merge commit" yes \
    "$(has "$NF" 'non-merge relocation commit')"
check "control: a reference without the relocation blind spot fails that pin" no \
    "$(has "$sandbox/reversed-ref.md" 'line relocation')"

# No push in the route forces. A force answers a refused push by deleting the commit that
# caused the refusal, which is a bot's commit or a teammate's.
PUSH_OK='git -C <dir> push origin "${new}:refs/heads/<child>"'
NL=$'\n'
check "no-force: no push line in the route's bash blocks forces (no --force, -f or + refspec)" yes \
    "$(yn push_plain "$(bash_blocks "$NF")")"
check "control: three plain pushes pass the no-force pin" yes \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}${PUSH_OK}")"
check "control: a --force push fails the pin" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}"'git -C <dir> push --force origin "${new}:refs/heads/<child>"')"
check "control: a -f push fails the pin" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}"'&& git -C <dir> push -f origin "${new}:refs/heads/<child>"')"
check "control: a + refspec push fails the pin" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}"'git -C <dir> push origin "+${new}:refs/heads/<child>"')"
check "control: a --force-with-lease push fails the pin" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}"'git -C <dir> push --force-with-lease origin "${new}:refs/heads/<child>"')"
check "control: a bundled -fu push fails the pin" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}${NL}"'git push -fu origin "${new}:refs/heads/<child>"')"
check "control: fewer than three push lines fail the pin (a renamed command is not silent)" no \
    "$(yn push_plain "${PUSH_OK}${NL}${PUSH_OK}")"
check "no-force: the rejected-push block ends in a push, and the pin above reads it" yes \
    "$(yn grep -qE -- 'push origin' <<<"$(tail -n 1 <<<"$REJECT_RAW")")"

check "no-force: every git merge in the route's bash blocks passes --no-ff (merge.ff=only cannot refuse one)" yes \
    "$(yn merges_no_ff "$NF")"
check "control: a plain git merge in a bash block fails the --no-ff pin" no \
    "$(yn merges_no_ff "$sandbox/merge-plain.md")"
check "control: a block of --no-ff merges passes the pin" yes "$(yn merges_no_ff "$sandbox/merge-noff.md")"
check "no-force: a merge stop can name merge.verifySignatures as its cause" yes \
    "$(has "$NF" 'merge.verifySignatures')"
check "control: a reference that never names merge.verifySignatures fails that pin" no \
    "$(has "$sandbox/reversed-ref.md" 'merge.verifySignatures')"

check "gate: count gate removed (--jq 'length' absent)" yes "$(yn lacks "$GF" "--jq 'length'")"
check "control: a fixture carrying the count gate fails the absence pin" no \
    "$(yn lacks "$sandbox/count-gate.md" "--jq 'length'")"
check "gate: the rollup is read" yes "$(has "$GF" 'statusCheckRollup')"
check "gate: head SHA check present" yes "$(has "$GF" 'headRefOid')"
check "gate: completion check present" yes "$(has "$GF" 'COMPLETED')"
check "gate: skipped and neutral conclusions named as accepted" yes "$(has "$GF" 'SKIPPED')"
check "gate: legacy commit statuses are read through state" yes "$(has "$GF" '(.conclusion // .state)')"
check "control: a fixture without the state fallback fails the pin" no \
    "$(has "$sandbox/reversed-gate.md" '(.conclusion // .state)')"
check "gate: the cited registration race names its repository" yes \
    "$(has "$GF" 'ForumViriumHelsinki/.github-private #13, #15, #19')"
check "control: the registration race no longer cites claude-plugins PRs" no \
    "$(has "$GF" '(claude-plugins #13')"
check "gate: Recovery bullet kept" yes \
    "$(has "$GF" '- **Recovery** when auto-closed: the rebased commits survive in local objects')"
check "gate: Recovery refspec kept byte-identical" yes \
    "$(has "$GF" '(`git reflog`) — `git push --force-with-lease origin "${sha}:refs/heads/<branch>"`,')"
check "gate: the poll has a wall-clock deadline" yes "$(has "$GF" 'deadline=$((SECONDS + 1800))')"
check "gate: the 30-minute poll is run in the background, past the foreground Bash limit" yes \
    "$(has "$GF" 'run_in_background: true')"
check "control: a gate note without the background run fails the pin" no \
    "$(has "$sandbox/count-gate.md" 'run_in_background: true')"
write_lines "$sandbox/equal-timeout.md" \
    'deadline=$((SECONDS + 1800))' \
    'Run it with `run_in_background: true` and an explicit `timeout` of `1800000`.'
write_lines "$sandbox/no-timeout.md" \
    'deadline=$((SECONDS + 1800))' \
    'Run it with `run_in_background: true`, whose default limit is 30 minutes.'
write_lines "$sandbox/larger-timeout.md" \
    'deadline=$((SECONDS + 1800))' \
    'Run it with `run_in_background: true` and an explicit `timeout` of `1800001`.'
check "gate: the background run carries an explicit timeout above the gate's own deadline" yes \
    "$(yn gate_timeout_ok "$GF")"
check "control: a timeout equal to the deadline fails the pin (the harness kill races the exit)" no \
    "$(yn gate_timeout_ok "$sandbox/equal-timeout.md")"
check "control: a note with no explicit timeout fails the pin" no "$(yn gate_timeout_ok "$sandbox/no-timeout.md")"
check "control: a timeout above the deadline passes the pin" yes "$(yn gate_timeout_ok "$sandbox/larger-timeout.md")"
check "gate: a PR that is no longer OPEN ends the poll" yes "$(has "$GF" 'MERGED|CLOSED) break')"
check "control: a loop without the deadline fails the pin" no \
    "$(has "$sandbox/count-gate.md" 'deadline=$((SECONDS + 1800))')"

for grant in 'Bash(git merge *)' 'Bash(git checkout *)' 'Bash(git worktree *)' \
    'Bash(git diff *)' 'Bash(git rev-list *)' 'Bash(git add *)' 'Bash(git commit *)' \
    'Bash(git -C *)' 'Bash(git merge-base *)' 'Bash(grep *)' 'Bash(awk *)' 'Bash(jq *)'; do
    check "skill: frontmatter grants $grant" yes "$(has "$SF" "$grant")"
done
check "skill: modified date is at or after 2026-10-17" yes "$(yn modified_ok "$SF")"
check "skill: the body stays under the 10,000-character WARN band" yes "$(yn under_warn "$SF")"
check "skill: base-state precondition present" yes \
    "$(has "$SF" 'gh pr view <base> --json state,mergeStateStatus,mergeable')"
check "skill: the precondition proceeds only on an OPEN base" yes "$(has "$SF" '`state` is `OPEN`')"
check "skill: base-state read precedes the retarget" yes \
    "$(order_ok "$SF" 'gh pr view <base> --json state,mergeStateStatus,mergeable' 'gh pr edit <child> --base main')"
check "control: a retarget ahead of the base-state read is rejected" no \
    "$(order_ok "$sandbox/reversed-skill.md" 'gh pr view <base> --json state,mergeStateStatus,mergeable' 'gh pr edit <child> --base main')"
check "skill: no-force pointer names its reference" yes \
    "$(has "$SF" '[references/no-force-push-stack.md](references/no-force-push-stack.md)')"
check "skill: no-force pointer target exists" yes "$(yn test -f "$REF_DIR/no-force-push-stack.md")"
check "control: an absent pointer target is reported absent" no "$(yn test -f "$REF_DIR/no-such-route.md")"
check "skill: the base-state anchor names a heading in its reference" yes \
    "$(has "$NF" '## Check the base first')"
check "skill: the maintainer notes are in sync-notes.md" yes "$(has "$SF" 'references/sync-notes.md')"
check "skill: rebase fallback kept" yes "$(has "$SF" 'git rebase --onto origin/main')"
check "skill: §6 names a retarget as a second bot trigger" yes "$(has "$SF" 'gh pr edit --base')"
check "control: a body without the retarget trigger fails the pin" no \
    "$(has "$sandbox/reversed-skill.md" 'gh pr edit --base')"
check "sync-notes: §1's REVIEW-bucket sentence is listed as skill-only" yes \
    "$(has "$SNF" "§1's REVIEW-bucket sentence")"
check "control: a sync-notes file without that entry fails the pin" no \
    "$(has "$sandbox/reversed-ref.md" "§1's REVIEW-bucket sentence")"
check "skill: the branch-audit caveat names its measured bucket" yes "$(has "$SF" 'REVIEW bucket')"
check "skill: the branch-audit caveat cites #2268" yes "$(has "$SF" '#2268')"
check "control: a body without the caveat fails the bucket pin" no \
    "$(has "$sandbox/reversed-skill.md" 'REVIEW bucket')"
check "skill: frontmatter grants git cat-file (the Record block's object check)" yes \
    "$(has "$SF" 'Bash(git cat-file *)')"
check "skill: frontmatter grants sleep (the rollup gate's poll interval)" yes "$(has "$SF" 'Bash(sleep *)')"

check "gh-json-fields: points at the rollup gate" yes "$(has "$FIELDS_FILE" 'stacked-chain-push.md')"
check "gh-json-fields: two-read stability guidance kept" yes \
    "$(has "$FIELDS_FILE" 'stable across two consecutive reads')"
check "README: the git-merge-hazards row names the no-force route" yes \
    "$(has "$README_FILE" 'no-force merge-main route')"
check "test is registered as a required test" yes \
    "$(has "$MANIFEST_FILE" 'git-plugin/skills/git-merge-hazards/scripts/tests/test-no-force-stack.sh')"

# A PR that edits only the reference recipe, or only the field rule, must still run this suite.
check "workflow: the pull_request paths run the suite on an edit to the no-force reference" yes \
    "$(yn workflow_has "$WORKFLOW_FILE" pull_request 'git-plugin/skills/git-merge-hazards/**')"
check "workflow: the push paths run the suite on an edit to the no-force reference" yes \
    "$(yn workflow_has "$WORKFLOW_FILE" push 'git-plugin/skills/git-merge-hazards/**')"
check "workflow: the pull_request paths run the suite on an edit to gh-json-fields.md" yes \
    "$(yn workflow_has "$WORKFLOW_FILE" pull_request '.claude/rules/gh-json-fields.md')"
check "workflow: the push paths run the suite on an edit to gh-json-fields.md" yes \
    "$(yn workflow_has "$WORKFLOW_FILE" push '.claude/rules/gh-json-fields.md')"
check "control: a trigger whose paths omit the reference fails the pin" no \
    "$(yn workflow_has "$sandbox/wf-no-ref.yml" pull_request 'git-plugin/skills/git-merge-hazards/**')"

check "sync-notes: §3's pointer names its target instead of a direction" yes \
    "$(has "$SNF" "(see **Diverged, not yet mirrored: §3's registration race**)")"
check "sync-notes: no bare '(next bullet)' pointer remains" yes "$(yn lacks "$SNF" '(next bullet)')"
check "control: a file with the bare '(next bullet)' pointer fails that pin" no \
    "$(yn lacks "$sandbox/next-bullet.md" '(next bullet)')"

printf '%s\n' "test-no-force-stack.sh: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
