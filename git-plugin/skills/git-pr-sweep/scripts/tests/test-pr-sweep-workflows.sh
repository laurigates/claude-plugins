#!/usr/bin/env bash
# Behaviour test for git-pr-sweep's three workflow templates, run against a
# stub runtime (run-workflows.mjs). It pins:
#   pr-review — every guard aborts with zero agents; two finders per group and
#     one verifier per selected finding, all opus/high, verifiers detached at
#     the PR head in a worktree; the PR number is part of the dedup key; the
#     fair share across PRs; dead finders and verifiers come back as coverage
#     gaps (partial / unreviewed / unverified), never as clean or refuted; the
#     open[] rows carry exactly pr-fix's findings keys; the claims re-run skips
#     Find; no prompt asks for a GitHub mutation; its verdict schema and
#     distinct_also handling are byte-identical with adversarial-review's
#     find-verify (fv-shared markers) and both carry the refute-by-default
#     clauses (#3750).
#   pr-fix — repair-round's guards plus a "pr-<n>" unit id; PASS / REPAIRED_PASS
#     / BLOCKED / UNVERIFIED / FIX_NEEDED rows; only the finalise agent pushes
#     and it never merges or opens a PR; its shared region is byte-identical
#     with repair-round's minus the three stage helpers.
#   pr-merge — a reader can only hold a ready draft (hold, dead reader, unmet or
#     unknown condition, moved head); the merge chunks are rebuilt; read-only.
# It also pins the caps the review planner and the review template share, each
# template's agent count as the scale estimator reads it, and three SKILL.md
# orderings: the review timestamp before the merge-stage re-list, one verify-only
# re-run per review run, and findings listed in the final report. Text pins:
# the verify-only re-run takes its prs from review-plan.json (M2), a FAILED or
# UNVERIFIED unit is re-dispatched only after its leftovers are cleared (H3),
# and the M8 repair starts from the expected head, never the live one (H1).
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

# Regression: the merge stage took --review-ts after the re-list, the gate, the pr-merge
# run and gh pr ready, so a push landing in that window predated the timestamp and
# merge-chain.sh merged a head no review or gate saw. The timestamp now comes first.
skill_md="$skill/SKILL.md"
step4=$(awk '/^### Step 4: Merge/{on=1} /^## Draft handling/{on=0} on' "$skill_md")
ts_line=$(grep -n 'date -u +%Y-%m-%dT%H:%M:%SZ' <<<"$step4" | head -1 | cut -d: -f1)
relist_line=$(grep -n 'Re-list fresh' <<<"$step4" | head -1 | cut -d: -f1)
if [[ -n "$ts_line" && -n "$relist_line" && "$ts_line" -lt "$relist_line" ]]; then pass "SKILL Step 4 takes the review timestamp before the re-list"
else bad "SKILL Step 4 must take the review timestamp (line $ts_line) before the re-list (line $relist_line)"; fi
proc="$skill/references/merge-procedure.md"
ts_row=$(grep -n '^| M[0-9] .*date -u' "$proc" | head -1 | cut -d: -f1)
relist_row=$(grep -n '^| M[0-9] .*list-sweep-prs.sh --resolve-blockers' "$proc" | head -1 | cut -d: -f1)
if [[ -n "$ts_row" && -n "$relist_row" && "$ts_row" -lt "$relist_row" ]]; then pass "merge-procedure takes the timestamp before the re-list"
else bad "merge-procedure must order the timestamp row ($ts_row) before the re-list row ($relist_row)"; fi

# Regression (#3748): M1 precedes the last re-list, and merge-chain.sh's guard compares commit
# dates, so a commit dated before M1 but pushed after the last re-list merged unreviewed. Lauri
# chose option 3: immediately before every merge-chain.sh call, read each chunk PR's live
# headRefOid, compare it with the head G5 cleared (the roster head_sha, equal to G5's expected
# head for a passing PR) and drop the PRs that moved. No merge-chain.sh or guard change.
m6_row=$(grep -E '^\| M6 ' "$proc" | head -1)
if grep -qF 'gh pr view <n> -R <owner>/<repo> --json headRefOid' <<<"$m6_row" \
   && grep -qF 'head_sha' <<<"$m6_row" && grep -qiF 'drop' <<<"$m6_row" \
   && grep -qiF 'every chunk, including the first' <<<"$m6_row" \
   && [[ "$(grep -bo -- '--json headRefOid' <<<"$m6_row" | head -1 | cut -d: -f1)" -lt "$(grep -bo 'merge-chain.sh' <<<"$m6_row" | tail -1 | cut -d: -f1)" ]]; then
  pass "merge-procedure M6 compares each PR's headRefOid with the gated head before every merge-chain.sh call"
else bad "merge-procedure M6 must read each chunk PR's headRefOid, compare it with the roster head_sha G5 cleared, and drop moved PRs before every merge-chain.sh call, including the first"; fi
if ! grep -qF 'still slips through' "$proc" && grep -qF 'head moved' "$proc"; then
  pass "merge-procedure no longer leaves the pushed-after-re-list commit to the date guard"
else bad "merge-procedure must replace the 'still slips through' residual with the head comparison"; fi
step4_6=$(awk '/^6\. For each `plan.merge` chunk/{on=1} /^7\. /{on=0} on' <<<"$step4")
hc=$(grep -n 'gh pr view 12 -R <owner>/<repo> --json headRefOid' <<<"$step4_6" | head -1 | cut -d: -f1 || true)
mc=$(grep -n 'merge-chain.sh --repo' <<<"$step4_6" | head -1 | cut -d: -f1 || true)
if [[ -n "$hc" && -n "$mc" && "$hc" -lt "$mc" ]]; then pass "SKILL Step 4.6 reads headRefOid before the merge-chain.sh call"
else bad "SKILL Step 4.6 must read each PR's headRefOid (line $hc) before the merge-chain.sh call (line $mc)"; fi
# The decision excludes a script or guard change: merge-chain.sh keeps its accepted flags.
mch="$repo_root/git-plugin/skills/git-merge-hazards/scripts/merge-chain.sh"
flags=$(grep -oE '^    --[a-z-]+(\|--[a-z-]+)*\)$' "$mch" | head -1 || true)
if [[ "$flags" == '    --repo|--prs|--review-ts|--method|--timeout|--fetch-dir)' ]]; then pass "merge-chain.sh accepts exactly the flags the merge guard knows"
else bad "merge-chain.sh flag set changed: $flags"; fi

# Regression: Step 2 pooled every run's unverified claims into one verify-only re-run,
# which aborts over pr-review's 6-PR cap, and its join example dropped review-2.json.
step2=$(awk '/^### Step 2: Review/{on=1} /^### Step 3: Fix/{on=0} on' "$skill_md")
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
if grep -qF 'For each `review-<i>.json` with `unverified` rows' <<<"$step2" && grep -qF '`<work>/verify-<i>.json`' <<<"$step2" \
   && grep -qE 'merge-review\.sh .*review-1\.json .*review-2\.json .*verify-1\.json' <<<"$step2"; then
  pass "SKILL Step 2 re-verifies per review run and joins every run file"
else bad "SKILL Step 2 must re-verify per review run (verify-<i>.json) and join every review/verify file"; fi

# Regression: findings of PRs the sweep may not fix were never shown; Post-actions must list them.
post=$(awk '/^## Post-actions/{on=1} on' "$skill_md")
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
if grep -qF '`findings`' <<<"$post" && grep -qF '`fix_block`' <<<"$post"; then pass "SKILL Post-actions lists each reported PR's findings and fix_block"
else bad "SKILL Post-actions must list reported PRs' findings and fix_block"; fi

# Regression (M2): Step 2.4 said `prs` = "their rows" without a source; review-<i>.json
# rows have no base or author_kind, and pr-review aborts missing-head on them.
handoff="$skill/references/handoff-formats.md"
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
if grep -qF '`prs` = those PRs'"'"' rows from `review-plan.json` `runs[i].prs`' <<<"$step2" \
   && grep -qF '`prs` = `review-plan.json` `runs[i].prs` filtered to those PRs' "$handoff"; then
  pass "verify-only re-run takes its prs from review-plan.json runs[i].prs (SKILL and handoff-formats)"
else bad "SKILL Step 2.4 and handoff-formats must name review-plan.json runs[i].prs as the verify-only prs source"; fi

# Regression (H3): Step 3.3 re-dispatched a FAILED/UNVERIFIED unit with no clean-up, so the
# fresh fixer hit the dead run's local commits (blocked) or its worktree path (already exists).
redispatch="$skill/references/fix-redispatch.md"
step3=$(awk '/^### Step 3: Fix/{on=1} /^### Step 4: Merge/{on=0} on' "$skill_md")
if grep -qF '[references/fix-redispatch.md](references/fix-redispatch.md)' <<<"$step3" \
   && grep -qF '[references/fix-redispatch.md](references/fix-redispatch.md)' "$skill/REFERENCE.md" \
   && [[ -f "$redispatch" ]] \
   && grep -qF 'git -C <root> worktree remove <path>' "$redispatch" \
   && grep -qF 'git -C <root> merge-base --is-ancestor <branch> <head_sha>' "$redispatch" \
   && grep -qF 'git -C <root> branch rescue/<unit> <branch>' "$redispatch" \
   && grep -qF 'git -C <root> branch -f <branch> <head_sha>' "$redispatch" \
   && ! grep -qE 'worktree remove (--force|-f) ' "$redispatch"; then
  pass "SKILL Step 3.3 clears leftover worktrees and resets the local branch before a re-dispatch"
else bad "SKILL Step 3.3 must link fix-redispatch.md, which removes leftover worktrees (never --force), rescues and resets the local branch"; fi

# Regression (H1): M8 built the repair unit from the live headRefOid, so a commit pushed after
# the gate became the repair's base and merged unreviewed once the repair passed G5.
m8=$(awk '/^## M8:/{on=1} /^## Stacked PRs/{on=0} on' "$proc")
# shellcheck disable=SC2016 # the backticks are literal markdown, not expansions
if ! grep -qF 'head_sha: <headRefOid from gh pr view' <<<"$m8" \
   && grep -qF 'latest pushed fix row' <<<"$m8" && grep -qF 'review.json` `head_sha`' <<<"$m8" \
   && grep -qF 'do not repair, report the PR for Lauri as' <<<"$m8"; then
  pass "merge-procedure M8 starts the repair from the expected head and refuses a moved one"
else bad "merge-procedure M8 must set head_sha to the expected head (fix push, else review) and refuse to repair when the live head differs"; fi

# #3750: pr-review copies find-verify's refute-by-default verifier. The verdict
# schema and distinct_also handling sit between `fv-shared:` markers in both and
# must stay byte-identical; the prompts differ on purpose (untrusted PRs, worktree
# paths), so their refute-by-default clauses and the code that enforces them are
# pinned as text in both.
fv="$repo_root/agent-patterns-plugin/skills/adversarial-review/workflows/find-verify.workflow.js"
fv_region() { # fv_region <file> <name>: lines strictly between the named markers
  awk -v b="// <fv-shared:$2:begin>" -v e="// <fv-shared:$2:end>" \
    'index($0, e) == 1 {on=0} on {print} index($0, b) == 1 {on=1}' "$1"
}
if [[ ! -f "$fv" ]]; then bad "find-verify template missing: $fv"
else
  for name in verdict-schema distinct-also; do
    a=$(fv_region "$fv" "$name"); b=$(fv_region "$wf/pr-review.workflow.js" "$name")
    if [[ -z "$a" ]]; then bad "find-verify has no fv-shared:$name region"
    elif [[ -z "$b" ]]; then bad "pr-review has no fv-shared:$name region"
    elif [[ "$a" == "$b" ]]; then pass "pr-review fv-shared:$name is byte-identical with find-verify"
    else bad "pr-review fv-shared:$name differs from find-verify"; diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") || true; fi
  done
  # Prompt clauses, whitespace-normalised because each template wraps its lines differently.
  norm() { tr -s ' \n\t' '   ' < "$1"; }
  fv_txt=$(norm "$fv"); pr_txt=$(norm "$wf/pr-review.workflow.js")
  for clause in \
    'You did not find this defect and have no stake in it being real.' \
    'Try to REFUTE it. Default to "refuted" unless you can construct a concrete reproduction: an input or state, and the wrong outcome it produces.' \
    'a verdict without one counts as a failed verifier' \
    "const onEnum = v && ['confirmed', 'partially', 'refuted'].includes(v.verdict)" \
    "const reproduced = onEnum && (v.verdict === 'refuted' || String(v.reproduction ?? '').trim() !== '')" \
    'if (!onEnum || !reproduced || distinct === null) {'; do
    if [[ "$fv_txt" == *"$clause"* && "$pr_txt" == *"$clause"* ]]; then pass "refute-by-default clause in both: ${clause:0:60}"
    else bad "refute-by-default clause missing from find-verify or pr-review: $clause"; fi
  done
fi

node "$here/run-workflows.mjs" "$wf" "$rr" || fail=1
exit "$fail"
