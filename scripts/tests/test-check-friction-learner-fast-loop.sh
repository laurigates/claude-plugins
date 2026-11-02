#!/usr/bin/env bash
# Regression test for scripts/check-friction-learner-fast-loop.sh (issue #3346).
#
# friction-learner's Step 0 fetched only `--label session-feedback`, while
# `/feedback:session` files positive findings under `positive-feedback` alone,
# so most positive feedback was read by nothing. The guard pins the second
# fetch and its use as stability markers.
#
# Guards:
#   A. the real agent file passes
#   B. a compliant fixture exits 0 with STATUS=OK
#   C. a fixture with only the session-feedback fetch fails (the #3346 shape)
#   D. a combined `--label session-feedback,positive-feedback` fetch fails
#      (gh matches only issues carrying BOTH labels)
#   E. a positive-feedback fetch without --json fails (bare list exits 1 on empty)
#   F. a positive-feedback command mentioned only in prose (outside a fence) fails
#   G. Step 3 without the stability-marker handling fails
#   H. Step 5 without the positive listing fails
#   I. an unknown argument and a missing file exit 2
#   J. failing and passing outputs satisfy the structured-output contract
#   K. an open-only positive fetch fails (closure policy: cited issues are
#      closed, so open-only stops seeing them; #3346 decision 1)
#   L. an any-state positive fetch with no date window fails
#   M. Step 6 with no close-after-cite command fails; a close with no
#      --comment fails too
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-friction-learner-fast-loop.sh"
contract="$repo_root/scripts/check-structured-output-contract.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { grep -q -- "$2" <<<"$1" && echo true || echo false; }
lacks() { grep -q -- "$2" <<<"$1" && echo false || echo true; }
validates() {
  printf '%s\n' "$1" | bash "$contract" --validate >/dev/null 2>&1 && echo true || echo false
}

tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 2; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then echo "mktemp returned no directory" >&2; exit 2; fi
trap 'rm -rf "$tmp_root"' EXIT

FENCE='```'

# make_agent <file> <step0-commands> <step3-body> <step5-body> [<step6-body>]
make_agent() {
  local step6="${5:-$GOOD_STEP6}"
  cat >"$1" <<EOF
---
name: friction-learner
---

# Friction Learner

## Workflow

### Step 0: Read fast-loop signal

$2

### Step 1: Enumerate

Parse transcripts.

### Step 3: Propose a fix per cluster

$3

### Step 5: Render

$4

### Step 6: Open PRs

$step6

### Step 7: Report

Done.
EOF
}

GOOD_STEP0="${FENCE}bash
gh issue list -R \"\$TARGET_REPO\" --state open --label session-feedback \\
  --limit 100 --json number,title,labels,body
${FENCE}

${FENCE}bash
gh issue list -R \"\$TARGET_REPO\" --state all --label positive-feedback \\
  --search \"created:>=\$SINCE\" \\
  --limit 200 --json number,title,state,labels,body
${FENCE}"
GOOD_STEP6="Close each cited positive-feedback issue.

${FENCE}bash
gh issue close \"\$N\" --reason completed --comment \"Cited in \$PR_URL\"
${FENCE}"
GOOD_STEP3="Each open positive-feedback issue is a stability marker; name it as Preserves #<n>."
GOOD_STEP5="List each positive-feedback issue in the ## Fast-loop signal section."

run() { out="$(bash "$checker" "$@" 2>&1)"; rc=$?; }

# A. real repo
run --project-dir "$repo_root"
assert "A: real agent file passes (rc=$rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "A: real agent STATUS=OK" "$(contains "$out" '^STATUS=OK$')"

# B. compliant fixture
f="$tmp_root/good.md"; make_agent "$f" "$GOOD_STEP0" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "B: compliant fixture exits 0 (rc=$rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "B: contract validates" "$(validates "$out")"

# C. session-feedback only (the pre-fix shape)
f="$tmp_root/c.md"
make_agent "$f" "${FENCE}bash
gh issue list --state open --label session-feedback --limit 100 --json number,title
${FENCE}" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "C: missing positive fetch exits 1 (rc=$rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "C: names missing_positive_feedback_fetch" "$(contains "$out" 'TYPE=missing_positive_feedback_fetch')"
assert "C: session fetch still recognised" "$(lacks "$out" 'missing_session_feedback_fetch')"
assert "C: contract validates" "$(validates "$out")"

# D. combined label (AND semantics)
f="$tmp_root/d.md"
make_agent "$f" "${FENCE}bash
gh issue list --state open --label session-feedback,positive-feedback --json number
${FENCE}" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "D: combined --label a,b fails (rc=$rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "D: both fetches reported missing" "$( [ "$(contains "$out" 'TYPE=missing_session_feedback_fetch')" = true ] && [ "$(contains "$out" 'TYPE=missing_positive_feedback_fetch')" = true ] && echo true || echo false)"

# E. no --json on the positive fetch
f="$tmp_root/e.md"
make_agent "$f" "${FENCE}bash
gh issue list --state open --label session-feedback --json number
gh issue list --state open --label positive-feedback
${FENCE}" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "E: positive fetch without --json fails" "$(contains "$out" 'TYPE=missing_positive_feedback_fetch')"

# F. prose mention only
f="$tmp_root/f.md"
make_agent "$f" "${FENCE}bash
gh issue list --state open --label session-feedback --json number
${FENCE}

Also run gh issue list --label positive-feedback --json number when you remember." "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "F: prose-only positive fetch fails" "$(contains "$out" 'TYPE=missing_positive_feedback_fetch')"

# G. Step 3 lost the stability-marker handling
f="$tmp_root/g.md"; make_agent "$f" "$GOOD_STEP0" "Cross-reference clusters against session-feedback." "$GOOD_STEP5"
run --file "$f"
assert "G: Step 3 without stability markers fails (rc=$rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "G: names step3_no_stability_marker" "$(contains "$out" 'TYPE=step3_no_stability_marker')"
assert "G: contract validates" "$(validates "$out")"

# H. Step 5 lost the positive listing
f="$tmp_root/h.md"; make_agent "$f" "$GOOD_STEP0" "$GOOD_STEP3" "List session-feedback issues in ## Fast-loop signal."
run --file "$f"
assert "H: names step5_no_positive_listing" "$(contains "$out" 'TYPE=step5_no_positive_listing')"

# I. usage errors
run --bogus
assert "I: unknown argument exits 2 (rc=$rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run --file "$tmp_root/does-not-exist.md"
assert "I: missing file exits 2 (rc=$rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"

SESSION_FETCH="${FENCE}bash
gh issue list --state open --label session-feedback --json number
${FENCE}"

# K. open-only positive fetch (the first-commit shape before the closure policy)
f="$tmp_root/k.md"
make_agent "$f" "$SESSION_FETCH

${FENCE}bash
gh issue list --state open --label positive-feedback --search \"created:>=\$SINCE\" --json number
${FENCE}" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "K: open-only positive fetch exits 1 (rc=$rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "K: names positive_fetch_not_any_state" "$(contains "$out" 'TYPE=positive_fetch_not_any_state')"
assert "K: window still recognised" "$(lacks "$out" 'positive_fetch_no_window')"
assert "K: contract validates" "$(validates "$out")"

# L. any state, no window
f="$tmp_root/l.md"
make_agent "$f" "$SESSION_FETCH

${FENCE}bash
gh issue list --state all --label positive-feedback --limit 200 --json number,state
${FENCE}" "$GOOD_STEP3" "$GOOD_STEP5"
run --file "$f"
assert "L: names positive_fetch_no_window" "$(contains "$out" 'TYPE=positive_fetch_no_window')"
assert "L: any-state still recognised" "$(lacks "$out" 'positive_fetch_not_any_state')"

# M. Step 6 without close-after-cite, and a close with no comment
f="$tmp_root/m.md"; make_agent "$f" "$GOOD_STEP0" "$GOOD_STEP3" "$GOOD_STEP5" "Open the PR."
run --file "$f"
assert "M: Step 6 without close exits 1 (rc=$rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "M: names step6_no_close_after_cite" "$(contains "$out" 'TYPE=step6_no_close_after_cite')"
f="$tmp_root/m2.md"; make_agent "$f" "$GOOD_STEP0" "$GOOD_STEP3" "$GOOD_STEP5" "Close each cited positive-feedback issue.

${FENCE}bash
gh issue close \"\$N\" --reason completed
${FENCE}"
run --file "$f"
assert "M: close without --comment fails" "$(contains "$out" 'TYPE=step6_no_close_after_cite')"

echo "=== TEST CHECK FRICTION LEARNER FAST LOOP ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  exit 1
fi
echo "STATUS=OK"
exit 0
