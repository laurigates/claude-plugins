#!/usr/bin/env bash
# shellcheck disable=SC2015   # `cond && ok … || notok …` is this repo's assertion idiom
#
# Content pins for git-plugin skill guidance added from session-feedback issues.
# Each case asserts the semantic invariant a feedback issue asked for, so a later
# bulk "tighten the prose" edit that drops it fails here instead of silently
# re-opening the gap.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="${SCRIPT_DIR}/../../skills"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
notok() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# section <file> <heading-prefix> — print the lines from the first heading that
# starts with <heading-prefix> up to (not including) the next heading of the
# same or higher level.
section() {
    awk -v want="$2" '
        /^#+ / {
            n = index($0, " ") - 1
            if (inside && n <= lvl) exit
            if (!inside && index($0, want) == 1) { inside = 1; lvl = n }
        }
        inside { print }
    ' "$1"
}

# has <label> <text> <fixed-string> — <text> contains <fixed-string>.
has() {
    grep -qF -- "$3" <<<"$2" && ok "$1" || notok "$1: missing '$3'"
}

# before <label> <text> <first> <second> — <first> appears on an earlier line
# than <second>, and both appear.
before() {
    local a b
    a=$(grep -nF -m1 -- "$3" <<<"$2" | cut -d: -f1)
    b=$(grep -nF -m1 -- "$4" <<<"$2" | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && ok "$1" ||
        notok "$1: '$3' (line ${a:-none}) must precede '$4' (line ${b:-none})"
}

echo "=== #3628 git-issue --auto: already-implemented check before scoring ==="
modes="${SKILLS}/git-issue/references/selection-modes.md"
auto=$(section "$modes" "### Auto Mode")
has "auto mode searches merged PRs" "$auto" "--state merged"
has "auto mode searches the default branch log" "$auto" "origin/main"
has "auto mode routes a hit to the verification-only flow" "$auto" "verification-only.md"
before "the merged-work check runs before scoring" "$auto" "--state merged" "Score and prioritize"
has "interactive 'Claude decides priority' runs the same check" "$(section "$modes" "### No Arguments")" "already-implemented check"
has "SKILL.md names the check on the --auto route" "$(cat "${SKILLS}/git-issue/SKILL.md")" "already-implemented check"

echo "=== #3616 release-please: generic updater and release-workflow gotchas ==="
rpc="${SKILLS}/release-please-configuration"
generic="${rpc}/references/generic-updater.md"
has "release-please-configuration links the generic-updater reference" "$(cat "${rpc}/SKILL.md")" "](references/generic-updater.md)"
gtext=$(cat "$generic" 2>/dev/null)
has "generic updater skips a version that is not major.minor.patch" "$gtext" "major.minor.patch"
has "generic updater rewrites CRLF files as LF" "$gtext" "CRLF"
has "a GITHUB_TOKEN tag triggers no on: push: tags workflow" "$gtext" "GITHUB_TOKEN"
has "the build job gates on the release_created output" "$gtext" "release_created"
rppw=$(cat "${SKILLS}/release-please-pr-workflow/SKILL.md")
has "a release PR stuck CONFLICTING after a non-releasable commit" "$rppw" "non-releasable"
has "the stuck PR is closed with its branch deleted before the rerun" "$rppw" "--delete-branch"

echo "=== #3614 no-force stack: Case A step 1 is expected to fail for a child that edits the base's files ==="
nofp="${NOFORCE_STACK_FILE:-${SKILLS}/git-merge-hazards/references/no-force-push-stack.md}"
case_a=$(section "$nofp" "## Case A")
before "the Case A intro sends such a stack to step 2 before step 1 runs" "$case_a" "expect step 1's prediction to fail" "1. Try the plain fast-forward first"
has "step 1 calls the failure expected for this shape" "$case_a" "step 2 is its normal path"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
