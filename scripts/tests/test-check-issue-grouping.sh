#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `[ -n ] && [ -d ] || die` is a guard, not if-then-else (must precede the first command)
# Regression tests for scripts/check-issue-grouping.sh.
#
# Hermetic: a stub `gh` on PATH serves fixture pages of the REST
# `repos/{o}/{r}/issues` listing by their `page=N` parameter, so the real fetch
# loop (manual pagination, PR filtering, the exempt list) runs with no network.
#
# Both directions are covered. Every shape that must NOT be reported (sub-issue,
# milestone member, pull request, epic, exempt label, exempt title) sits beside
# one that must, so a check that reports nothing and a check that reports
# everything both fail.
#
# Run: bash scripts/tests/test-check-issue-grouping.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$SCRIPT_DIR/check-issue-grouping.sh"
CONTRACT="$SCRIPT_DIR/check-structured-output-contract.sh"
REAL_EXEMPT="$SCRIPT_DIR/issue-grouping-exempt.txt"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
WORK=$(cd -P -- "$WORK" && pwd -P) || { echo "cannot resolve sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

assert_eq() {
  local desc="$1" expected="$2" got="$3"
  if [ "$got" = "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}
reported() { grep -cE "^  - SEVERITY=WARN TYPE=ungrouped_issue ISSUE=$1 " <<<"$2"; }
key() { grep -E "^$1=" <<<"$2" | cut -d= -f2-; }
validates() { bash "$CONTRACT" --validate - <<<"$1" >/dev/null 2>&1; echo $?; }

# --- stub gh: `gh api 'repos/o/r/issues?...&page=N'` -> $STUB_DIR/page-N.json ---
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "api" ] || { echo "stub gh: unexpected call: $*" >&2; exit 64; }
if [ -n "${STUB_FAIL:-}" ]; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
page="$(printf '%s' "$2" | sed -nE 's/.*[?&]page=([0-9]+).*/\1/p')"
f="$STUB_DIR/page-$page.json"
if [ -f "$f" ]; then cat "$f"; else echo "[]"; fi
STUB
chmod +x "$WORK/bin/gh"
[ -x "$WORK/bin/gh" ] || { echo "stub gh is not executable" >&2; exit 1; }
[ "$(PATH="$WORK/bin:$PATH" command -v gh)" = "$WORK/bin/gh" ] || { echo "stub gh does not shadow the real one" >&2; exit 1; }

run_check() {
  # run_check STUB_DIR [extra args...] -> report on stdout; exit code in $RC
  local dir="$1"; shift
  OUT="$(PATH="$WORK/bin:$PATH" STUB_DIR="$dir" bash "$CHECK" --repo o/r "$@" 2>&1)"; RC=$?
}

# --- fixture: page 1 is a full page of 100 grouped issues, so the loop must
#     fetch page 2 to see the shapes under test. ---
mixed="$WORK/mixed"; mkdir -p "$mixed"
jq -n '[range(1000; 1100) | {number: ., title: "grouped \(.)", labels: [],
        parent_issue_url: "https://api.github.com/repos/o/r/issues/1"}]' > "$mixed/page-1.json"
cat > "$mixed/page-2.json" <<'JSON'
[
  {"number": 10, "title": "ungrouped bug", "labels": [{"name": "bug"}]},
  {"number": 11, "title": "sub-issue of an epic", "labels": [{"name": "bug"}],
   "parent_issue_url": "https://api.github.com/repos/o/r/issues/1"},
  {"number": 12, "title": "milestone member", "labels": [], "milestone": {"number": 3, "title": "v2"}},
  {"number": 13, "title": "an open pull request", "labels": [], "pull_request": {"url": "x"}},
  {"number": 1,  "title": "the tracking issue", "labels": [{"name": "epic"}]},
  {"number": 14, "title": "Research radar W44", "labels": [{"name": "research-radar"}]},
  {"number": 15, "title": "Dependency Dashboard", "labels": []},
  {"number": 16, "title": "second ungrouped chore", "labels": [{"name": "chore"}],
   "parent_issue_url": null, "milestone": null}
]
JSON

echo "=== check-issue-grouping regression tests ==="

run_check "$mixed"
assert_eq "findings exit 0 (advisory)" "0" "$RC"
assert_eq "findings report STATUS=WARN" "WARN" "$(key STATUS "$OUT")"
assert_eq "both ungrouped issues are counted" "2" "$(key ISSUE_COUNT "$OUT")"
assert_eq "UNGROUPED= matches ISSUE_COUNT=" "2" "$(key UNGROUPED "$OUT")"
assert_eq "page 2 was fetched (pagination): ISSUES_FETCHED excludes only the PR" "107" "$(key ISSUES_FETCHED "$OUT")"
assert_eq "ungrouped issue #10 is reported" "1" "$(reported 10 "$OUT")"
assert_eq "explicit-null parent and milestone #16 is reported" "1" "$(reported 16 "$OUT")"
assert_eq "sub-issue #11 is not reported" "0" "$(reported 11 "$OUT")"
assert_eq "milestone member #12 is not reported" "0" "$(reported 12 "$OUT")"
assert_eq "pull request #13 is not reported" "0" "$(reported 13 "$OUT")"
assert_eq "epic #1 is not reported" "0" "$(reported 1 "$OUT")"
assert_eq "exempt-label issue #14 is not reported" "0" "$(reported 14 "$OUT")"
assert_eq "exempt-title issue #15 is not reported" "0" "$(reported 15 "$OUT")"
assert_eq "page-1 sub-issues are not reported" "0" "$(grep -cE 'ISSUE=10[0-9][0-9] ' <<<"$OUT")"
assert_eq "EPICS= counts the tracking issue" "1" "$(key EPICS "$OUT")"
assert_eq "REASON= opens with the first finding's TYPE and number" "1" \
  "$(grep -c '^REASON=ungrouped_issue: #10 ungrouped bug (+1 more)$' <<<"$OUT")"
assert_eq "WARN output satisfies the structured-output contract" "0" "$(validates "$OUT")"

# The exempt list is read from the file, not hardcoded: drop research-radar
# from a copy and #14 becomes reported.
grep -v '^label research-radar$' "$REAL_EXEMPT" > "$WORK/exempt-no-radar.txt"
run_check "$mixed" --exempt-file "$WORK/exempt-no-radar.txt"
assert_eq "an issue whose label leaves the exempt file is reported" "1" "$(reported 14 "$OUT")"

# The shipped exempt file covers the recurring types named in #3346.
for lbl in research-radar positive-feedback session-feedback config-drift golden-set-eval changelog-review stranded-work fleet-drift agentic-audit epic; do
  assert_eq "shipped exempt list carries '$lbl'" "1" "$(grep -cx "label $lbl" "$REAL_EXEMPT")"
done

# Clean tree: everything grouped or exempt.
clean="$WORK/clean"; mkdir -p "$clean"
cat > "$clean/page-1.json" <<'JSON'
[
  {"number": 1, "title": "the tracking issue", "labels": [{"name": "epic"}]},
  {"number": 2, "title": "member", "labels": [], "parent_issue_url": "https://api.github.com/repos/o/r/issues/1"}
]
JSON
run_check "$clean"
assert_eq "clean tree exits 0" "0" "$RC"
assert_eq "clean tree reports STATUS=OK" "OK" "$(key STATUS "$OUT")"
assert_eq "clean tree reports ISSUE_COUNT=0" "0" "$(key ISSUE_COUNT "$OUT")"
assert_eq "clean tree carries no REASON=" "0" "$(grep -c '^REASON=' <<<"$OUT")"
assert_eq "OK output satisfies the structured-output contract" "0" "$(validates "$OUT")"

# Fetch failure is ERROR, never an empty OK.
OUT="$(PATH="$WORK/bin:$PATH" STUB_DIR="$clean" STUB_FAIL=1 bash "$CHECK" --repo o/r 2>&1)"; RC=$?
assert_eq "fetch failure exits 1" "1" "$RC"
assert_eq "fetch failure reports STATUS=ERROR" "ERROR" "$(key STATUS "$OUT")"
assert_eq "fetch failure names its TYPE" "1" "$(grep -c '^REASON=fetch_failed: ' <<<"$OUT")"
assert_eq "ERROR output satisfies the structured-output contract" "0" "$(validates "$OUT")"

# A non-JSON page is a fetch failure too, not zero issues.
bad="$WORK/bad"; mkdir -p "$bad"; printf '<html>rate limited</html>\n' > "$bad/page-1.json"
run_check "$bad"
assert_eq "non-JSON page reports STATUS=ERROR" "ERROR" "$(key STATUS "$OUT")"

# GH_REPO is honoured when --repo is absent.
OUT="$(PATH="$WORK/bin:$PATH" STUB_DIR="$clean" GH_REPO=o/r bash "$CHECK" 2>&1)"
assert_eq "GH_REPO sets REPO=" "o/r" "$(key REPO "$OUT")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
