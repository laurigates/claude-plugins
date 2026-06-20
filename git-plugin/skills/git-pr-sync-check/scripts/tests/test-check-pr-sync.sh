#!/usr/bin/env bash
# Regression tests for check-pr-sync.sh
#
# Run: bash git-plugin/skills/git-pr-sync-check/scripts/tests/test-check-pr-sync.sh
# Exit 0 = all pass, Exit 1 = failures. gh is mocked.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-pr-sync.sh"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
MOCK_BIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR" "$MOCK_BIN"' EXIT

# Feature branch tracking a real bare origin.
git -C "$TMPDIR" init -q
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config user.email t@t; git -C "$TMPDIR" config user.name T
git -C "$TMPDIR" commit --allow-empty -m init -q
git -C "$TMPDIR" branch -m main 2>/dev/null || git -C "$TMPDIR" checkout -b main -q
git -C "$TMPDIR" checkout -b feature -q
git -C "$TMPDIR" commit --allow-empty -m "feat: work" -q
ORIGIN="$TMPDIR/o.git"; git init -q --bare "$ORIGIN"
git -C "$TMPDIR" remote add origin "$ORIGIN"
git -C "$TMPDIR" push -q origin main feature
git -C "$TMPDIR" remote set-head origin main 2>/dev/null || \
    git -C "$TMPDIR" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "$TMPDIR" fetch -q origin

cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    [ -n "${MOCK_PR_JSON:-}" ] && printf '%s' "$MOCK_PR_JSON"
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"

verdict_of() {
    PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="${MOCK_PR_JSON:-}" \
        bash "$SCRIPT" --project-dir "$TMPDIR" 2>/dev/null \
        | awk -F= '/^VERDICT=/{print $2}'
}

assert_verdict() {
    local desc="$1" expected="$2" got
    got=$(verdict_of)
    if [ "$got" = "$expected" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
    fi
}

echo "=== check-pr-sync.sh tests ==="
echo ""

# no_remote: non-repo dir
echo "no_remote:"
got=$(bash "$SCRIPT" --project-dir /tmp 2>/dev/null | awk -F= '/^VERDICT=/{print $2}')
if [ "$got" = "no_remote" ]; then printf "  PASS: non-repo dir → no_remote\n"; PASS=$((PASS+1)); else printf "  FAIL: non-repo dir (got %s)\n" "$got"; FAIL=$((FAIL+1)); fi

# no_pr: open PR absent → no_pr (in sync, no PR)
echo ""
echo "verdicts on the feature branch:"
MOCK_PR_JSON=""
assert_verdict "no PR found + in sync → no_pr" no_pr

MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,reviewDecision:"REVIEW_REQUIRED",url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "open PR + in sync → in_sync" in_sync

MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",reviewDecision:"APPROVED",url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "merged PR → pr_merged" pr_merged

MOCK_PR_JSON=$(jq -n '{number:7,state:"CLOSED",mergedAt:null,reviewDecision:null,url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "closed PR → pr_closed" pr_closed

MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,reviewDecision:"CHANGES_REQUESTED",url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "open PR + changes requested → changes_requested" changes_requested

# behind: push drift to origin/feature from a second clone
echo ""
echo "behind upstream:"
CLONE2=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }; git clone -q "$ORIGIN" "$CLONE2" 2>/dev/null
git -C "$CLONE2" config user.email o@o; git -C "$CLONE2" config user.name O
git -C "$CLONE2" checkout -q feature 2>/dev/null || git -C "$CLONE2" checkout -q -b feature origin/feature
git -C "$CLONE2" commit --allow-empty -m "other: drift" -q
git -C "$CLONE2" push -q origin feature
MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,reviewDecision:"REVIEW_REQUIRED",url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "behind origin (open PR) → behind" behind
# Merged takes precedence over behind
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",reviewDecision:"APPROVED",url:"https://x/7",statusCheckRollup:[]}')
assert_verdict "merged precedence over behind → pr_merged" pr_merged
rm -rf "$CLONE2"

# CI roll-up key is surfaced
echo ""
echo "CI roll-up key:"
MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,reviewDecision:"REVIEW_REQUIRED",url:"https://x/7",statusCheckRollup:[{conclusion:"FAILURE",status:"COMPLETED"}]}')
ci=$(PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" bash "$SCRIPT" --project-dir "$TMPDIR" 2>/dev/null | awk -F= '/^CI_STATUS=/{print $2}')
if [ "$ci" = "FAILING" ]; then printf "  PASS: failing check → CI_STATUS=FAILING\n"; PASS=$((PASS+1)); else printf "  FAIL: CI_STATUS (got %s)\n" "$ci"; FAIL=$((FAIL+1)); fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
