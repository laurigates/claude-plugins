#!/usr/bin/env bash
# Regression test for scripts/assert-pr-comment-delivered.sh (#2630 Rec 1, #2719).
#
# Two Claude workflows whose ONLY deliverable is a PR comment ran green while
# posting nothing: release-pr-doc-audit.yml on every release PR since
# 2026-09-01, and the Claude Skill Quality Review step on 7 of 8 recent
# SKILL.md PRs. The helper is the post-step gate that turns that silence into a
# failed step. This suite EXECUTES it against a stub `gh` on PATH that applies
# the helper's own `--jq` expression to fixture pages, so the endpoint, the
# pagination flag and the jq projection are all exercised — not retyped.
#
# Cases replay the observed shapes:
#   A. #2664 — only a github-actions[bot] comment and a claude[bot] comment from
#      BEFORE the step started → not delivered (exit 1)
#   B. #2709 — three claude[bot] inline review comments → delivered
#   C. the approval path — one claude[bot] issue comment → delivered
#   D. release audit — a heading-carrying comment from a PREVIOUS run on the
#      same (force-pushed) release PR must not satisfy this run; a fresh one does
#   E. heading and author filters narrow, they do not widen
#   F. an unreadable API is ERROR/exit 2, never DELIVERED=true
#   G. usage errors exit 2 and emit no verdict
#   H. pagination: a match on page 2 counts
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
helper="$repo_root/scripts/assert-pr-comment-delivered.sh"

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
lacks() { grep -qF -- "$2" <<<"$1" && echo false || echo true; }

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

# Stub gh: logs argv, then applies the `--jq` expression it was given to each
# fixture page for the requested endpoint, exactly as `gh api --paginate --jq`
# applies it per page. STUB_FAIL makes every call fail like an auth/network
# error. The sentinel file proves the stub — not a real gh — answered.
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
  */issues/*/comments*) pages="$STUB_ISSUE_PAGES" ;;
  */pulls/*/comments*)  pages="$STUB_REVIEW_PAGES" ;;
  *) echo "stub: unexpected endpoint $endpoint" >&2; exit 3 ;;
esac
for page in $pages; do
  jq -r "$expr" "$page"
done
STUB
chmod +x "$work/bin/gh"

SINCE=1790000000                       # the step's recorded start (epoch)
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
BEFORE=$(iso $((SINCE - 600)))         # ten minutes before the step started
AFTER=$(iso $((SINCE + 30)))           # during the step
AT=$(iso "$SINCE")                     # exactly at the boundary

page() { # page <file> <json-array>
  printf '%s\n' "$2" > "$work/$1"
  echo "$work/$1"
}
EMPTY=$(page empty.json '[]')

run() { # run <issue-pages> <review-pages> <args...>
  local ip="$1" rp="$2"; shift 2
  : > "$work/gh.log"; rm -f "$work/sentinel"
  OUT=$(PATH="$work/bin:$PATH" STUB_LOG="$work/gh.log" STUB_SENTINEL="$work/sentinel" \
        STUB_ISSUE_PAGES="$ip" STUB_REVIEW_PAGES="$rp" STUB_FAIL="${STUB_FAIL:-}" \
        bash "$helper" "$@" 2>&1)
  RC=$?
  LOG=$(cat "$work/gh.log")
}

REVIEW_ARGS=(--repo o/r --pr 2664 --since "$SINCE" --author 'claude[bot]' --include-review-comments)
AUDIT_ARGS=(--repo o/r --pr 2710 --since "$SINCE" --heading '## Release Documentation Audit')

echo "=== TEST A: #2664 shape — nothing delivered during the step ==="
A_ISSUES=$(page a-issues.json "[
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"github-actions[bot]\"},\"body\":\"## Plugin Compliance Review\n\n| Plugin |\"},
  {\"created_at\":\"$BEFORE\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"503 diagnosis from the auto-fix run\"}
]")
run "$A_ISSUES" "$EMPTY" "${REVIEW_ARGS[@]}"
assert "A: stub answered (sentinel written)" "$([ -f "$work/sentinel" ] && echo true || echo false)"
assert "A: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "A: DELIVERED=false" "$(has_line "$OUT" 'DELIVERED=false')"
assert "A: both issue comments were scanned (non-vacuous)" "$(has_line "$OUT" 'ISSUE_COMMENTS_SCANNED=2')"
assert "A: none matched" "$(has_line "$OUT" 'ISSUE_COMMENTS_MATCHED=0')"
assert "A: TYPE=deliverable_missing" "$(grep -qF 'TYPE=deliverable_missing' <<<"$OUT" && echo true || echo false)"
assert "A: STATUS=ERROR" "$(has_line "$OUT" 'STATUS=ERROR')"
assert "A: paginated issue-comments endpoint queried" "$(grep -qF -- '--paginate repos/o/r/issues/2664/comments' <<<"$LOG" && echo true || echo false)"
assert "A: review-comments endpoint queried" "$(grep -qF 'repos/o/r/pulls/2664/comments' <<<"$LOG" && echo true || echo false)"

echo "=== TEST B: #2709 shape — inline review comments delivered ==="
B_REVIEWS=$(page b-reviews.json "[
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"**Description length: ~233 chars — WARN band.**\"},
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"When to Use carries no decision table.\"},
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"This Sibling: pointer names no skill.\"}
]")
run "$A_ISSUES" "$B_REVIEWS" "${REVIEW_ARGS[@]}"
assert "B: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "B: DELIVERED=true" "$(has_line "$OUT" 'DELIVERED=true')"
assert "B: three review comments matched" "$(has_line "$OUT" 'REVIEW_COMMENTS_MATCHED=3')"
assert "B: STATUS=OK" "$(has_line "$OUT" 'STATUS=OK')"

echo "=== TEST C: approval comment path ==="
C_ISSUES=$(page c-issues.json "[
  {\"created_at\":\"$AT\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"## Skill Quality Review\n\nAll changed skills pass.\"}
]")
run "$C_ISSUES" "$EMPTY" "${REVIEW_ARGS[@]}"
assert "C: a comment exactly at the boundary counts (exit 0)" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "C: ISSUE_COMMENTS_MATCHED=1" "$(has_line "$OUT" 'ISSUE_COMMENTS_MATCHED=1')"

echo "=== TEST D: release audit — a previous run's comment does not count ==="
D_STALE=$(page d-stale.json "[
  {\"created_at\":\"$BEFORE\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"## Release Documentation Audit\n\n| Check |\"}
]")
run "$D_STALE" "$EMPTY" "${AUDIT_ARGS[@]}"
assert "D1: stale heading comment only → exit 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "D1: DELIVERED=false" "$(has_line "$OUT" 'DELIVERED=false')"
assert "D1: review comments not queried without the flag" "$(lacks "$LOG" 'pulls/')"
assert "D1: REVIEW_COMMENTS_MATCHED reported as skipped" "$(has_line "$OUT" 'REVIEW_COMMENTS_MATCHED=skipped')"
D_FRESH=$(page d-fresh.json "[
  {\"created_at\":\"$BEFORE\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"## Release Documentation Audit\n\nold\"},
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"\`\`\`\n  ## Release Documentation Audit\n\n| Check | Status |\"}
]")
run "$D_FRESH" "$EMPTY" "${AUDIT_ARGS[@]}"
assert "D2: a fresh heading comment (indented, inside a fence) counts" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "D2: exactly the fresh one matched" "$(has_line "$OUT" 'ISSUE_COMMENTS_MATCHED=1')"

echo "=== TEST E: filters narrow, never widen ==="
E_ISSUES=$(page e-issues.json "[
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"github-actions[bot]\"},\"body\":\"## Plugin Compliance Review\"},
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"someone\"},\"body\":\"Mentions ## Release Documentation Audit mid-line\"}
]")
run "$E_ISSUES" "$EMPTY" "${AUDIT_ARGS[@]}"
assert "E1: heading must start a line (mid-line mention does not count)" "$([ "$RC" -eq 1 ] && echo true || echo false)"
E_OTHER=$(page e-other.json "[
  {\"created_at\":\"$AFTER\",\"user\":{\"login\":\"someone\"},\"body\":\"LGTM\"}
]")
run "$E_OTHER" "$EMPTY" "${REVIEW_ARGS[@]}"
assert "E2: a comment by another author does not satisfy --author" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "E2: it was scanned" "$(has_line "$OUT" 'ISSUE_COMMENTS_SCANNED=1')"

echo "=== TEST F: unreadable API is ERROR, never a verdict ==="
STUB_FAIL=1 run "$C_ISSUES" "$EMPTY" "${REVIEW_ARGS[@]}"
assert "F: exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "F: TYPE=api_unreadable" "$(grep -qF 'TYPE=api_unreadable' <<<"$OUT" && echo true || echo false)"
assert "F: never DELIVERED=true" "$(lacks "$OUT" 'DELIVERED=true')"
assert "F: DELIVERED=unknown" "$(has_line "$OUT" 'DELIVERED=unknown')"

echo "=== TEST G: usage errors exit 2 and emit no verdict ==="
run "$EMPTY" "$EMPTY" --repo o/r --since "$SINCE"
assert "G1: missing --pr exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G1: no verdict emitted" "$(lacks "$OUT" 'DELIVERED=')"
run "$EMPTY" "$EMPTY" --repo o/r --pr 1 --since yesterday
assert "G2: non-numeric --since exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
run "$EMPTY" "$EMPTY" --repo o/r --pr 1 --since "$SINCE" --strict
assert "G3: unknown argument exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G3: names the argument" "$(grep -qF 'unknown argument: --strict' <<<"$OUT" && echo true || echo false)"
run "$EMPTY" "$EMPTY" --repo 'not a repo' --pr 1 --since "$SINCE"
assert "G4: malformed --repo exits 2" "$([ "$RC" -eq 2 ] && echo true || echo false)"
assert "G4: no API call made on a usage error" "$([ -z "$LOG" ] && echo true || echo false)"

echo "=== TEST H: pagination — a match on page 2 counts ==="
H_P1=$(page h-p1.json "[{\"created_at\":\"$AFTER\",\"user\":{\"login\":\"github-actions[bot]\"},\"body\":\"compliance\"}]")
H_P2=$(page h-p2.json "[{\"created_at\":\"$AFTER\",\"user\":{\"login\":\"claude[bot]\"},\"body\":\"## Skill Quality Review\"}]")
run "$H_P1 $H_P2" "$EMPTY" "${REVIEW_ARGS[@]}"
assert "H: exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "H: both pages scanned" "$(has_line "$OUT" 'ISSUE_COMMENTS_SCANNED=2')"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
