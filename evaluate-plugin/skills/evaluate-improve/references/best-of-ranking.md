# /evaluate:improve — `--best-of N` candidate ranking

Generating N alternative revisions and letting evaluation pick the winner,
plus the history entry that records the ranking. Only needed when `--best-of`
is passed with N > 1. Entry point: [`../SKILL.md`](../SKILL.md) § Step 5a.


Instead of drafting the approved edits once, generate N alternative drafts and
let evaluation pick the winner.

1. **Generate candidates.** Write N complete candidate revisions of the
   SKILL.md to `<plugin>/skills/<skill>/eval-results/candidates/candidate-<i>.md`
   (the `eval-results/` tree is gitignored). Each candidate implements the
   approved suggestions with a genuinely different strategy — different
   instruction placement, phrasing, or example choice — not paraphrases of one
   draft.

2. **Rank with real grading when evals exist.** If the skill has `evals.json`:
   - For each candidate, run one pass per eval case: spawn a Task subagent
     (`subagent_type: general-purpose`) that receives the **candidate**
     content as the skill context and executes the eval prompt (mirrors
     `/evaluate:skill` Step 4; use `prepare_run.sh` for the run directories).
   - Grade each transcript with
     `python3 evaluate-plugin/scripts/grade_deterministic.py` — typed checks
     grade for zero judge tokens; defer fuzzy assertions to the `eval-grader`
     agent.
   - Rank candidates by **source-failure delta first** (how many of the Step 1
     source-failure cases each candidate fixes — the Delta-verify gate signal),
     then by mean golden-set pass rate, so a candidate that lifts the aggregate
     while leaving the motivating failures broken never wins. Break remaining
     ties with the `eval-comparator` agent: blind pairwise comparison of the
     tied candidates' transcripts. Discard any candidate with `delta <= 0`
     unless `--force-apply` is set.

3. **Fall back to blind self-preference when no evals exist.** Without
   `evals.json` there are no prompts to roll out. Rank via the
   `eval-comparator` agent — pairwise, candidates presented as Output A/B,
   the analyzer's weakness list passed as the assertions. Flag this in the
   report as a weaker signal and suggest re-running `/evaluate:skill` with
   `--create-evals` first.

4. **Apply the winner** through the Step 5 apply flow, and record the ranking
   in the history entry (Step 5b below): a `candidates` array with each
   candidate's id, pass rate (or comparison score), and a `selected` flag.

Token cost is bounded at N × eval cases × 1 run plus grading; treat `--best-of`
without a number as N=3. Prefer this mode for skills that have `evals.json` —
deterministic ranking of real rollouts is the point; text-only self-preference
is the fallback.

### Step 5b: Record history

After applying changes, update (or create) the history file at:
```
<plugin-name>/skills/<skill-name>/eval-results/history.json
```

Add a new iteration entry recording:
- Version number (increment from previous)
- Timestamp
- Pass rate from current benchmark
- Summary of changes made
- Delta-verify result: `source_failures_before`, `source_failures_after`, and the resulting `source_failure_delta` (and whether `--force-apply` overrode a non-positive delta)
- Candidate ranking when `--best-of` was used: a `candidates` array of `{id, pass_rate, source_failure_delta, selected}` (use `comparison_score` instead of `pass_rate` for the no-evals fallback)

