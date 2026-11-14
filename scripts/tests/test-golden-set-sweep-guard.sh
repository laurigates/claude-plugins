#!/usr/bin/env bash
# Fixture test for the duplicate-sweep guard in
# .github/workflows/golden-set-evaluation.yml.
#
# "Check for an existing open sweep issue" skipped the monthly sweep while ANY
# open issue carried the golden-set-eval label. The label also routes related
# chores (#2748, #2766), so once the previous report closed those chores would
# have switched the sweep off: the #2729 class that #2972 fixed for the
# script-to-issue callers. The guard now counts only issues whose title starts
# with the sweep's own report prefix.
#
# It EXTRACTS the shipped `run:` body with PyYAML and runs it against a stub
# `gh` that applies the step's own `--jq` program to an issue-list fixture. It
# also pins the prefix to the title the sweep files its report under, which
# since #2769 is the `--title` of the step running scripts/publish-agent-issue.sh.
#
# Supersede (#3346, docs/issue-lifecycle.md): only THIS month's report skips the
# sweep. Last month's open report no longer blocks it; the guard reports it as
# `previous` so the sweep job can carry it forward and close it.
#
# Usage: bash scripts/tests/test-golden-set-sweep-guard.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/golden-set-evaluation.yml}"
GUARD_STEP='Check for an existing open sweep issue'

for tool in python3 jq; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

work="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

echo "=== GOLDEN-SET SWEEP GUARD ==="

python3 - "$WORKFLOW" "$GUARD_STEP" "$work/guard.sh" "$work/publish.txt" <<'PY'
import sys, yaml
path, name, out, publish_out = sys.argv[1:5]
jobs = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]
steps = [s for job in jobs.values() for s in job.get("steps", [])]
guard = [s for s in steps if s.get("name") == name]
if len(guard) != 1:
    sys.exit(f"expected one '{name}' step, found {len(guard)}")
open(out, "w", encoding="utf-8").write(guard[0]["run"])
# The report title lives in the step that files it: since #2769 that is the
# bash step running scripts/publish-agent-issue.sh, not the Claude prompt.
publish = [s["run"] for s in steps if "scripts/publish-agent-issue.sh" in str(s.get("run", ""))]
if len(publish) != 1:
    sys.exit(f"expected one publish-agent-issue.sh step, found {len(publish)}")
open(publish_out, "w", encoding="utf-8").write("\n".join(publish))
PY

# The prefix the guard filters on must be the prefix of the title the sweep's
# publish step files its report under, or the guard can never see the report.
prefix="$(sed -n 's/.*startswith("\([^"]*\)").*/\1/p' "$work/guard.sh" | head -1)"
title="$(sed -n 's/.*--title "\([^"]*\)".*/\1/p' "$work/publish.txt" | head -1)"
if [ -n "$prefix" ] && [ "${title#"$prefix"}" != "$title" ]; then
  pass "the guard's title prefix ('$prefix') matches the report title the publish step files ('$title')"
else
  fail "guard prefix '$prefix' does not start the publish step's report title '$title'"
fi

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
prog=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--jq) prog="$2"; shift 2 ;;
    *) shift ;;
  esac
done
jq -r "$prog" "$ISSUES_FIXTURE"
STUB
chmod +x "$work/bin/gh"

chores='[{"number":2766,"title":"[Chore] golden-set-evaluation: decide the monthly sweep scope"},{"number":2748,"title":"[Chore] evaluate-plugin: carry #2667 golden-set recs"}]'
with_report='[{"number":2766,"title":"[Chore] golden-set-evaluation: decide the monthly sweep scope"},{"number":2901,"title":"Golden-set cross-model sweep: 2026-10"}]'
last_month='[{"number":2766,"title":"[Chore] golden-set-evaluation: decide the monthly sweep scope"},{"number":2667,"title":"Golden-set cross-model sweep: 2026-09"}]'
printf '%s\n' "$chores" > "$work/chores.json"
printf '%s\n' "$with_report" > "$work/with_report.json"
printf '%s\n' "$last_month" > "$work/last_month.json"
printf '[]\n' > "$work/none.json"

check() { # <label> <fixture> <force> <expected should_skip> [expected previous]
  local got prev
  : > "$work/out"
  (PATH="$work/bin:$PATH" ISSUES_FIXTURE="$work/$2.json" FORCE="$3" MONTH=2026-10 GH_TOKEN=x \
    GITHUB_OUTPUT="$work/out" bash -e "$work/guard.sh" >/dev/null 2>&1) || true
  got="$(sed -n 's/^should_skip=//p' "$work/out")"
  if [ "$got" = "$4" ]; then pass "$1"; else fail "$1 (expected should_skip=$4, got '$got')"; fi
  if [ $# -ge 5 ]; then
    prev="$(sed -n 's/^previous=//p' "$work/out")"
    if [ "$prev" = "$5" ]; then pass "$1: previous=$5"; else fail "$1 (expected previous=$5, got '$prev')"; fi
  fi
}

check "open chores carrying the label do not skip the sweep"   chores      false false ""
check "this month's open sweep report skips the sweep"          with_report false true  ""
check "last month's open report does not skip the sweep"        last_month  false false 2667
check "force runs the sweep despite an open report"             with_report true  false
check "no open issue runs the sweep"                            none        false false ""

echo "=== END GOLDEN-SET SWEEP GUARD ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
