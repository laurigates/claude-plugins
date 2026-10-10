#!/usr/bin/env bash
# Regression test for scripts/script-to-issue-guard.sh (#2729).
#
# The bug: the script-to-issue duplicate guard counted every open issue carrying
# the audit's label. #2696, an on-hold enhancement that carries
# `workflow-model-audit` for routing, therefore suppressed the monthly
# workflow-model audit -- silently, as a green run that filed nothing.
#
# A stub `gh` on PATH replays a fixture issue list, so the test is hermetic.
# Case A is the bug and case B is its counterweight: a guard hardwired to
# "never suppress" passes A, and one hardwired to "always suppress" passes B.
# shellcheck disable=SC2016  # file-level: the single-quoted `$(...)` / `${{ }}` are
# deliberate literals -- a fixture prefix that must stay unexpanded, and grep patterns.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
guard="$repo_root/scripts/script-to-issue-guard.sh"

tmp="$(mktemp -d)" || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "FAIL: mktemp -d returned no dir" >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not found on PATH"
  exit 0
fi

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

# The stub prints $GH_STUB_JSON for `gh issue list`, records its argv, and exits
# $GH_STUB_RC. Anything else is an unexpected call and fails loudly.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_ARGS"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  if [ "${GH_STUB_RC:-0}" != "0" ]; then echo "stub: HTTP 502" >&2; exit "$GH_STUB_RC"; fi
  printf '%s\n' "$GH_STUB_JSON"
  exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 99
STUB
chmod +x "$tmp/bin/gh"

# The real 2026-09-23 state from #2729, plus nothing else.
NON_REPORT='{"number":2696,"title":"feat(workflows): log predicted demand against pinned --effort"}'
REPORT='{"number":2630,"title":"Workflow model/effort audit: 2026-09"}'
PREFIX='Workflow model/effort audit:'

# run <json> [guard args...] -- sets OUT, RC, GHOUT, SUMMARY, ARGS
run() {
  local json="$1"; shift
  : > "$tmp/out"; : > "$tmp/summary"; : > "$tmp/args"
  OUT="$(PATH="$tmp/bin:$PATH" GH_STUB_JSON="$json" GH_STUB_ARGS="$tmp/args" \
    GITHUB_OUTPUT="$tmp/out" GITHUB_STEP_SUMMARY="$tmp/summary" \
    GITHUB_REPOSITORY="o/r" bash "$guard" "$@" 2>&1)"
  RC=$?
  GHOUT="$(<"$tmp/out")"
  SUMMARY="$(<"$tmp/summary")"
  ARGS="$(<"$tmp/args")"
}
is_rc() { [ "$RC" -eq "$1" ] && echo true || echo false; }

# --- A: the #2729 bug -- a label-only non-report must NOT suppress -------------
run "[$NON_REPORT]" --label workflow-model-audit --title-prefix "$PREFIX"
assert "A exits 0" "$(is_rc 0)"
assert "A exists=false (non-report does not suppress)" "$(contains "$GHOUT" '^exists=false$')"
assert "A matched is empty" "$(contains "$GHOUT" '^matched=$')"
assert "A stdout reports IGNORED=2696" "$(contains "$OUT" '^IGNORED=2696$')"
assert "A summary says the audit runs" "$(contains "$SUMMARY" 'the audit runs')"
assert "A summary names the ignored non-report" "$(contains "$SUMMARY" 'Ignored.*#2696')"
# Guard integrity: the stub was really asked for the label and for titles.
assert "A queried the label" "$(contains "$ARGS" '--label workflow-model-audit')"
assert "A requested titles" "$(contains "$ARGS" '--json number,title')"
assert "A raised the page cap" "$(contains "$ARGS" '--limit 100')"

# --- B: a real report title suppresses, and the summary names it -------------
run "[$NON_REPORT,$REPORT]" --label workflow-model-audit --title-prefix "$PREFIX"
assert "B exits 0" "$(is_rc 0)"
assert "B exists=true" "$(contains "$GHOUT" '^exists=true$')"
assert "B matched names only the report" "$(contains "$GHOUT" '^matched=2630$')"
assert "B summary names the matched issue" "$(contains "$SUMMARY" 'Skipped.*#2630')"
assert "B summary does not blame the non-report" "$(lacks "$SUMMARY" 'Skipped.*#2696')"

# --- C: no prefix keeps the label-only behaviour ------------------------------
run "[$NON_REPORT]" --label workflow-model-audit
assert "C exits 0" "$(is_rc 0)"
assert "C label-only: any labelled issue suppresses" "$(contains "$GHOUT" '^exists=true$')"
assert "C matched=2696" "$(contains "$GHOUT" '^matched=2696$')"
assert "C reports MODE=label-only" "$(contains "$OUT" '^MODE=label-only$')"
assert "C summary names the matched issue" "$(contains "$SUMMARY" 'Skipped.*#2696')"

# --- D: an empty list exits 0 with exists=false (both modes) ------------------
run "[]" --label workflow-model-audit --title-prefix "$PREFIX"
assert "D prefix mode: empty list exits 0" "$(is_rc 0)"
assert "D prefix mode: exists=false" "$(contains "$GHOUT" '^exists=false$')"
run "[]" --label workflow-model-audit
assert "D label-only: empty list exits 0" "$(is_rc 0)"
assert "D label-only: exists=false" "$(contains "$GHOUT" '^exists=false$')"

# --- E: a prefix match is a PREFIX, not a substring ---------------------------
run '[{"number":7,"title":"Re: Workflow model/effort audit: 2026-09"}]' \
  --label workflow-model-audit --title-prefix "$PREFIX"
assert "E mid-title occurrence does not match" "$(contains "$GHOUT" '^exists=false$')"

# --- F: a prefix carrying shell/jq metacharacters is data, not code -----------
run '[{"number":8,"title":"x\"$(touch PWNED)\" audit"}]' \
  --label l --title-prefix 'x"$(touch PWNED)"'
assert "F metacharacter prefix still matches literally" "$(contains "$GHOUT" '^matched=8$')"
assert "F nothing was executed" "$([ ! -e PWNED ] && [ ! -e "$tmp/PWNED" ] && echo true || echo false)"

# --- G: gh failure fails the step (neither a duplicate nor a silent skip) -----
: > "$tmp/out"
GHOUT_G="$(PATH="$tmp/bin:$PATH" GH_STUB_JSON='[]' GH_STUB_RC=1 GH_STUB_ARGS="$tmp/args" \
  GITHUB_OUTPUT="$tmp/out" bash "$guard" --label l 2>&1)"; RC=$?
assert "G gh failure exits 1" "$(is_rc 1)"
assert "G gh failure writes no exists= output" "$(lacks "$(<"$tmp/out")" 'exists=')"
assert "G names the failure" "$(contains "$GHOUT_G" 'gh issue list failed')"

# --- H: usage errors exit 2 (#2057) -------------------------------------------
PATH="$tmp/bin:$PATH" bash "$guard" >/dev/null 2>&1; RC=$?
assert "H missing --label exits 2" "$(is_rc 2)"
PATH="$tmp/bin:$PATH" bash "$guard" --label l --bogus >/dev/null 2>&1; RC=$?
assert "H unknown argument exits 2" "$(is_rc 2)"

# --- I: the composite and its callers stay wired to the guard -----------------
action="$repo_root/.github/actions/script-to-issue/action.yml"
assert "I composite calls the guard script" \
  "$(grep -q 'scripts/script-to-issue-guard.sh' "$action" && echo true || echo false)"
assert "I composite declares a title-prefix input" \
  "$(grep -q '^  title-prefix:' "$action" && echo true || echo false)"
assert "I composite passes the prefix via env, not interpolation" \
  "$(grep -q 'TITLE_PREFIX: \${{ inputs.title-prefix }}' "$action" && echo true || echo false)"
wma="$repo_root/.github/workflows/workflow-model-audit.yml"
assert "I workflow-model-audit passes its report prefix" \
  "$(grep -q "title-prefix: 'Workflow model/effort audit:'" "$wma" && echo true || echo false)"
assert "I workflow-model-audit prompt still files that title" \
  "$(grep -q -- '--title "Workflow model/effort audit: ' "$wma" && echo true || echo false)"

echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ]
