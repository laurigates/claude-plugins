#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `[ -n ] && [ -d ] || die` is a guard, not if-then-else (must precede the first command)
# Regression tests for scripts/check-research-radar-grounding.sh (#2507, #2697).
#
# The guard pins the research-radar prompt's TOKEN-LEVEL grounding requirement:
# every surfaced suggestion is probed with one `Grep` against the surface it
# claims exists, and the old blanket "Do not read plugin source files" clause
# stays gone. Both directions are tested — a present-clause fixture must report
# STATUS=OK, and each mutant must be flagged — so the guard cannot pass
# vacuously by emitting nothing (.claude/rules/regression-testing.md).
#
# #2697 adds the target carry-forward: the Step 3 template emits a
# `<!-- research-radar-targets: -->` block, the prompt reads
# `recent-targets.txt`, and a recent-target collision is flagged, never
# filtered. Cases 10-12 strip one of those clauses each. Case 13 EXECUTES the
# shipped collector step against a stubbed `gh`, because the recency window is
# behaviour a token check cannot see.
#
# Run: bash scripts/tests/test-check-research-radar-grounding.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$SCRIPT_DIR/check-research-radar-grounding.sh"
REAL_WORKFLOW="$REPO_ROOT/.github/workflows/research-radar.yml"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

[ -f "$REAL_WORKFLOW" ] || { echo "missing $REAL_WORKFLOW" >&2; exit 1; }

# Seed a fixture repo root holding a copy of the real workflow.
seed() {
  local root="$1"
  mkdir -p "$root/.github/workflows"
  cp "$REAL_WORKFLOW" "$root/.github/workflows/research-radar.yml"
}

run_key() {
  # run_key DIR KEY -> value of KEY= from the guard's report
  bash "$GUARD" "$1" 2>&1 | grep -E "^$2=" | cut -d= -f2-
}

assert_eq() {
  local desc="$1" expected="$2" got="$3"
  if [ "$got" = "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected '%s', got '%s')\n" "$desc" "$expected" "$got"; FAIL=$((FAIL + 1))
  fi
}

echo "=== check-research-radar-grounding regression tests ==="

# 0. Guard integrity: the report is actually emitted (a silent script would make
#    every ISSUE_COUNT assertion below pass on an empty string).
clean="$WORK/clean"; seed "$clean"
report="$(bash "$GUARD" "$clean" 2>&1)"
case "$report" in
  *"=== RESEARCH RADAR GROUNDING ==="*"=== END RESEARCH RADAR GROUNDING ==="*)
    printf "  PASS: guard emits its structured report block\n"; PASS=$((PASS + 1)) ;;
  *)
    printf "  FAIL: guard emitted no structured report block\n"; FAIL=$((FAIL + 1)) ;;
esac

# 1. Positive control — the real workflow, copied verbatim, is grounded.
assert_eq "grounded workflow reports STATUS=OK" "OK" "$(run_key "$clean" STATUS)"
assert_eq "grounded workflow reports ISSUE_COUNT=0" "0" "$(run_key "$clean" ISSUE_COUNT)"
assert_eq "grounded workflow reports WORKFLOW_PRESENT=true" "true" "$(run_key "$clean" WORKFLOW_PRESENT)"

# 2. The live repo (default project dir) is grounded too.
assert_eq "live repo reports STATUS=OK" "OK" "$(bash "$GUARD" 2>&1 | grep -E '^STATUS=' | cut -d= -f2)"

# 3. Grounding requirement stripped → flagged.
no_ground="$WORK/no_ground"; seed "$no_ground"
wf="$no_ground/.github/workflows/research-radar.yml"
grep -vF 'Ground every surfaced suggestion' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing grounding requirement is flagged" "1" "$(run_key "$no_ground" ISSUE_COUNT)"
assert_eq "missing grounding requirement sets STATUS=ERROR" "ERROR" "$(run_key "$no_ground" STATUS)"

# 4. Drop-or-re-target instruction stripped → flagged.
no_drop="$WORK/no_drop"; seed "$no_drop"
wf="$no_drop/.github/workflows/research-radar.yml"
grep -vF 'or drop the paper' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing drop-or-re-target instruction is flagged" "1" "$(run_key "$no_drop" ISSUE_COUNT)"

# 5. Evidence-disclosure instruction stripped → flagged.
no_evidence="$WORK/no_evidence"; seed "$no_evidence"
wf="$no_evidence/.github/workflows/research-radar.yml"
grep -vF 'State the exact file(s) and pattern grepped' "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
assert_eq "missing grounding-evidence disclosure is flagged" "1" "$(run_key "$no_evidence" ISSUE_COUNT)"

# 6. The #2507 root-cause clause re-introduced → flagged (absence assertion).
regressed="$WORK/regressed"; seed "$regressed"
wf="$regressed/.github/workflows/research-radar.yml"
printf '            - Do not read plugin source files — mapping ideas to plugin names only.\n' >> "$wf"
assert_eq "re-introduced no-source-read clause is flagged" "1" "$(run_key "$regressed" ISSUE_COUNT)"

# 7. Missing workflow entirely → every assertion reports.
empty="$WORK/empty"; mkdir -p "$empty"
assert_eq "absent workflow reports WORKFLOW_PRESENT=false" "false" "$(run_key "$empty" WORKFLOW_PRESENT)"
assert_eq "absent workflow flags all seven assertions" "7" "$(run_key "$empty" ISSUE_COUNT)"

# 8. --strict exit codes.
if bash "$GUARD" --strict "$clean" >/dev/null 2>&1; then
  printf "  PASS: --strict exits 0 on a grounded workflow\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: --strict should exit 0 on a grounded workflow\n"; FAIL=$((FAIL + 1))
fi
if bash "$GUARD" --strict "$no_ground" >/dev/null 2>&1; then
  printf "  FAIL: --strict should exit 1 when the grounding clause is missing\n"; FAIL=$((FAIL + 1))
else
  printf "  PASS: --strict exits 1 when the grounding clause is missing\n"; PASS=$((PASS + 1))
fi

# 9. Unknown argument is rejected with exit 2, never swallowed.
bash "$GUARD" --bogus >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  printf "  PASS: unknown argument exits 2\n"; PASS=$((PASS + 1))
else
  printf "  FAIL: unknown argument should exit 2\n"; FAIL=$((FAIL + 1))
fi

# 10-12. #2697 target carry-forward clauses: each stripped alone → flagged.
# assert_stripped DESC TOKEN strips every line carrying TOKEN from a fresh copy
# of the real workflow and requires exactly one finding that names TOKEN. The
# line-count assertion proves the mutant really lost a line; without it, a token
# missing from the workflow would leave the "mutant" identical to the clean copy.
assert_stripped() {
  local desc="$1" token="$2" root wf before after report
  root="$(mktemp -d "$WORK/strip.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
  seed "$root"
  wf="$root/.github/workflows/research-radar.yml"
  before="$(wc -l < "$wf")"
  grep -vF -- "$token" "$wf" > "$wf.tmp" && mv "$wf.tmp" "$wf"
  after="$(wc -l < "$wf")"
  assert_eq "$desc: mutant removed exactly one line" "1" "$((before - after))"
  report="$(bash "$GUARD" "$root" 2>&1)"
  assert_eq "$desc: flagged as the only finding" "1" \
    "$(printf '%s\n' "$report" | grep -E '^ISSUE_COUNT=' | cut -d= -f2)"
  case "$report" in
    *"TOKEN=\"$token\""*)
      printf "  PASS: %s: the finding names the stripped token\n" "$desc"; PASS=$((PASS + 1)) ;;
    *)
      printf "  FAIL: %s: the finding does not name the stripped token\n" "$desc"; FAIL=$((FAIL + 1)) ;;
  esac
}
assert_stripped "targets block in the Step 3 template" '<!-- research-radar-targets: <path1> <path2> -->'
# shellcheck disable=SC2016  # the backticks are literal prompt text, not an expansion
assert_stripped "recent-targets.txt pre-computed input" '`recent-targets.txt` in the repo root:'
assert_stripped "flag-do-not-filter collision clause" 'Never drop a paper because its target was recently amended'

# 13. The shipped collector step, EXECUTED against a stubbed `gh`. A token check
#     cannot see the recency window, so this runs the real run block: a target
#     inside the window is listed with its issue, one outside it is not, a legacy
#     issue without the block contributes nothing, and the file always exists.
col="$WORK/collector"
mkdir -p "$col/bin" "$col/ws" "$col/tmp"
extract_rc=0
python3 - "$REAL_WORKFLOW" "$col" <<'PY' || extract_rc=$?
import shlex, sys, yaml
wf_path, out = sys.argv[1], sys.argv[2]
wf = yaml.safe_load(open(wf_path))
steps = [s for s in wf["jobs"]["gather"]["steps"]
         if s.get("name") == "Collect recently-amended targets"]
if len(steps) != 1:
    sys.exit("expected 1 'Collect recently-amended targets' step, found %d" % len(steps))
run = steps[0]["run"]
if "${{" in run:
    sys.exit("unresolved ${{ }} interpolation in the collector run block")
open(out + "/run.sh", "w").write(run)
with open(out + "/env.sh", "w") as fh:
    for k, v in (steps[0].get("env") or {}).items():
        if "${{" in str(v):
            continue  # GH_TOKEN: the stub needs no credential
        fh.write("export %s=%s\n" % (k, shlex.quote(str(v))))
PY
assert_eq "13: collector step extracted from the real workflow" "0" "$extract_rc"

# shellcheck source=/dev/null
window="$(. "$col/env.sh" 2>/dev/null; printf '%s' "${TARGET_WINDOW_DAYS:-}")"
case "$window" in
  ''|*[!0-9]*|0) window_ok=no ;;
  *) window_ok=yes ;;
esac
assert_eq "13: step declares a positive TARGET_WINDOW_DAYS" "yes" "$window_ok"

# Stub: never reaches GitHub. It records every call so the run can prove the
# stub, not a real `gh` further down PATH, answered.
cat > "$col/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'STUB-GH-CALLED\n' >> "$STUB_LOG"
[ "${STUB_GH_FAIL:-0}" = "1" ] && exit 1
cat "$STUB_GH_FIXTURE"
STUB
chmod +x "$col/bin/gh"
assert_eq "13: the stub is the gh on PATH" "$col/bin/gh" "$(PATH="$col/bin:$PATH" bash -c 'command -v gh')"

# Fixture ages are placed one day either side of the step's own window, so the
# boundary is tested at the shipped value rather than at a copy of it.
python3 - "$col" "${window:-28}" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
out, window = sys.argv[1], int(sys.argv[2])
now = datetime.now(timezone.utc)
def ago(days):
    return (now - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
ids = "<!-- research-radar-ids: 2609.0000%d -->"
targets = "<!-- research-radar-targets: %s -->"
json.dump([
    {"number": 2673, "createdAt": ago(1), "body": "## What\nbody\n" + ids % 1 + "\n"
        + targets % ".claude/rules/loop-integrity.md evaluate-plugin/skills/evaluate-improve/SKILL.md"},
    {"number": 2631, "createdAt": ago(max(window - 1, 1)),
        "body": ids % 2 + "\n" + targets % ".claude/rules/loop-integrity.md"},
    {"number": 2573, "createdAt": ago(1), "body": "legacy body\n" + ids % 3},
    {"number": 2600, "createdAt": ago(1), "body": None},
    # #2697 itself carries the research-radar label and quotes the template
    # placeholder; `<path1>` must never be collected as a target.
    {"number": 2697, "createdAt": ago(1), "body": targets % "<path1> <path2>"},
    {"number": 2507, "createdAt": ago(window + 1),
        "body": targets % "prompt-engineering-plugin/skills/stale-target/SKILL.md"},
], open(out + "/issues.json", "w"))
json.dump([], open(out + "/empty.json", "w"))
PY

run_collector() {
  # run_collector FIXTURE FAIL_FLAG -> the step's exit code
  rm -f "$col/ws/recent-targets.txt" "$col/stub.log"
  (
    cd "$col/ws" || exit 97
    # shellcheck source=/dev/null
    . "$col/env.sh"
    export STUB_LOG="$col/stub.log" STUB_GH_FIXTURE="$1" STUB_GH_FAIL="$2"
    export RUNNER_TEMP="$col/tmp" GITHUB_REPOSITORY="example/not-a-real-repo"
    PATH="$col/bin:$PATH" bash "$col/run.sh"
  ) >/dev/null 2>&1
}
out="$col/ws/recent-targets.txt"
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo "missing"; fi; }
has() { if [ -f "$1" ] && grep -qF -- "$2" "$1"; then echo yes; else echo no; fi; }

rc=0; run_collector "$col/issues.json" 0 || rc=$?
assert_eq "13: collector exits 0" "0" "$rc"
assert_eq "13: the stub answered the query" "yes" "$(has "$col/stub.log" STUB-GH-CALLED)"
assert_eq "13: three recent targets listed" "3" "$(lines "$out")"
assert_eq "13: this week's target names its issue" "yes" "$(has "$out" '.claude/rules/loop-integrity.md #2673 ')"
assert_eq "13: a target just inside the window is kept" "yes" "$(has "$out" '.claude/rules/loop-integrity.md #2631 ')"
assert_eq "13: every path in a multi-target block is listed" "yes" \
  "$(has "$out" 'evaluate-plugin/skills/evaluate-improve/SKILL.md #2673 ')"
assert_eq "13: a target just outside the window is dropped" "no" "$(has "$out" 'stale-target')"
assert_eq "13: a legacy ids-only issue contributes nothing" "no" "$(has "$out" '#2573')"
assert_eq "13: a null body contributes nothing" "no" "$(has "$out" '#2600')"
assert_eq "13: a quoted template placeholder contributes nothing" "no" "$(has "$out" '#2697')"
assert_eq "13: each line carries a YYYY-MM-DD date" "3" \
  "$(grep -cE '^[^ ]+ #[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$out" 2>/dev/null)"

rc=0; run_collector "$col/empty.json" 0 || rc=$?
assert_eq "13: no prior issues exits 0" "0" "$rc"
assert_eq "13: no prior issues still writes an empty file" "0" "$(lines "$out")"

rc=0; run_collector "$col/empty.json" 1 || rc=$?
assert_eq "13: a failing gh query exits 0" "0" "$rc"
assert_eq "13: a failing gh query still writes an empty file" "0" "$(lines "$out")"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
