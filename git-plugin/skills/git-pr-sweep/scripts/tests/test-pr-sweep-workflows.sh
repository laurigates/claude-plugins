#!/usr/bin/env bash
# Behaviour test for git-pr-sweep's three workflow templates, run against a
# stub runtime (run-workflows.mjs). It pins:
#   pr-review — every guard aborts with zero agents; two finders per group and
#     one verifier per selected finding, all opus/high, verifiers detached at
#     the PR head in a worktree; the PR number is part of the dedup key; the
#     fair share across PRs; dead finders and verifiers come back as coverage
#     gaps (partial / unreviewed / unverified), never as clean or refuted; the
#     open[] rows carry exactly pr-fix's findings keys; the claims re-run skips
#     Find; no prompt asks for a GitHub mutation.
#   pr-fix — repair-round's guards plus a "pr-<n>" unit id; PASS / REPAIRED_PASS
#     / BLOCKED / UNVERIFIED / FIX_NEEDED rows; only the finalise agent pushes
#     and it never merges or opens a PR; its shared region is byte-identical
#     with repair-round's minus the three stage helpers.
#   pr-merge — a reader can only hold a ready draft (hold, dead reader, unmet or
#     unknown condition, moved head); the merge chunks are rebuilt; read-only.
# It also pins the caps the review planner and the review template share, and
# each template's agent count as the scale estimator reads it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill="$here/../.."
wf="$skill/workflows"
repo_root="$(cd "$skill/../../.." && pwd)"
rr="$repo_root/workflow-orchestration-plugin/skills/workflow-implement-verify/workflows/repair-round.workflow.js"
estimator="$repo_root/hooks-plugin/hooks/workflow-scale-estimate.py"

command -v node >/dev/null || { echo "SKIP: node not installed"; exit 0; }
for f in "$wf/pr-review.workflow.js" "$wf/pr-fix.workflow.js" "$wf/pr-merge.workflow.js" "$rr"; do
  [[ -f "$f" ]] || { echo "FAIL template missing: $f"; exit 1; }
done

fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

# The planner's limits are the review template's caps.
planner="$skill/scripts/plan-review-runs.sh"
for pair in "MAX_PRS:MAX_PRS" "MAX_GROUPS:MAX_GROUPS" "MAX_PER_GROUP:MAX_PER_GROUP"; do
  sh_name="${pair%%:*}"; js_name="${pair##*:}"
  sh_val=$(grep -E "^${sh_name}=[0-9]+$" "$planner" | cut -d= -f2)
  js_val=$(grep -E "^const ${js_name} = [0-9]+$" "$wf/pr-review.workflow.js" | awk '{print $4}')
  if [[ -n "$sh_val" && "$sh_val" == "$js_val" ]]; then pass "planner $sh_name ($sh_val) equals pr-review $js_name"
  else bad "planner $sh_name ($sh_val) differs from pr-review $js_name ($js_val)"; fi
done
# review-to-units.sh caps --chunk at pr-fix's MAX_UNITS.
fix_cap=$(grep -E "^const MAX_UNITS = [0-9]+$" "$wf/pr-fix.workflow.js" | awk '{print $4}')
if grep -qF "[1-${fix_cap}]" "$skill/scripts/review-to-units.sh"; then pass "review-to-units --chunk cap equals pr-fix MAX_UNITS ($fix_cap)"
else bad "review-to-units --chunk cap does not match pr-fix MAX_UNITS ($fix_cap)"; fi

# Each template is fully counted by the scale estimator, at the declared size.
if command -v python3 >/dev/null; then
  for spec in "pr-review:15" "pr-fix:13" "pr-merge:8"; do
    name="${spec%%:*}"; want="${spec##*:}"
    est=$(python3 "$estimator" 1000 < "$wf/$name.workflow.js")
    got=$(grep -E '^ESTIMATE=' <<<"$est" | cut -d= -f2)
    unb=$(grep -E '^UNBOUNDED=' <<<"$est" | cut -d= -f2)
    if [[ "$got" == "$want" && "$unb" == "0" ]]; then pass "$name estimator ESTIMATE=$got UNBOUNDED=0"
    else bad "$name estimator ESTIMATE=$got UNBOUNDED=$unb (want $want, 0)"; fi
  done
fi

node "$here/run-workflows.mjs" "$wf" "$rr" || fail=1
exit "$fail"
