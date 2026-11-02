#!/usr/bin/env bash
# Regression test for scripts/assert-issue-filed.sh (#2731).
#
# Three Claude workflows file a GitHub issue as their ONLY deliverable
# (golden-set-evaluation.yml, scheduled-audits.yml agentic-audit,
# workflow-model-audit.yml), and the SDK exits 0 on a denied `gh issue create`,
# so a run that files nothing is green: workflow-model-audit.yml filed nothing
# in six runs before #2630, and the 2026-08-15 golden-set run filed nothing
# after 7 denials. The helper is the same-run post-step gate. This suite
# EXECUTES it against a stub `gh` on PATH that applies the helper's own `--jq`
# expression to fixture pages, so the endpoint, the label query, the pagination
# flag and the jq projection are all exercised — not retyped.
#
# Cases:
#   A. an issue with the label created during the run → filed (exit 0)
#   B. no issue at all → not filed (exit 1)
#   C. the only labelled issue predates the run (last month's report) → exit 1
#   D. a pull request returned by the issues endpoint does not count
#   E. --title-prefix narrows: another chore under the shared label does not count
#   F. an unreadable API is ERROR/exit 2, never FILED=true
#   G. usage errors exit 2 and make no API call
#   H. pagination: a match on page 2 counts
#   I. an issue created exactly at --since counts (inclusive bound)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
helper="$repo_root/scripts/assert-issue-filed.sh"

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
has_line() { grep -qxF -- "$2" <<<"$1" && echo true || echo false; }
has() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
lacks() { grep -qF -- "$2" <<<"$1" && echo false || echo true; }

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

# Stub gh: logs argv, then applies the `--jq` expression it was given to each
# fixture page, exactly as `gh api --paginate --jq` applies it per page.
# STUB_FAIL makes every call fail like an auth/network error. The sentinel file
# proves the stub — not a real gh — answered.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
: > "$STUB_SENTINEL"
if [ -n "${STUB_FAIL:-}" ]; then
  echo "HTTP 401: Bad credentials (https://api.github.com/)" >&2
  exit 1
fi
expr=""; endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) expr="$2"; shift 2 ;;
    api|--paginate) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done
case "$endpoint" in
  repos/*/issues\?*) ;;
  *) echo "stub: unexpected endpoint $endpoint" >&2; exit 3 ;;
esac
for page in $STUB_PAGES; do
  jq -r "$expr" "$page"
done
STUB
chmod +x "$work/bin/gh"

SINCE=1790000000                       # the recorded start of the Claude step
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
BEFORE=$(iso $((SINCE - 2592000)))     # thirty days earlier: last month's run
AFTER=$(iso $((SINCE + 1200)))         # twenty minutes into the step
AT=$(iso "$SINCE")

page() { # page <file> <json-array>
  printf '%s\n' "$2" > "$work/$1"
  echo "$work/$1"
}
EMPTY=$(page empty.json '[]')

run() { # run <pages> <args...>
  local pages="$1"; shift
  : > "$work/gh.log"; rm -f "$work/sentinel"
  OUT=$(PATH="$work/bin:$PATH" STUB_LOG="$work/gh.log" STUB_SENTINEL="$work/sentinel" \
        STUB_PAGES="$pages" STUB_FAIL="${STUB_FAIL:-}" \
        bash "$helper" "$@" 2>&1)
  RC=$?
  LOG=$(cat "$work/gh.log")
}

ARGS=(--repo o/r --label workflow-model-audit --since "$SINCE")

echo "=== TEST A: an issue filed during the run ==="
A=$(page a.json "[
  {\"number\":3001,\"created_at\":\"$AFTER\",\"title\":\"Workflow model audit: 2026-11\"}
]")
run "$A" "${ARGS[@]}"
assert "A: stub answered (sentinel written)" "$([ -f "$work/sentinel" ] && echo true || echo false)"
assert "A: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "A: FILED=true" "$(has_line "$OUT" 'FILED=true')"
assert "A: STATUS=OK" "$(has_line "$OUT" 'STATUS=OK')"
assert "A: names the filed issue" "$(has_line "$OUT" 'FILED_ISSUES=3001')"
assert "A: no REASON= on the OK path" "$(grep -q '^REASON=' <<<"$OUT" && echo false || echo true)"
assert "A: ISSUE_COUNT=0" "$(has_line "$OUT" 'ISSUE_COUNT=0')"
assert "A: paginated issues endpoint filtered by label, all states" \
  "$(has "$LOG" '--paginate repos/o/r/issues?labels=workflow-model-audit&state=all')"

echo "=== TEST B: nothing filed ==="
run "$EMPTY" "${ARGS[@]}"
assert "B: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "B: FILED=false" "$(has_line "$OUT" 'FILED=false')"
assert "B: STATUS=ERROR" "$(has_line "$OUT" 'STATUS=ERROR')"
assert "B: TYPE=deliverable_missing" "$(has "$OUT" 'TYPE=deliverable_missing')"
assert "B: REASON= names the cause" "$(grep -qE '^REASON=deliverable_missing: .+' <<<"$OUT" && echo true || echo false)"
assert "B: ISSUE_COUNT=1" "$(has_line "$OUT" 'ISSUE_COUNT=1')"

echo "=== TEST C: last month's report does not satisfy this run ==="
C=$(page c.json "[
  {\"number\":2900,\"created_at\":\"$BEFORE\",\"title\":\"Workflow model audit: 2026-10\"}
]")
run "$C" "${ARGS[@]}"
assert "C: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "C: the old issue was scanned (non-vacuous)" "$(has_line "$OUT" 'ISSUES_SCANNED=1')"
assert "C: none matched" "$(has_line "$OUT" 'ISSUES_MATCHED=0')"

echo "=== TEST D: a pull request under the label does not count ==="
D=$(page d.json "[
  {\"number\":3002,\"created_at\":\"$AFTER\",\"title\":\"fix: something\",\"pull_request\":{\"url\":\"x\"}}
]")
run "$D" "${ARGS[@]}"
assert "D: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "D: FILED=false" "$(has_line "$OUT" 'FILED=false')"

echo "=== TEST E: --title-prefix narrows to this workflow's report ==="
E=$(page e.json "[
  {\"number\":3003,\"created_at\":\"$AFTER\",\"title\":\"Golden-set coverage gap: foo\"}
]")
run "$E" --repo o/r --label golden-set-eval --since "$SINCE" --title-prefix 'Golden-set cross-model sweep:'
assert "E: another chore under the label → exit 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "E: prefix filter reported" "$(has_line "$OUT" 'TITLE_PREFIX_FILTER=Golden-set cross-model sweep:')"
E2=$(page e2.json "[
  {\"number\":3003,\"created_at\":\"$AFTER\",\"title\":\"Golden-set coverage gap: foo\"},
  {\"number\":3004,\"created_at\":\"$AFTER\",\"title\":\"Golden-set cross-model sweep: 2026-11\"}
]")
run "$E2" --repo o/r --label golden-set-eval --since "$SINCE" --title-prefix 'Golden-set cross-model sweep:'
assert "E: the sweep report → exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "E: only the sweep report matched" "$(has_line "$OUT" 'FILED_ISSUES=3004')"

echo "=== TEST F: an unreadable API is never FILED=true ==="
STUB_FAIL=1 run "$A" "${ARGS[@]}"
assert "F: exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "F: FILED=unknown" "$(has_line "$OUT" 'FILED=unknown')"
assert "F: TYPE=api_unreadable" "$(has "$OUT" 'TYPE=api_unreadable')"
assert "F: never FILED=true" "$(lacks "$OUT" 'FILED=true')"

echo "=== TEST G: usage errors exit 2 and make no API call ==="
run "$A" --repo o/r --label workflow-model-audit
assert "G: missing --since exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G: no API call" "$([ -f "$work/sentinel" ] && echo false || echo true)"
run "$A" --repo o/r --label 'bad label&x=1' --since "$SINCE"
assert "G: unsafe label exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G: unsafe label makes no API call" "$([ -f "$work/sentinel" ] && echo false || echo true)"
run "$A" --repo o/r --label x --since "$SINCE" --bogus
assert "G: unknown argument exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G: emits no verdict" "$(lacks "$OUT" 'FILED=')"

echo "=== TEST H: a match on page 2 counts ==="
H1=$(page h1.json "[
  {\"number\":2800,\"created_at\":\"$BEFORE\",\"title\":\"Workflow model audit: 2026-09\"}
]")
H2=$(page h2.json "[
  {\"number\":3005,\"created_at\":\"$AFTER\",\"title\":\"Workflow model audit: 2026-11\"}
]")
run "$H1 $H2" "${ARGS[@]}"
assert "H: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "H: both pages scanned" "$(has_line "$OUT" 'ISSUES_SCANNED=2')"

echo "=== TEST I: the --since bound is inclusive ==="
I=$(page i.json "[
  {\"number\":3006,\"created_at\":\"$AT\",\"title\":\"Workflow model audit: 2026-11\"}
]")
run "$I" "${ARGS[@]}"
assert "I: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
