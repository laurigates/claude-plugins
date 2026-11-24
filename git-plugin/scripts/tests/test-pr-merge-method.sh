#!/usr/bin/env bash
# shellcheck disable=SC2015   # `cond && ok … || notok …` is this repo's assertion idiom
#
# Regression tests for git-plugin/scripts/pr-merge-method.py — the rebase-vs-squash
# decision behind the check-pr-merge-method.sh hook and the merge-method check run.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# pr-*.json are real claude-plugins PRs captured with --emit-fixture; the
# expected method for each is the hand label from the calibration over the last
# 400 merged PRs (claude-plugins squashes with COMMIT_MESSAGES, so their bodies
# are never linted). synthetic-*.json mutate pr-2940 (four independent fixes, so
# rebase-eligible) to reach one rule each.
#
# The no-commits control matters most: a failed or empty fetch must come back
# as STATUS=ERROR, not as rule 3/7 "squash", or a broken gh call would look like
# a decision.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${SCRIPT_DIR}/../pr-merge-method.py"
FX="${SCRIPT_DIR}/fixtures/pr-merge-method"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
notok() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# expect <fixture> <METHOD> <REASON> — run the tool and compare both keys.
expect() {
    local fx=$1 method=$2 reason=$3 out
    out=$(python3 "$TOOL" --fixture "$FX/$fx.json")
    grep -qx "METHOD=$method" <<<"$out" && grep -qx "REASON=$reason" <<<"$out" &&
        ok "$fx -> $method ($reason)" ||
        notok "$fx: wanted $method/$reason, got $(grep -E '^(METHOD|REASON)=' <<<"$out" | tr '\n' ' ')"
}

echo "=== real PRs ==="
expect pr-3182 squash in_pr_correction   # feat + fix to the file the feat added
# pr-3132's third commit re-placed the ledger row its first commit appended; its
# only overlap is docs/regression-ledger.md, which #3373 leaves out of rule 8.
# It was hand-labelled squash; it now rebases, and merge:squash is the lever.
expect pr-3132 rebase independent_commits
expect pr-3117 squash fixup_or_review_churn  # "close review gaps"
expect pr-2996 squash merge_commit       # synced main by merge
expect pr-2940 rebase independent_commits
expect pr-3108 rebase independent_commits # a docs polish commit does not force squash
expect pr-2537 squash bot_or_release     # release-please
expect pr-2538 squash single_commit

echo "=== one rule each ==="
expect synthetic-human-label squash override_label
expect synthetic-bot-label rebase independent_commits
expect synthetic-fixup squash fixup_or_review_churn
expect synthetic-nonconventional squash non_conventional
expect synthetic-single-concern squash single_concern

echo "=== rule 8 ignores convention files (#3373) ==="
# Two same-scope fixes sharing only the regression ledger and the plugin README
# (2/4 files, the PR #3370 false positive) stay rebase; real code overlap still
# flags; a merge=union path counts as convention only when .gitattributes lists it.
expect synthetic-shared-docs rebase independent_commits
expect synthetic-shared-docs-code-overlap squash in_pr_correction
expect synthetic-union-path rebase independent_commits
expect synthetic-union-path-unlisted squash in_pr_correction

echo "=== union paths from .gitattributes ==="
out=$(python3 - "$TOOL" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("pmm", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
text = "* text=auto eol=lf\n# docs/x.md merge=union\ndocs/regression-ledger.md merge=union\nlogs/*.log  merge=union -diff\n*.svg linguist-generated=true\n"
print(m.union_paths(text))
PY
)
[ "$out" = "['docs/regression-ledger.md', 'logs/*.log']" ] &&
    ok "union_paths parses merge=union lines, skips comments" || notok "union_paths: $out"

echo "=== OVERRIDE names the label ==="
out=$(python3 "$TOOL" --fixture "$FX/synthetic-human-label.json")
grep -qx 'OVERRIDE=merge:squash' <<<"$out" && ok "OVERRIDE=merge:squash" || notok "OVERRIDE missing: $out"

echo "=== control: no commits is an ERROR, not a decision ==="
rc=0
out=$(python3 "$TOOL" --fixture "$FX/synthetic-no-commits.json") || rc=$?
[ "$rc" -eq 1 ] && grep -qx 'STATUS=ERROR' <<<"$out" && ! grep -q '^METHOD=squash' <<<"$out" &&
    ok "no commits -> exit 1, STATUS=ERROR" || notok "no commits -> rc=$rc: $out"

echo "=== body lint ==="
out=$(python3 "$TOOL" --fixture "$FX/synthetic-body-lint.json")
for kv in LINT_CHECKLIST=2 LINT_HTML_COMMENT=1 LINT_HEADING=1 LINT_CLOSES_AFTER_MERGE=1 LINT_STALE_BODY=1 BODY_LINT=6 STATUS=WARN; do
    grep -qx "$kv" <<<"$out" && ok "$kv" || notok "$kv not in: $(grep -E '^(LINT_|BODY_LINT|STATUS)' <<<"$out" | tr '\n' ' ')"
done
out=$(python3 "$TOOL" --fixture "$FX/synthetic-commit-messages-body.json")
grep -qx 'SQUASH_BODY=COMMIT_MESSAGES' <<<"$out" && grep -qx 'BODY_LINT=0' <<<"$out" &&
    ok "COMMIT_MESSAGES repo: PR body not linted (it never lands)" || notok "COMMIT_MESSAGES body linted: $out"
out=$(python3 "$TOOL" --fixture "$FX/synthetic-rebase-body.json")
grep -qx 'BODY_LINT=0' <<<"$out" && grep -qx 'STATUS=OK' <<<"$out" &&
    ok "rebase: body not linted (it never lands)" || notok "rebase linted the body: $out"
out=$(python3 "$TOOL" --fixture "$FX/pr-2537.json")
grep -qx 'BODY_LINT=0' <<<"$out" && ok "bot PR: generated body not linted" || notok "bot body linted: $out"

echo "=== contract ==="
out=$(python3 "$TOOL" --fixture "$FX/pr-2940.json")
for key in PR METHOD RULE REASON DETAIL OVERRIDE TITLE COMMITS SQUASH_BODY BODY_LINT STATUS ISSUE_COUNT; do
    grep -q "^$key=" <<<"$out" && ok "emits $key=" || notok "missing $key="
done
grep -qx 'TITLE=→ Rebase and merge (4 independent conventional commits)' <<<"$out" &&
    ok "rebase title" || notok "title: $(grep ^TITLE= <<<"$out")"

echo "=== --local: classify an unpushed branch from git (#3686) ==="
# Throwaway repos only: HOME and global/system git config are isolated, the
# GIT_DIR family is unset (#1745), and every repo dir is guarded so an empty
# mktemp result can never point git at the real checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
LOCAL_TMP=$(mktemp -d) || { notok "mktemp failed"; echo "PASSED=$PASS FAILED=$FAIL"; exit 1; }
[ -n "$LOCAL_TMP" ] && [ -d "$LOCAL_TMP" ] || { notok "no temp dir"; exit 1; }
trap 'rm -rf "$LOCAL_TMP"' EXIT
export HOME="$LOCAL_TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

g() { git -c user.name=Test -c user.email=test@example.invalid -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# new_repo <name> — repo with one base commit; origin/main points at it.
new_repo() {
    local r="$LOCAL_TMP/$1"
    mkdir -p "$r" && [ -d "$r" ] || return 1
    g -C "$r" init -q && echo base >"$r/base.txt" && g -C "$r" add base.txt &&
        g -C "$r" commit -qm "chore: base" && g -C "$r" update-ref refs/remotes/origin/main HEAD &&
        g -C "$r" switch -qc feature && printf '%s\n' "$r"
}
# commit_file <repo> <file> <message>
commit_file() { echo "$3" >>"$1/$2" && g -C "$1" add "$2" && g -C "$1" commit -qm "$3"; }

# local_expect <repo> <METHOD> <REASON> <label> [range]
local_expect() {
    local r=$1 method=$2 reason=$3 label=$4 out
    out=$(cd "$r" && python3 "$TOOL" --local ${5:+"$5"})
    grep -qx "METHOD=$method" <<<"$out" && grep -qx "REASON=$reason" <<<"$out" &&
        ok "local $label -> $method ($reason)" ||
        notok "local $label: wanted $method/$reason, got $(tr '\n' ' ' <<<"$out")"
}

if r=$(new_repo indep); then
    commit_file "$r" a.py "feat(a): add a"
    commit_file "$r" b.py "fix(b): repair b"
    local_expect "$r" rebase independent_commits "two independent commits"
    out=$(cd "$r" && python3 "$TOOL" --local)
    grep -qx 'NOT_EVALUATED=rule1_override_label,rule2_bot_author' <<<"$out" &&
        ok "local output names the rules it cannot evaluate" || notok "NOT_EVALUATED missing: $out"
    grep -qx 'PR=local:origin/main..HEAD' <<<"$out" &&
        ok "default range is origin/main..HEAD (no origin/HEAD)" || notok "PR line: $(grep ^PR= <<<"$out")"
    # origin/HEAD names the default branch when present.
    g -C "$r" update-ref refs/remotes/origin/develop main
    g -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
    out=$(cd "$r" && python3 "$TOOL" --local)
    grep -qx 'PR=local:origin/develop..HEAD' <<<"$out" &&
        ok "default branch resolved from refs/remotes/origin/HEAD" || notok "origin/HEAD ignored: $(grep ^PR= <<<"$out")"
else notok "could not build indep repo"; fi

if r=$(new_repo correction); then
    commit_file "$r" a.py "feat(a): add a"
    commit_file "$r" a.py "fix(a): correct a"
    local_expect "$r" squash in_pr_correction "fix of in-branch work"
else notok "could not build correction repo"; fi

if r=$(new_repo single); then
    commit_file "$r" a.py "feat(a): add a"
    local_expect "$r" squash single_commit "single commit"
else notok "could not build single repo"; fi

if r=$(new_repo range); then
    commit_file "$r" a.py "feat(a): add a"
    mid=$(g -C "$r" rev-parse HEAD)
    commit_file "$r" b.py "fix(b): repair b"
    # Only the last commit is in mid..HEAD: a single commit, not the pair.
    local_expect "$r" squash single_commit "explicit BASE..HEAD range" "$mid..HEAD"
    out=$(cd "$r" && python3 "$TOOL" --local "$mid..HEAD")
    grep -qx 'COMMITS=1' <<<"$out" && ok "explicit range counts only its commits" || notok "range COMMITS: $out"
    rc=0
    out=$(cd "$r" && python3 "$TOOL" --local HEAD..HEAD) || rc=$?
    [ "$rc" -eq 1 ] && grep -qx 'STATUS=ERROR' <<<"$out" &&
        ok "empty local range -> STATUS=ERROR" || notok "empty range rc=$rc: $out"
else notok "could not build range repo"; fi

rc=0
err=$(python3 "$TOOL" --local --fixture "$FX/pr-2940.json" 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 2 ] && grep -q 'not allowed with' <<<"$err" &&
    ok "--local and --fixture are mutually exclusive" || notok "--local + --fixture rc=$rc: $err"
python3 "$TOOL" --help | grep -q -- '--local' && ok "--help documents --local" || notok "--help lacks --local"

echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]
