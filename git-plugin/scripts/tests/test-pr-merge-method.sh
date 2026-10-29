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
expect pr-3132 squash in_pr_correction   # same-scope fix, half its files already changed
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

echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ]
