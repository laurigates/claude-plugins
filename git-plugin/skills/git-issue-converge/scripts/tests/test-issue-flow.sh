#!/usr/bin/env bash
# Regression test for issue-flow.sh. Runs offline through a stub gh binary
# (ISSUE_FLOW_GH) and checks the counts, the label cap, the structured-output
# contract and the zero-net OK path.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
flow="${script_dir}/../issue-flow.sh"

tmp="$(mktemp -d)"
[ -n "$tmp" ] && [ -d "$tmp" ] || { echo "FAIL: mktemp" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

fail=0
check() {
  if grep -qxF "$2" <<<"$3"; then echo "PASS $1"; else echo "FAIL $1: missing '$2'"; fail=1; fi
}

# Stub gh: search counts from env, one page of open issues with labels and a PR.
cat >"$tmp/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *search/issues*is:open*) echo "${STUB_OPEN:-0}" ;;
  *search/issues*reason:*) echo "${STUB_NOT_PLANNED:-0}" ;;
  *search/issues*is:closed*) echo "${STUB_CLOSED:-0}" ;;
  *search/issues*created:*) echo "${STUB_OPENED:-0}" ;;
  *repos/*/issues*page=1*)
    jq -n '[range(0;3) | {labels:[{name:"build:robocar"},{name:"bug"}]}]
           + [{labels:[{name:"build:robocar"}], pull_request:{}}]
           + [{labels:[{name:"docs"}]}]' ;;
  *) echo "[]" ;;
esac
EOF
chmod +x "$tmp/gh"

# Case A: growing backlog, one label over a cap of 2.
out="$(STUB_OPEN=183 STUB_OPENED=162 STUB_CLOSED=67 STUB_NOT_PLANNED=5 ISSUE_FLOW_GH="$tmp/gh" \
  bash "$flow" --repo acme/app --days 28 --label-cap 2)"
check "A open total" "OPEN_TOTAL=183" "$out"
check "A opened" "OPENED_WINDOW=162" "$out"
check "A closed" "CLOSED_WINDOW=67" "$out"
check "A not planned" "CLOSED_NOT_PLANNED_WINDOW=5" "$out"
check "A net" "NET_WINDOW=95" "$out"
check "A label over cap (PR excluded)" "LABEL_BUILD_ROBOCAR=3" "$out"
check "A bug over cap" "LABEL_BUG=3" "$out"
check "A labels over cap" "LABELS_OVER_CAP=2" "$out"
check "A status" "STATUS=WARN" "$out"
check "A reason" "REASON=label_over_cap: 2 label(s) above 2 open issues (+1 more)" "$out"
check "A issue count" "ISSUE_COUNT=2" "$out"
check "A footer" "=== END ISSUE FLOW ===" "$out"

# Case B: shrinking backlog, cap not reached.
out="$(STUB_OPEN=100 STUB_OPENED=10 STUB_CLOSED=90 ISSUE_FLOW_GH="$tmp/gh" \
  bash "$flow" --repo acme/app --label-cap 20)"
check "B net" "NET_WINDOW=-80" "$out"
check "B labels over cap" "LABELS_OVER_CAP=0" "$out"
check "B status" "STATUS=OK" "$out"
check "B issue count" "ISSUE_COUNT=0" "$out"
if grep -q '^REASON=' <<<"$out"; then echo "FAIL B: REASON on OK"; fail=1; else echo "PASS B no reason on OK"; fi

# Case D: --label-pattern caps only matching labels.
out="$(STUB_OPEN=5 STUB_OPENED=1 STUB_CLOSED=2 ISSUE_FLOW_GH="$tmp/gh" \
  bash "$flow" --repo acme/app --label-cap 2 --label-pattern '^(build|area):')"
check "D routing label" "LABEL_BUILD_ROBOCAR=3" "$out"
check "D type label skipped" "LABELS_OVER_CAP=1" "$out"

# Case C: bad argument is an ERROR with a reason.
out="$(ISSUE_FLOW_GH="$tmp/gh" bash "$flow" --repo acme/app --days x)"
check "C status" "STATUS=ERROR" "$out"
check "C reason" "REASON=bad_argument: --days and --label-cap take whole numbers" "$out"

exit "$fail"
