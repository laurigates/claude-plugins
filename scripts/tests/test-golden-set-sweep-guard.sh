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
# also pins the prefix to the title the sweep prompt files its report under.
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

python3 - "$WORKFLOW" "$GUARD_STEP" "$work/guard.sh" "$work/prompt.txt" <<'PY'
import sys, yaml
path, name, out, prompt_out = sys.argv[1:5]
jobs = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]
steps = [s for job in jobs.values() for s in job.get("steps", [])]
guard = [s for s in steps if s.get("name") == name]
if len(guard) != 1:
    sys.exit(f"expected one '{name}' step, found {len(guard)}")
open(out, "w", encoding="utf-8").write(guard[0]["run"])
prompts = [s.get("with", {}).get("prompt", "") for s in steps if s.get("with", {}).get("prompt")]
open(prompt_out, "w", encoding="utf-8").write("\n".join(prompts))
PY

# The prefix the guard filters on must be the prefix of the title the sweep
# prompt files its report under, or the guard can never see the report.
prefix="$(sed -n 's/.*startswith("\([^"]*\)").*/\1/p' "$work/guard.sh" | head -1)"
title="$(sed -n 's/.*--title "\([^"]*\)".*/\1/p' "$work/prompt.txt" | head -1)"
if [ -n "$prefix" ] && [ "${title#"$prefix"}" != "$title" ]; then
  pass "the guard's title prefix ('$prefix') matches the report title the prompt files ('$title')"
else
  fail "guard prefix '$prefix' does not start the prompt's report title '$title'"
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
with_report='[{"number":2766,"title":"[Chore] golden-set-evaluation: decide the monthly sweep scope"},{"number":2667,"title":"Golden-set cross-model sweep: 2026-09"}]'
printf '%s\n' "$chores" > "$work/chores.json"
printf '%s\n' "$with_report" > "$work/with_report.json"
printf '[]\n' > "$work/none.json"

check() { # <label> <fixture> <force> <expected should_skip>
  local got
  : > "$work/out"
  (PATH="$work/bin:$PATH" ISSUES_FIXTURE="$work/$2.json" FORCE="$3" GH_TOKEN=x \
    GITHUB_OUTPUT="$work/out" bash -e "$work/guard.sh" >/dev/null 2>&1) || true
  got="$(sed -n 's/^should_skip=//p' "$work/out")"
  if [ "$got" = "$4" ]; then pass "$1"; else fail "$1 (expected should_skip=$4, got '$got')"; fi
}

check "open chores carrying the label do not skip the sweep"   chores      false false
check "an open sweep report skips the sweep"                    with_report false true
check "force runs the sweep despite an open report"             with_report true  false
check "no open issue runs the sweep"                            none        false false

echo "=== END GOLDEN-SET SWEEP GUARD ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
