#!/usr/bin/env bash
# Regression test for scripts/publish-agent-issue.sh (#2769, #2720).
#
# The bug class: a Claude step that runs `gh issue create --label --assignee`
# itself can see a failure after the issue already exists (gh assigns in a
# second call and prints no URL when that call fails), retry, and file the
# issue twice. It can also report labels it never applied. The publisher moves
# the create into bash. This suite EXECUTES it against a stateful stub `gh` on
# PATH that keeps the repo's issues in a JSON file, applies the script's own
# `--jq` programs to that state, and can fail each call in the ways GitHub does.
#
# Cases:
#   A. no open issue with the title: created once, with no labels or assignee
#      on the create; labels and assignee applied afterwards and read back
#   B. an open, unlabelled issue with the exact title: reused, nothing created
#   C. the create call fails AFTER filing (response lost): the issue is adopted,
#      the create is not retried, one issue exists, STATUS=WARN
#   D. the create call fails and files nothing: ERROR, exactly one create call
#   E. a label that does not stick is an ERROR, read back from the issue
#   F. an assignee GitHub silently drops is a WARN, ASSIGNEES_APPLIED empty
#   G. a missing or blank body is an ERROR without --optional and a skip with
#      it, and neither makes an API call
#   H. --processing is appended to the published body; the agent's file is
#      left as written
#   I. only an exact, open, non-PR title match is reused
#   J. an unreadable issue listing is an ERROR and creates nothing
#   K. usage errors exit 2 and make no API call
#   L. GITHUB_OUTPUT receives action, number and url
#   M. every output block passes the structured-output contract validator
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
subject="$repo_root/scripts/publish-agent-issue.sh"
validator="$repo_root/scripts/check-structured-output-contract.sh"

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
eq() { [ "$1" = "$2" ] && echo true || echo false; }

for tool in jq python3; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

# Stateful stub gh. STUB_DB holds every issue (open, closed and PRs) as a JSON
# array. Failure knobs:
#   STUB_LIST_FAIL=1           the open-issue listing fails
#   STUB_CREATE=fail-before    the create fails and files nothing
#   STUB_CREATE=fail-after     the create files the issue, then fails
#   STUB_DROP_LABELS=1         the label call "succeeds" but adds nothing
#   STUB_DROP_ASSIGNEES=1      the assignee call succeeds and adds nobody (what
#                              GitHub does for a login that cannot be assigned)
# The sentinel proves the stub, not a real gh, answered.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
: > "$STUB_SENTINEL"
method=GET; input=""; expr=""; endpoint=""
while [ $# -gt 0 ]; do
  case "$1" in
    api|--paginate) shift ;;
    -X) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --jq) expr="$2"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
case "$method $endpoint" in
  "GET repos/"*"/issues?state=open"*)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    jq -c '[.[] | select(.state == "open")]' "$STUB_DB" | jq -r "$expr" ;;
  "POST repos/"*"/issues")
    [ "${STUB_CREATE:-}" = "fail-before" ] && { echo "HTTP 500: Internal Server Error" >&2; exit 1; }
    cp "$input" "$STUB_CREATE_PAYLOAD"
    n=$(jq '[.[].number] | max + 1' "$STUB_DB")
    jq --argjson n "$n" --slurpfile p "$input" \
      '. + [{number: $n, title: $p[0].title, body: $p[0].body, state: "open",
             html_url: "https://github.com/o/r/issues/\($n)", labels: [], assignees: []}]' \
      "$STUB_DB" > "$STUB_DB.tmp" && mv "$STUB_DB.tmp" "$STUB_DB"
    [ "${STUB_CREATE:-}" = "fail-after" ] && { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
    jq -c --argjson n "$n" '.[] | select(.number == $n)' "$STUB_DB" | jq -r "$expr" ;;
  "POST repos/"*"/issues/"*"/labels")
    n="${endpoint%/labels}"; n="${n##*/}"
    if [ -z "${STUB_DROP_LABELS:-}" ]; then
      jq --argjson n "$n" --slurpfile p "$input" \
        'map(if .number == $n then .labels += [$p[0].labels[] | {name: .}] else . end)' \
        "$STUB_DB" > "$STUB_DB.tmp" && mv "$STUB_DB.tmp" "$STUB_DB"
    fi
    jq -c --argjson n "$n" '[.[] | select(.number == $n) | .labels[]]' "$STUB_DB" | jq -r "$expr" ;;
  "POST repos/"*"/issues/"*"/assignees")
    n="${endpoint%/assignees}"; n="${n##*/}"
    if [ -z "${STUB_DROP_ASSIGNEES:-}" ]; then
      jq --argjson n "$n" --slurpfile p "$input" \
        'map(if .number == $n then .assignees += [$p[0].assignees[] | {login: .}] else . end)' \
        "$STUB_DB" > "$STUB_DB.tmp" && mv "$STUB_DB.tmp" "$STUB_DB"
    fi
    jq -c --argjson n "$n" '.[] | select(.number == $n)' "$STUB_DB" | jq -r "$expr" ;;
  "GET repos/"*"/issues/"*)
    n="${endpoint##*/}"
    jq -c --argjson n "$n" '.[] | select(.number == $n)' "$STUB_DB" | jq -r "$expr" ;;
  *) echo "stub: unexpected call $method $endpoint" >&2; exit 3 ;;
esac
STUB
chmod +x "$work/bin/gh"

TITLE="Monthly Agentic Quality Audit: 2026-11"

# reset <db-json> : fresh state, log, sentinel and output file for one case.
reset() {
  printf '%s\n' "$1" > "$work/db.json"
  : > "$work/log"
  rm -f "$work/sentinel" "$work/payload.json"
  : > "$work/ghout"
  unset STUB_LIST_FAIL STUB_CREATE STUB_DROP_LABELS STUB_DROP_ASSIGNEES
}
run() {
  OUT="$(PATH="$work/bin:$PATH" STUB_DB="$work/db.json" STUB_LOG="$work/log" \
    STUB_SENTINEL="$work/sentinel" STUB_CREATE_PAYLOAD="$work/payload.json" \
    GITHUB_OUTPUT="$work/ghout" GITHUB_STEP_SUMMARY="" \
    bash "$subject" "$@" 2>"$work/stderr")"
  RC=$?
}
validate() { # validate <case>
  if printf '%s\n' "$OUT" | bash "$validator" --validate - >/dev/null 2>&1; then
    assert "M $1 output passes the contract validator" true
  else
    assert "M $1 output passes the contract validator: $(printf '%s\n' "$OUT" | bash "$validator" --validate - 2>&1 | tail -3)" false
  fi
}
issue_count() { jq --arg t "$TITLE" '[.[] | select(.title == $t)] | length' "$work/db.json"; }
create_calls() { grep -c -- '-X POST repos/o/r/issues --input' "$work/log" || true; }

printf '## Monthly Agentic Quality Audit: 2026-11\n\nFindings.\n' > "$work/body.md"
OTHER='{"number":10,"title":"unrelated","state":"open","html_url":"u10","labels":[],"assignees":[]}'

# --- A: create once, metadata afterwards ----------------------------------------
reset "[$OTHER]"
run --repo o/r --title "$TITLE" --body-file "$work/body.md" \
  --label "agentic-audit,maintenance" --assignee laurigates
assert "A exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "A stub answered" "$([ -f "$work/sentinel" ] && echo true || echo false)"
assert "A ACTION=created" "$(has_line "$OUT" 'ACTION=created')"
assert "A STATUS=OK" "$(has_line "$OUT" 'STATUS=OK')"
assert "A one issue exists" "$(eq "$(issue_count)" 1)"
assert "A one create call" "$(eq "$(create_calls)" 1)"
assert "A create payload carries only title and body" \
  "$(eq "$(jq -c 'keys' "$work/payload.json")" '["body","title"]')"
assert "A labels read back" "$(has_line "$OUT" 'LABELS_APPLIED=agentic-audit,maintenance')"
assert "A assignee read back" "$(has_line "$OUT" 'ASSIGNEES_APPLIED=laurigates')"
assert "A issue number reported" "$(has_line "$OUT" 'ISSUE_NUMBER=11')"
validate A

# --- B: an open, unlabelled issue with the exact title is reused ----------------
reset "[$OTHER,{\"number\":12,\"title\":\"$TITLE\",\"state\":\"open\",\"html_url\":\"u12\",\"labels\":[],\"assignees\":[]}]"
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label "agentic-audit,maintenance"
assert "B exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "B ACTION=reused" "$(has_line "$OUT" 'ACTION=reused')"
assert "B reused #12" "$(has_line "$OUT" 'ISSUE_NUMBER=12')"
assert "B no create call" "$(eq "$(create_calls)" 0)"
assert "B still one issue" "$(eq "$(issue_count)" 1)"
assert "B labels applied to the reused issue" "$(has_line "$OUT" 'LABELS_APPLIED=agentic-audit,maintenance')"

# --- C: create files the issue, then fails: adopt, never retry ------------------
reset "[$OTHER]"
export STUB_CREATE=fail-after
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label "agentic-audit" --assignee laurigates
unset STUB_CREATE
assert "C exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "C exactly one create call (no retry)" "$(eq "$(create_calls)" 1)"
assert "C exactly one issue (no duplicate)" "$(eq "$(issue_count)" 1)"
assert "C STATUS=WARN" "$(has_line "$OUT" 'STATUS=WARN')"
assert "C names the lost response" "$(has "$OUT" 'TYPE=create_response_lost')"
assert "C labels applied to the adopted issue" "$(has_line "$OUT" 'LABELS_APPLIED=agentic-audit')"
validate C

# --- D: create fails and files nothing ------------------------------------------
reset "[$OTHER]"
export STUB_CREATE=fail-before
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label "agentic-audit"
unset STUB_CREATE
assert "D exits 1 (rc=$RC)" "$(eq "$RC" 1)"
assert "D exactly one create call (no retry)" "$(eq "$(create_calls)" 1)"
assert "D no issue" "$(eq "$(issue_count)" 0)"
assert "D TYPE=create_failed" "$(has "$OUT" 'TYPE=create_failed')"
assert "D no metadata call" "$(grep -q '/labels' "$work/log" && echo false || echo true)"
validate D

# --- E: a label that does not stick is an ERROR ---------------------------------
reset "[$OTHER]"
export STUB_DROP_LABELS=1
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label "agentic-audit,maintenance"
unset STUB_DROP_LABELS
assert "E exits 1 (rc=$RC)" "$(eq "$RC" 1)"
assert "E the issue was still published once" "$(eq "$(issue_count)" 1)"
assert "E TYPE=label_missing" "$(has "$OUT" 'TYPE=label_missing')"
assert "E LABELS_APPLIED reports what the issue carries" "$(has_line "$OUT" 'LABELS_APPLIED=')"
validate E

# --- F: an assignee GitHub drops is a WARN ---------------------------------------
reset "[$OTHER]"
export STUB_DROP_ASSIGNEES=1
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label "agentic-audit" --assignee laurigates
unset STUB_DROP_ASSIGNEES
assert "F exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "F STATUS=WARN" "$(has_line "$OUT" 'STATUS=WARN')"
assert "F TYPE=assignee_missing" "$(has "$OUT" 'TYPE=assignee_missing')"
assert "F ASSIGNEES_APPLIED is empty, not the request" "$(has_line "$OUT" 'ASSIGNEES_APPLIED=')"
validate F

# --- G: missing or blank body ---------------------------------------------------
reset "[$OTHER]"
run --repo o/r --title "$TITLE" --body-file "$work/nope.md" --label "agentic-audit"
assert "G missing body without --optional exits 1 (rc=$RC)" "$(eq "$RC" 1)"
assert "G TYPE=body_missing" "$(has "$OUT" 'TYPE=body_missing')"
assert "G missing body makes no API call" "$([ -f "$work/sentinel" ] && echo false || echo true)"
validate G-required
run --repo o/r --title "$TITLE" --body-file "$work/nope.md" --label "agentic-audit" --optional
assert "G missing body with --optional exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "G ACTION=skipped" "$(has_line "$OUT" 'ACTION=skipped')"
assert "G skip makes no API call" "$([ -f "$work/sentinel" ] && echo false || echo true)"
validate G-optional
printf '  \n\n' > "$work/blank.md"
run --repo o/r --title "$TITLE" --body-file "$work/blank.md" --optional
assert "G blank body counts as missing" "$(has_line "$OUT" 'ACTION=skipped')"

# --- H: --processing appended; agent file untouched -----------------------------
reset "[$OTHER]"
before="$(cat "$work/body.md")"
run --repo o/r --title "$TITLE" --body-file "$work/body.md" \
  --processing $'## Processing\n\n- **Closes:** next month.'
assert "H exits 0 (rc=$RC)" "$(eq "$RC" 0)"
assert "H published body ends with the processing section" \
  "$(eq "$(jq -r '.body' "$work/payload.json" | sed '/^$/d' | tail -1)" '- **Closes:** next month.')"
assert "H published body keeps the agent's text" \
  "$(jq -r '.body' "$work/payload.json" | grep -qxF 'Findings.' && echo true || echo false)"
assert "H agent file is unchanged" "$(eq "$(cat "$work/body.md")" "$before")"

# --- I: only an exact, open, non-PR title is reused -----------------------------
reset "[$OTHER,
  {\"number\":20,\"title\":\"Re: $TITLE\",\"state\":\"open\",\"html_url\":\"u20\",\"labels\":[],\"assignees\":[]},
  {\"number\":21,\"title\":\"$TITLE\",\"state\":\"closed\",\"html_url\":\"u21\",\"labels\":[],\"assignees\":[]},
  {\"number\":22,\"title\":\"$TITLE\",\"state\":\"open\",\"html_url\":\"u22\",\"labels\":[],\"assignees\":[],\"pull_request\":{}}]"
run --repo o/r --title "$TITLE" --body-file "$work/body.md"
assert "I near-miss, closed and PR titles are not reused" "$(has_line "$OUT" 'ACTION=created')"
assert "I the new issue is #23" "$(has_line "$OUT" 'ISSUE_NUMBER=23')"

# --- J: an unreadable listing creates nothing ------------------------------------
reset "[$OTHER]"
export STUB_LIST_FAIL=1
run --repo o/r --title "$TITLE" --body-file "$work/body.md"
unset STUB_LIST_FAIL
assert "J exits 1 (rc=$RC)" "$(eq "$RC" 1)"
assert "J TYPE=api_unreadable" "$(has "$OUT" 'TYPE=api_unreadable')"
assert "J no create call" "$(eq "$(create_calls)" 0)"
validate J

# --- K: usage errors -------------------------------------------------------------
reset "[$OTHER]"
run --repo o/r --body-file "$work/body.md"
assert "K missing --title exits 2" "$(eq "$RC" 2)"
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --label 'bad label'
assert "K a label with a space exits 2" "$(eq "$RC" 2)"
run --repo 'o/r;x' --title "$TITLE" --body-file "$work/body.md"
assert "K a malformed repo exits 2" "$(eq "$RC" 2)"
run --repo o/r --title "$TITLE" --body-file "$work/body.md" --bogus
assert "K an unknown flag exits 2" "$(eq "$RC" 2)"
assert "K usage errors make no API call" "$([ -f "$work/sentinel" ] && echo false || echo true)"

# --- L: GITHUB_OUTPUT -------------------------------------------------------------
reset "[$OTHER]"
run --repo o/r --title "$TITLE" --body-file "$work/body.md"
assert "L action=created in GITHUB_OUTPUT" "$(grep -qx 'action=created' "$work/ghout" && echo true || echo false)"
assert "L number=11 in GITHUB_OUTPUT" "$(grep -qx 'number=11' "$work/ghout" && echo true || echo false)"
assert "L url in GITHUB_OUTPUT" \
  "$(grep -qx 'url=https://github.com/o/r/issues/11' "$work/ghout" && echo true || echo false)"

echo "=== PUBLISH AGENT ISSUE TESTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
