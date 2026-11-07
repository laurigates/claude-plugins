#!/usr/bin/env bash
# Regression test for scripts/close-superseded-reports.sh (#3346).
#
# Monthly reports close when the next month's report opens (decision recorded
# on #3346, docs/issue-lifecycle.md). The script closes every earlier report
# carrying the audit's label and title prefix, and nothing else:
#
#   A  closes last month's report, names the new one, leaves the new one open
#   B  never touches an issue that only carries the label (routing tag, #2729)
#   C  closes nothing when the current report was not filed (a denied create
#      must not also lose last month's findings)
#   D  --clean closes earlier reports with no current report (clean sweep)
#   E  a gh failure exits 1; usage errors exit 2
#
# A stub `gh` on PATH replays a fixture issue list and records every call.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
closer="$repo_root/scripts/close-superseded-reports.sh"

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

mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_ARGS"
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "list" ]; then
  if [ "${GH_STUB_RC:-0}" != "0" ]; then echo "stub: HTTP 502" >&2; exit "$GH_STUB_RC"; fi
  printf '%s\n' "$GH_STUB_JSON"
  exit 0
fi
if [ "${1:-}" = "issue" ] && [ "${2:-}" = "close" ]; then exit 0; fi
echo "stub gh: unexpected call: $*" >&2
exit 99
STUB
chmod +x "$tmp/bin/gh"
if [ ! -x "$tmp/bin/gh" ]; then echo "FAIL: stub gh is not executable" >&2; exit 1; fi

PREFIX='Monthly Agentic Quality Audit:'
OLD='{"number":3001,"title":"Monthly Agentic Quality Audit: 2026-09"}'
PREV='{"number":3200,"title":"Monthly Agentic Quality Audit: 2026-10"}'
CUR='{"number":3400,"title":"Monthly Agentic Quality Audit: 2026-11"}'
ROUTED='{"number":2696,"title":"feat(audit): something that carries the label"}'

run() { # <json> [args...] -- sets OUT, RC, ARGS
  local json="$1"; shift
  : > "$tmp/args"
  OUT="$(PATH="$tmp/bin:$PATH" GH_STUB_JSON="$json" GH_STUB_ARGS="$tmp/args" \
    GITHUB_REPOSITORY="o/r" bash "$closer" "$@" 2>&1)"
  RC=$?
  ARGS="$(<"$tmp/args")"
}
is_rc() { [ "$RC" -eq "$1" ] && echo true || echo false; }

# --- A: supersede ------------------------------------------------------------
run "[$OLD,$PREV,$CUR,$ROUTED]" --label agentic-audit --title-prefix "$PREFIX" \
  --current-title 'Monthly Agentic Quality Audit: 2026-11'
assert "A exits 0" "$(is_rc 0)"
assert "A closes the 2026-10 report" "$(contains "$ARGS" '^issue close 3200 ')"
assert "A closes the 2026-09 report" "$(contains "$ARGS" '^issue close 3001 ')"
assert "A leaves the current report open" "$(lacks "$ARGS" '^issue close 3400')"
assert "A the close comment names the new report" "$(contains "$ARGS" 'Superseded by #3400')"
assert "A the close comment points at the lifecycle doc" "$(contains "$ARGS" 'docs/issue-lifecycle.md')"
assert "A reports CURRENT=3400" "$(contains "$OUT" '^CURRENT=3400$')"
assert "A reports CLOSED=3001,3200" "$(contains "$OUT" '^CLOSED=3001,3200$')"
assert "A queried open issues by label" "$(contains "$ARGS" '--label agentic-audit --state open')"

# --- B: a routing-tag issue is never closed ----------------------------------
assert "B leaves the label-only issue open" "$(lacks "$ARGS" '^issue close 2696')"

# --- C: no current report -> close nothing -----------------------------------
run "[$PREV,$ROUTED]" --label agentic-audit --title-prefix "$PREFIX" \
  --current-title 'Monthly Agentic Quality Audit: 2026-11'
assert "C exits 1 when the current report is missing" "$(is_rc 1)"
assert "C closes nothing" "$(lacks "$ARGS" '^issue close')"
assert "C says the current report is missing" "$(contains "$OUT" 'no open issue titled')"

# --- D: --clean closes earlier reports without a current one -----------------
run "[$PREV,$ROUTED]" --label agentic-audit --title-prefix "$PREFIX" \
  --current-title 'Monthly Agentic Quality Audit: 2026-11' --clean
assert "D exits 0" "$(is_rc 0)"
assert "D closes the earlier report" "$(contains "$ARGS" '^issue close 3200 ')"
assert "D close comment says the sweep was clean" "$(contains "$ARGS" 'found nothing to report')"
assert "D leaves the label-only issue open" "$(lacks "$ARGS" '^issue close 2696')"
run "[$ROUTED]" --label agentic-audit --title-prefix "$PREFIX" \
  --current-title 'Monthly Agentic Quality Audit: 2026-11' --clean
assert "D nothing to close exits 0" "$(is_rc 0)"
assert "D nothing to close reports CLOSED=" "$(contains "$OUT" '^CLOSED=$')"

# --- E: failures -------------------------------------------------------------
: > "$tmp/args"
OUT="$(PATH="$tmp/bin:$PATH" GH_STUB_JSON='[]' GH_STUB_RC=1 GH_STUB_ARGS="$tmp/args" \
  bash "$closer" --label l --title-prefix p --current-title 'p x' 2>&1)"; RC=$?
assert "E gh failure exits 1" "$(is_rc 1)"
PATH="$tmp/bin:$PATH" bash "$closer" --label l --current-title 'p x' >/dev/null 2>&1; RC=$?
assert "E missing --title-prefix exits 2" "$(is_rc 2)"
PATH="$tmp/bin:$PATH" bash "$closer" --label l --title-prefix p >/dev/null 2>&1; RC=$?
assert "E missing --current-title exits 2" "$(is_rc 2)"
PATH="$tmp/bin:$PATH" bash "$closer" --label l --title-prefix p --current-title 'p x' --bogus >/dev/null 2>&1; RC=$?
assert "E unknown argument exits 2" "$(is_rc 2)"

echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ] || exit 1
echo "PASS: close-superseded-reports ($pass_count assertions)"
