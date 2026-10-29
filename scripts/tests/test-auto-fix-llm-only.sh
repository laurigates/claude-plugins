#!/usr/bin/env bash
# Fixture test for the LLM-only gate in
# .github/workflows/github-workflow-auto-fix.yml.
#
# "Auto-fix: CI failures" started an Opus run on every failed run of the
# workflows it watches, including runs whose only failed step was a Claude
# step. A code change cannot fix a quota or bot-actor failure, and on quota the
# auto-fix Claude step failed the same way: on 2026-10-09 eight auto-fix runs
# each ended after 1 turn at $0 with is_error:true (run 37933730522 for failed
# run 37933197451).
#
# "Gather failure context" now sets `llm_only=true` when every failed step of
# the failed run is a `Claude …` step or a step of plugin-pr-checks'
# `skill-review` job, and the Claude step is skipped on it. This test EXTRACTS
# that step's shipped `run:` body with PyYAML and runs it against a stub `gh`
# that applies the step's own `--jq` program to jobs fixtures shaped like
# `gh run view <id> --json jobs`.
#
# Usage: bash scripts/tests/test-auto-fix-llm-only.sh [workflow-file]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
WORKFLOW="${1:-$repo_root/.github/workflows/github-workflow-auto-fix.yml}"
CTX_STEP='Gather failure context'
CLAUDE_STEP='Analyze and fix with Claude'

for tool in python3 jq git; do
  command -v "$tool" >/dev/null || { echo "FATAL: $tool not found on PATH" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML is required to read the workflow" >&2; exit 1; }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

work="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "FATAL: mktemp -d failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

echo "=== AUTO-FIX LLM-ONLY GATE ==="

claude_if="$(python3 - "$WORKFLOW" "$CTX_STEP" "$CLAUDE_STEP" "$work/ctx.sh" <<'PY'
import sys, yaml
path, ctx_name, claude_name, out = sys.argv[1:5]
steps = yaml.safe_load(open(path, encoding="utf-8"))["jobs"]["auto-fix"]["steps"]
by_name = {s.get("name"): s for s in steps}
open(out, "w", encoding="utf-8").write(by_name[ctx_name]["run"])
print(by_name[claude_name].get("if", ""))
PY
)"
if grep -qF "steps.context.outputs.llm_only != 'true'" <<<"$claude_if"; then
  pass "the Claude step is skipped when llm_only is true"
else
  fail "the Claude step's if: does not read steps.context.outputs.llm_only ('$claude_if')"
fi

# Stub gh: `run view --json jobs -q|--jq <prog>` applies <prog> to $JOBS_FIXTURE
# (a fixture named FAIL makes the call fail); every other call prints nothing.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
prog=""
want_jobs=false
while [ $# -gt 0 ]; do
  case "$1" in
    --json) [ "${2:-}" = "jobs" ] && want_jobs=true; shift 2 ;;
    -q|--jq) prog="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$want_jobs" = true ]; then
  [ "$JOBS_FIXTURE" = "FAIL" ] && { echo "stub gh: simulated API failure" >&2; exit 1; }
  jq -r "$prog" "$JOBS_FIXTURE"
fi
STUB
chmod +x "$work/bin/gh"
PATH="$work/bin:$PATH" command -v gh | grep -qF "$work/bin/gh" \
  || { echo "FATAL: gh does not resolve to the stub" >&2; exit 1; }

git init -q "$work/repo"
git -C "$work/repo" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init

fixture() { # <name> <json>
  printf '%s\n' "$2" > "$work/$1.json"
}
fixture claude_in_compliance '{"jobs":[{"name":"compliance","conclusion":"failure","steps":[{"name":"Run plugin compliance checks","conclusion":"success"},{"name":"Claude Skill Quality Review","conclusion":"failure"}]}]}'
fixture skill_review_assert '{"jobs":[{"name":"compliance","conclusion":"success","steps":[{"name":"Lint workflows with actionlint","conclusion":"success"}]},{"name":"skill-review","conclusion":"failure","steps":[{"name":"Claude Skill Quality Review","conclusion":"success"},{"name":"Assert the skill review left a comment","conclusion":"failure"}]}]}'
fixture mixed '{"jobs":[{"name":"compliance","conclusion":"failure","steps":[{"name":"Check shell scripts follow shell-scripting.md","conclusion":"failure"}]},{"name":"skill-review","conclusion":"failure","steps":[{"name":"Claude Skill Quality Review","conclusion":"failure"}]}]}'
fixture deterministic '{"jobs":[{"name":"compliance","conclusion":"failure","steps":[{"name":"Self-test every guard this job gates on","conclusion":"failure"}]}]}'
fixture no_failed_step '{"jobs":[{"name":"compliance","conclusion":"failure","steps":[{"name":"Set up job","conclusion":"success"}]}]}'
fixture no_failed_job '{"jobs":[{"name":"compliance","conclusion":"success","steps":[]}]}'
# A failed job whose steps show no failure, beside a failed review. Only the
# per-job `($failed | length) == 0` guard catches this one: without it the
# job adds nothing to the list and the review's `true` alone passes `all`.
fixture no_failed_step_beside_review '{"jobs":[{"name":"compliance","conclusion":"failure","steps":[{"name":"Run plugin compliance checks","conclusion":"success"}]},{"name":"skill-review","conclusion":"failure","steps":[{"name":"Claude Skill Quality Review","conclusion":"failure"}]}]}'

run_ctx() { # <fixture path or FAIL> — prints the llm_only value
  : > "$work/out"
  (cd "$work/repo" && PATH="$work/bin:$PATH" JOBS_FIXTURE="$1" GH_TOKEN=x \
    CI_CONTEXT_DIR="$work/ctx" RUN_ID=1 WORKFLOW_NAME="Plugin: PR checks" BRANCH=b \
    GITHUB_OUTPUT="$work/out" bash -e "$work/ctx.sh" >/dev/null 2>&1) || { echo "step-exited-nonzero"; return 0; }
  sed -n 's/^llm_only=//p' "$work/out"
}

check() { # <label> <fixture> <expected>
  local got
  got="$(run_ctx "$2")"
  if [ "$got" = "$3" ]; then pass "$1"; else fail "$1 (expected llm_only=$3, got '$got')"; fi
}

check "a run whose only failed step is the Claude review is LLM-only" "$work/claude_in_compliance.json" true
check "a failed skill-review delivery assertion is LLM-only"         "$work/skill_review_assert.json"  true
check "a deterministic failure beside a Claude failure is not"       "$work/mixed.json"                false
check "a deterministic failure alone is not"                         "$work/deterministic.json"        false
check "a failed job with no failed step is not"                      "$work/no_failed_step.json"       false
check "a failed job with no failed step beside a failed review is not" "$work/no_failed_step_beside_review.json" false
check "a run with no failed job is not"                              "$work/no_failed_job.json"        false
check "an unreadable job list is not"                                FAIL                              false

echo "=== END AUTO-FIX LLM-ONLY GATE ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
