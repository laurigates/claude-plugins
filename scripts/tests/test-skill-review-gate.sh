#!/usr/bin/env bash
# Fixture test for the Claude skill review's isolation and gate in
# .github/workflows/plugin-pr-checks.yml.
#
# Two defects this pins:
#
#   1. The Claude Skill Quality Review ran INSIDE the required `compliance`
#      job, so an LLM-side failure (subscription quota, bot-actor refusal)
#      turned the required context red regardless of the code: 10 of 19 failed
#      runs between 2026-09-24 and 2026-10-24. The review now lives in its own
#      `skill-review` job; this test asserts no claude-code-action step is left
#      in `compliance` and that `skill-review` needs it.
#   2. The review was gated on any changed path under skills/ and re-ran on
#      every push. The "Decide whether the Claude skill review runs" step now
#      runs it only when a SKILL.md changed, and on `synchronize` only when the
#      PR's SKILL.md diff (each head against its own merge-base) differs from
#      the one at the newest earlier head whose `skill-review` job succeeded.
#      The baseline is that reviewed head, not github.event.before: a review
#      cancelled by a newer push (cancel-in-progress), a failed review, or one
#      skipped because `compliance` failed never reviewed its head.
#
# It EXTRACTS the shipped `run:` body from the workflow with PyYAML and runs it
# against a scratch origin + clone and a stub `gh` that applies the step's own
# `--jq` programs to run-list and jobs fixtures, so editing the workflow is
# what this tests.
#
# Usage: bash scripts/tests/test-skill-review-gate.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/plugin-pr-checks.yml}"
GATE_STEP='Decide whether the Claude skill review runs'

for tool in python3 git jq sha256sum; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

# A scratch repo must never fall back to the real checkout (#1692, #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

work="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

echo "=== SKILL REVIEW ISOLATION ==="

structure="$(python3 - "$WORKFLOW" "$GATE_STEP" "$work/gate.sh" <<'PY'
import sys, yaml
path, gate_name, out = sys.argv[1:4]
jobs = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]
def claude_steps(job):
    return [s.get("name", "") for s in job.get("steps", [])
            if "anthropics/claude-code-action" in str(s.get("uses", ""))]
comp = jobs.get("compliance", {})
review = jobs.get("skill-review", {})
print("compliance_claude_steps=%d" % len(claude_steps(comp)))
print("review_claude_steps=%d" % len(claude_steps(review)))
needs = review.get("needs", [])
needs = [needs] if isinstance(needs, str) else needs
print("review_needs_compliance=%s" % ("compliance" in needs))
print("review_if_reads_gate=%s" % ("needs.compliance.outputs.skill_review" in str(review.get("if", ""))))
print("gate_output_wired=%s" % ("steps.review_gate.outputs.run" in str(comp.get("outputs", {}).get("skill_review", ""))))
gate = [s for s in comp.get("steps", []) if s.get("name") == gate_name]
print("gate_steps=%d" % len(gate))
if gate:
    open(out, "w", encoding="utf-8").write(gate[0]["run"])
PY
)"
get() { sed -n "s/^$1=//p" <<<"$structure"; }

expect() { # <key> <expected> <pass-label> <fail-label>
  if [ "$(get "$1")" = "$2" ]; then pass "$3"; else fail "$4 (got '$(get "$1")')"; fi
}
expect compliance_claude_steps 0 "no Claude step runs inside the required compliance job" \
  "the compliance job still holds a Claude step"
expect review_claude_steps 1 "the skill-review job holds the Claude step" \
  "the skill-review job does not hold exactly one Claude step"
expect review_needs_compliance True "skill-review needs compliance" "skill-review does not need compliance"
expect review_if_reads_gate True "skill-review is gated on the compliance gate output" \
  "skill-review if: does not read needs.compliance.outputs.skill_review"
expect gate_output_wired True "compliance exports the gate step's result" \
  "compliance outputs.skill_review is not steps.review_gate.outputs.run"
if [ "$(get gate_steps)" != "1" ]; then
  fail "no '$GATE_STEP' step in compliance"
  echo "=== END SKILL REVIEW GATE ==="
  echo "PASSED=$pass_count"
  echo "FAILED=$fail_count"
  echo "STATUS=FAIL"
  exit 1
fi

echo "=== SKILL REVIEW GATE ==="

# Stub gh. `run list` applies --jq to $GH_STUB_DIR/runs.json and fails unless
# it is scoped to --workflow plugin-pr-checks.yml --branch $GH_STUB_BRANCH;
# `api repos/<r>/actions/runs/<id>/jobs` applies --jq to jobs-<id>.json and
# fails when that fixture is missing. GH_STUB_FAIL=1 fails every call.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "${GH_STUB_FAIL:-0}" = 1 ] && { echo "stub gh: simulated API failure" >&2; exit 1; }
prog="" branch="" workflow="" pos=()
while [ $# -gt 0 ]; do
  case "$1" in
    -q|--jq) prog="$2"; shift 2 ;;
    -b|--branch) branch="$2"; shift 2 ;;
    -w|--workflow) workflow="$2"; shift 2 ;;
    -R|--repo|-e|--event|-L|--limit|--json) shift 2 ;;
    *) pos+=("$1"); shift ;;
  esac
done
case "${pos[0]:-} ${pos[1]:-}" in
  "run list")
    [ "$workflow" = plugin-pr-checks.yml ] || { echo "stub gh: unexpected --workflow '$workflow'" >&2; exit 1; }
    [ "$branch" = "$GH_STUB_BRANCH" ] || { echo "stub gh: unexpected --branch '$branch'" >&2; exit 1; }
    jq -r "$prog" "$GH_STUB_DIR/runs.json" ;;
  api\ repos/*/actions/runs/*/jobs)
    id="${pos[1]%/jobs}"; id="${id##*/}"
    [ -f "$GH_STUB_DIR/jobs-$id.json" ] || { echo "stub gh: no jobs for run $id" >&2; exit 1; }
    jq -r "$prog" "$GH_STUB_DIR/jobs-$id.json" ;;
  *) echo "stub gh: unexpected call: ${pos[*]}" >&2; exit 1 ;;
esac
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH" command -v gh | grep -qxF "$work/bin/gh" \
  || { echo "FATAL: gh does not resolve to the stub" >&2; exit 1; }

git init -q --bare "$work/origin.git"
git clone -q "$work/origin.git" "$work/w" 2>/dev/null
w="$work/w"
git -C "$w" config user.email test@example.invalid
git -C "$w" config user.name test
commit() { git -C "$w" add -A && git -C "$w" commit -qm "$1" && git -C "$w" rev-parse HEAD; }

mkdir -p "$w/a-plugin/skills/x" "$w/a-plugin/skills/y" "$w/a-plugin/skills/x/scripts"
echo one > "$w/a-plugin/skills/x/SKILL.md"
echo one > "$w/a-plugin/skills/y/SKILL.md"
echo s > "$w/a-plugin/skills/x/scripts/s.sh"
commit base >/dev/null
git -C "$w" branch -qM main
git -C "$w" push -q origin main

git -C "$w" switch -qc pr
echo two >> "$w/a-plugin/skills/x/SKILL.md";       c1="$(commit 'skill edit')"
echo s2 >> "$w/a-plugin/skills/x/scripts/s.sh";    c2="$(commit 'script only')"
echo s2b >> "$w/a-plugin/skills/x/scripts/s.sh";   c2b="$(commit 'second script only')"
echo three >> "$w/a-plugin/skills/x/SKILL.md";     c3="$(commit 'second skill edit')"
git -C "$w" push -q origin pr

# A later main that changes ANOTHER skill's SKILL.md, then the PR rebased on it:
# the PR's own SKILL.md diff is unchanged, but a diff taken against the current
# base tip instead of each head's merge-base would differ.
git -C "$w" switch -q main
echo two >> "$w/a-plugin/skills/y/SKILL.md"; commit 'main edits another skill' >/dev/null
git -C "$w" push -q origin main
git -C "$w" switch -qc pr-rebased "$c3"
git -C "$w" rebase -q main
r3="$(git -C "$w" rev-parse HEAD)"
git -C "$w" push -q origin pr-rebased

git -C "$w" switch -qc pr-scripts main
echo s3 >> "$w/a-plugin/skills/x/scripts/s.sh"; c4="$(commit 'scripts only PR')"
git -C "$w" fetch -q origin

# runs <sha>:<skill-review conclusion> ... — newest first, as `gh run list`
# returns them.
runs() {
  local i=100 entry sha concl json="["
  rm -f "$work"/stub/*
  mkdir -p "$work/stub"
  for entry in "$@"; do
    sha="${entry%%:*}" concl="${entry#*:}" i=$((i - 1))
    json="$json{\"databaseId\":$i,\"headSha\":\"$sha\"},"
    printf '{"jobs":[{"name":"compliance","conclusion":"success"},{"name":"skill-review","conclusion":"%s"}]}\n' \
      "$concl" > "$work/stub/jobs-$i.json"
  done
  printf '%s]\n' "${json%,}" > "$work/stub/runs.json"
}

# run_gate <action> <head> <workflow_changed> [gh_fail] — prints true/false
run_gate() {
  local out
  git -C "$w" checkout -q "$2"
  : > "$work/out"
  out="$(cd "$w" && PATH="$work/bin:$PATH" GH_STUB_DIR="$work/stub" GH_STUB_BRANCH=pr \
    GH_STUB_FAIL="${4:-0}" GH_TOKEN=x GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$work/out" \
    BASE_REF=main HEAD_REF=pr EVENT_ACTION="$1" HEAD_SHA="$2" WORKFLOW_CHANGED="$3" \
    bash -e "$work/gate.sh" 2>&1)" \
    || { echo "error: $out"; return 0; }
  sed -n 's/^run=//p' "$work/out"
}

check() { # <label> <expected> <action> <head> [workflow_changed] [gh_fail]
  local got
  got="$(run_gate "$3" "$4" "${5:-false}" "${6:-0}")"
  if [ "$got" = "$2" ]; then pass "$1"; else fail "$1 (expected run=$2, got '$got')"; fi
}

runs
check "opened with a SKILL.md change runs"                         true  opened      "$c3"
runs "$c1:success"
check "a script-only push after a reviewed skill push skips"       false synchronize "$c2"
runs "$c1:cancelled"
check "a script-only push after a cancelled review runs"          true  synchronize "$c2"
runs "$c1:failure"
check "a script-only push after a failed review runs"             true  synchronize "$c2"
runs "$c1:skipped"
check "a script-only push after a skipped review runs"            true  synchronize "$c2"
runs "$c2:skipped" "$c1:success"
check "a second script-only push compares against the last review" false synchronize "$c2b"
runs "$c2b:skipped" "$c2:skipped" "$c1:success"
check "push changing SKILL.md runs"                                true  synchronize "$c3"
runs "$c3:success" "$c2b:skipped" "$c1:success"
check "rebase onto a main that edits another skill skips"          false synchronize "$r3"
runs "0123456789abcdef0123456789abcdef01234567:success"
check "an unfetchable reviewed head fails toward running"          true  synchronize "$c3"
runs "$c1:success"
check "an unreadable run list fails toward running"                true  synchronize "$c2" false 1
runs
check "a PR changing only scripts under skills/ skips"             false opened      "$c4"
check "a PR modifying this workflow skips (OIDC)"                  false opened      "$c3" true

echo "=== END SKILL REVIEW GATE ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
