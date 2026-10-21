# model-compare

Compare Claude models on the same coding work, with deterministic hidden
graders where possible and a blind reviewer where not. It measures **models**,
not skills: `/evaluate:matrix` asks whether a skill adds value on a model, this
asks which model to send a piece of work to, and at what cost.

Three task sources, cheapest first:

| Set | What it is | Graded by | Cost per run (2026-10, medium effort) |
|---|---|---|---|
| `basic/` | 8 small, well-specified tasks (bug fixes, LRU, refactor, triage, log analysis, 4-file diagnosis, decomposition plan) | hidden `check.py`, 4–11 cases each | Haiku 5.5 ~$0.003, Opus 5.5 ~$0.06 |
| `hard/` | 8 harder tasks (multi-layer feature, concurrency + DST bugs with a red herring, 41-failure CI triage, 4-layer diagnosis, DSL from a spec, 23-file refactor with dynamic references, semver resolver, code review with planted bugs) | hidden `check.py`, 16–42 cases each, partial credit | Haiku 5.5 ~$0.02, Opus 5.5 ~$0.31 |
| `issues/` | real open issues of this repo, one worktree per model, normal Claude Code harness | the issue's own tests and probes, then a blind review against the maintainers' PR | Haiku 5.5 ~$0.25, Opus 5.5 ~$1.50 |

Findings from the first run: `docs/benchmarks/2026-10-model-comparison/`.

## Validate the sets (free, no model calls)

```bash
bash evaluate-plugin/scripts/model-compare/basic/validate.sh
bash evaluate-plugin/scripts/model-compare/hard/validate.sh
```

Each builds `tasks/` (and `hard/oracle/`) from source and checks every task's
contract: the untouched fixture fails (basic below 1.0, hard at most 0.4) and
the fixture plus the reference solution scores exactly 1.0. A grader that a
reference cannot pass, or that a no-op passes, measures nothing.
`scripts/tests/test-model-compare.sh` runs both in CI.

## Run synthetic cells

```bash
cd evaluate-plugin/scripts/model-compare
bash hard/validate.sh >/dev/null            # builds hard/tasks/
for m in claude-haiku-5-5 claude-sonnet-5-5 claude-opus-5-5; do
  echo "b2-subtle-bugs $m 1"
done | xargs -P 3 -L 1 bash -c 'bash run_cell.sh hard "$0" "$1" "$2" medium'
jq -c '{task,model,score,cost,turns,max_prompt,snoop}' "${TMPDIR:-/tmp}/model-compare-runs/results.jsonl"
```

`run_cell.sh <set-dir> <task> <model> <rep> [effort]` copies the fixture into a
fresh workdir outside the repo, runs a lean `claude -p` (no settings, plugins,
slash commands or MCP; Bash/Read/Edit/Write only), grades the result and
appends one JSON line: score, failed cases, cost, turns, peak prompt tokens, and
a `snoop` flag set when the transcript names the set directory or a
`check.py`. A flagged cell is worth inspecting, not discarding: a model's own
scratch script named `check.py` trips it too.

Caps: `MC_MAX_BUDGET_USD` per cell (default 1.00), `MC_TIMEOUT` (1200 s).

## Run real issues

```bash
bash evaluate-plugin/scripts/model-compare/run_issue.sh 3091 claude-haiku-5-5
```

`run_issue.sh <issue> <model> [effort]` creates `eval/<issue>-<model>` in a
worktree off `MC_BASE_REF` (default `origin/main`), runs `claude -p` there with
the repo's normal harness and `issues/prompts/<issue>.txt` (the issue text plus
"commit locally, do not push"), and records the diff, leftover changes, cost
and peak prompt under `$MC_RUNS_DIR/issues/`. Push and `gh` are denied.

The prompts in `issues/prompts/` are the five issues of the first run, kept
as examples. **Check an issue's premise before spending on it.** Two of the
first five turned out to be stale (#2994 already fixed on main by #3053, #3092
blocked on unmerged #3088): every model noticed, which measures judgment, but
not the fix.

Grade each issue with its own tests plus a targeted probe, then run
`issues/review-prompt.md` with a fresh Opus reviewer over the anonymised diffs
(shuffle model→letter and keep the key outside the review directory).

## Things that skew a comparison

- **Effort.** Pin `--effort` for every model. Defaults differ by model (Opus
  5.5 and Haiku 5.5 default to `medium`, most others to `high`).
- **Harness overhead.** A normal Claude Code session in this repo starts near
  69K prompt tokens; Haiku 5.5 bills a whole request at 5x once its prompt
  passes 100K. `run_cell.sh` strips the harness for that reason; `run_issue.sh`
  keeps it, because that is the cost a user pays.
- **Ceilings.** If every model scores 1.0, the set is too easy to rank them;
  add cases before adding runs.
- **Sample size.** One run per cell shows a direction, not a difference.
