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
# same or higher level. Lines inside ``` fences are never headings, so a shell
# comment in a code block does not end the section.
section() {
    awk -v want="$2" '
        /^[[:space:]]*```/ { fence = !fence }
        !fence && /^#+ / {
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
# The GITHUB_TOKEN tag case is GitHub Actions behaviour; the summary must not
# count it among the generic updater's failures (finding F3). The summary lives
# in the reference so the SKILL.md body stays under the size WARN (finding G2).
has "the summary counts two generic-updater failures" "$gtext" "fails silently in two"
has "the summary attributes the tag case to GitHub Actions" "$gtext" "GitHub Actions behaviour"
has "generic updater skips a version that is not major.minor.patch" "$gtext" "major.minor.patch"
has "generic updater rewrites CRLF files as LF" "$gtext" "CRLF"
has "a GITHUB_TOKEN tag triggers no on: push: tags workflow" "$gtext" "GITHUB_TOKEN"
has "the build job gates on the release_created output" "$gtext" "release_created"
# The stuck-PR guidance lives in a sidecar so the SKILL.md body stays under the
# size WARN; the body links it from § Why Conflicts Occur (finding F4).
rppw_dir="${SKILLS}/release-please-pr-workflow"
has "Why Conflicts Occur links the stuck-PR reference" "$(section "${rppw_dir}/SKILL.md" "### Why Conflicts Occur")" "](references/stuck-conflicting.md)"
rppw=$(cat "${rppw_dir}/references/stuck-conflicting.md" 2>/dev/null)
has "a release PR stuck CONFLICTING after a non-releasable commit" "$rppw" "non-releasable"
has "the stuck PR is closed with its branch deleted before the rerun" "$rppw" "--delete-branch"
# The Recovery section moved verbatim to troubleshooting.md to make room for the
# generic-updater link (finding G2); the body still points at it.
has "the untagged-PR failure links the moved Recovery section" "$(section "${rpc}/SKILL.md" "### Common Failure: Merged Release PR Never Tagged")" "troubleshooting.md#recovery-unwedge-an-already-merged-untagged-pr"
has "troubleshooting.md carries the Recovery section" "$(section "${rpc}/references/troubleshooting.md" "### Recovery: Unwedge")" '--add-label "autorelease: tagged" --remove-label "autorelease: pending"'
rppw_chars=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "${rppw_dir}/SKILL.md")
[ "$rppw_chars" -le 10000 ] && ok "release-please-pr-workflow SKILL.md is within the 10,000-char WARN line" ||
    notok "release-please-pr-workflow SKILL.md is ${rppw_chars} chars, over the 10,000-char WARN line"
rpc_chars=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "${rpc}/SKILL.md")
[ "$rpc_chars" -le 10000 ] && ok "release-please-configuration SKILL.md is within the 10,000-char WARN line" ||
    notok "release-please-configuration SKILL.md is ${rpc_chars} chars, over the 10,000-char WARN line"

echo "=== #3614 no-force stack: Case A step 1 is expected to fail for a child that edits lines at or next to the base's ==="
nofp="${NOFORCE_STACK_FILE:-${SKILLS}/git-merge-hazards/references/no-force-push-stack.md}"
case_a=$(section "$nofp" "## Case A")
before "the Case A intro sends such a stack to step 2 before step 1 runs" "$case_a" "expect step 1's prediction to fail" "1. Try the plain fast-forward first"
has "step 1 calls the failure expected for this shape" "$case_a" "step 2 is its normal path"
# The condition is per hunk, not per file: a child editing a shared file away
# from the base's hunks merges cleanly and passes step 1 (verifier finding F1).
has "the intro states the condition at line level" "$case_a" "lines at or next to the lines the base changed"
has "the intro says a 3-way merge conflicts per hunk" "$case_a" "conflicts per hunk, not per file"
has "step 1 states the condition at line level" "$case_a" "edits lines at or next to its base's"

echo "=== #3614 mechanism: merge-tree after a squash-merge, per hunk ==="
# The text above claims git behaviour; check it against git itself. A base PR
# edits line 10 of one file, a stacked child edits another line, the base is
# squash-merged into main, and `merge-tree --write-tree child main` must return
# the child's own tree only when the child's edit is away from line 10.
squash_stack_predicts_child_tree() { # <sed edit for the child> -> exit 0 when step 1 would pass
    local repo out child_tree
    repo=$(mktemp -d) || return 2
    [ -n "$repo" ] && [ -d "$repo" ] || return 2
    (
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
        git -C "$repo" init -q -b main &&
            git -C "$repo" config user.email t@example.com &&
            git -C "$repo" config user.name t &&
            seq 1 60 >"$repo/f.txt" &&
            git -C "$repo" add f.txt &&
            git -C "$repo" commit -qm "old main" &&
            git -C "$repo" switch -qc base &&
            sed -i.bak 's/^10$/ten-base/' "$repo/f.txt" && rm -f "$repo/f.txt.bak" &&
            git -C "$repo" commit -qam "base" &&
            git -C "$repo" switch -qc child &&
            sed -i.bak "$1" "$repo/f.txt" && rm -f "$repo/f.txt.bak" &&
            git -C "$repo" commit -qam "child" &&
            git -C "$repo" switch -q main &&
            git -C "$repo" merge -q --squash base >/dev/null &&
            git -C "$repo" commit -qm "squash base" || exit 2
        out=$(git -C "$repo" merge-tree --write-tree child main 2>/dev/null)
        out=${out%%$'\n'*}
        child_tree=$(git -C "$repo" rev-parse 'child^{tree}')
        [ "$out" = "$child_tree" ]
    )
    local rc=$?
    rm -rf "$repo"
    return "$rc"
}
if grep -qF -- '--write-tree' <<<"$(git merge-tree -h 2>&1)"; then
    squash_stack_predicts_child_tree 's/^50$/fifty-child/'
    sim_rc=$?
    [ "$sim_rc" -eq 0 ] && ok "a child editing the shared file away from the base's hunk passes step 1" ||
        notok "a child editing line 50 (base edited line 10) did not get its own tree back"
    squash_stack_predicts_child_tree 's/^ten-base$/ten-child/'
    sim_rc=$?
    [ "$sim_rc" -eq 1 ] && ok "a child editing the base's own line fails step 1" ||
        notok "a child editing the base's line 10 got its own tree back, or setup failed"
    squash_stack_predicts_child_tree 's/^11$/eleven-child/'
    sim_rc=$?
    [ "$sim_rc" -eq 1 ] && ok "a child editing the line next to the base's fails step 1" ||
        notok "a child editing line 11 (base edited line 10) got its own tree back, or setup failed"
else
    echo "  SKIP: git $(git --version | awk '{print $3}') lacks merge-tree --write-tree (needs 2.38+)"
fi

echo "=== #3606 upstream-pr-contribution: gate a behaviour fix on its observed outcome ==="
upr=$(cat "${SKILLS}/upstream-pr-contribution/SKILL.md")
before "the outcome gate comes before the description is written" "$upr" "## Check the outcome" "## Writing the description"
outcome=$(section "${SKILLS}/upstream-pr-contribution/SKILL.md" "## Check the outcome")
has "a reaction is not the outcome observable" "$outcome" "reaction"
has "an unobservable outcome opens the PR as a draft" "$outcome" "--draft"

echo "=== #3593 gh-cli-agentic: the github-actions bot's three spellings ==="
gca="${SKILLS}/gh-cli-agentic"
bots=$(section "${gca}/REFERENCE.md" "## Bot Authors")
has "JSON output spelling" "$bots" "app/github-actions"
has "search output spelling" "$bots" "github-actions[bot]"
has "the --author filter is named as unreliable for the bot" "$bots" "--author"
has "the working form filters author.login with jq" "$bots" ".author.login"
# The jq filter is the prescribed form. gh issue list maps --app <name> to the
# author filter app/<name>, the same createdBy path as the failing --author form,
# so --app is named as equivalent, never offered first (finding G1).
before "the jq filter is prescribed before --app is mentioned" "$bots" ".author.is_bot and" "--app"
has "--app is named as the same filter as --author" "$bots" "it is the same filter"
has "the --app claim cites gh's source" "$bots" "pkg/cmd/issue/list/list.go"
has "the jq filter names its list cap" "$bots" "past that cap"
gli=$(section "${gca}/SKILL.md" "### List Issues")
has "SKILL.md List Issues prescribes the jq filter" "$gli" ".author.login"
has "SKILL.md List Issues rules out --app" "$gli" "not \`--author\` or \`--app\`"
has "SKILL.md List Issues points at the Bot Authors section" "$gli" "REFERENCE.md#bot-authors"
gca_chars=$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "${gca}/SKILL.md")
[ "$gca_chars" -le 10000 ] && ok "gh-cli-agentic SKILL.md is within the 10,000-char WARN line" ||
    notok "gh-cli-agentic SKILL.md is ${gca_chars} chars, over the 10,000-char WARN line"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
