# evaluate-plugin

Skill evaluation and benchmarking plugin. Tests skill effectiveness through behavioral eval cases, grades results against assertions, and tracks quality improvements over time.

## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how the skills and agents fit together.

## What It Does

Static compliance checks (`plugin-compliance-check.sh`) verify structure — this plugin tests **behavior**: does a skill actually produce correct results when invoked?

| Dimension | Existing Tool | This Plugin |
|-----------|---------------|-------------|
| Structure | `plugin-compliance-check.sh` | — |
| Safety | `lint-context-commands.sh` | — |
| Freshness | `blueprint-health-check.sh` | — |
| **Behavior** | — | `/evaluate:skill` |
| **Improvement** | — | `/evaluate:improve` |

## Skills

| Skill | Description |
|-------|-------------|
| `/evaluate:skill` | Evaluate a single skill with test cases and grading |
| `/evaluate:plugin-batch` | Batch evaluate all skills in a plugin |
| `/evaluate:report` | View evaluation results and benchmark reports |
| `/evaluate:improve` | Suggest improvements based on eval results |
| `/evaluate:legibility` | Cold-read a SKILL.md with a zero-context agent reader to check its intent is legible (comprehension gate) |
| `/evaluate:matrix` | Run a skill's evals across pinned models with real execution and grade the artifact (executability gate) |
| `/evaluate:context-engineering` | Audit skills and always-loaded rules against the six Claude 5 context-engineering shifts (C1–C6) |

## Agents

| Agent | Model | Description |
|-------|-------|-------------|
| `eval-grader` | opus | Grade eval runs against assertions with cited evidence |
| `eval-analyzer` | opus | Analyze patterns across eval results and suggest improvements |
| `eval-comparator` | opus | Blind comparison of with-skill vs baseline outputs |

## Usage

### Evaluate a skill

```
/evaluate:skill git-plugin/git-commit
/evaluate:skill git-plugin/git-commit --create-evals
/evaluate:skill git-plugin/git-commit --runs 3 --baseline
/evaluate:skill git-plugin/git-commit --harness headless --baseline
/evaluate:skill git-plugin/git-commit --triggers-only
```

`--harness headless` (opt-in; `subagent` stays the default) rolls each cell out as a
real `claude -p` child with the plugin loaded, instead of an in-session subagent with
the SKILL.md pasted in — so plugin loading, description routing, `allowed-tools` and
hooks are exercised, and the run yields a `trace.json` and a workspace snapshot for
trace and workspace checks. `--triggers` / `--triggers-only` run the `evals.json`
`triggers` block: prompts that should and should not invoke the skill, scored as
recall / precision / false-positive rate. Both need `claude`, `jq` and `python3`;
see [Headless harness](docs/cross-model-evaluation.md#headless-harness).

`--create-evals` always generates an abstention control: an impossible task whose
passing answer is a refusal, marked `"expected_outcome": "abstain"`, with an
`absent_regex` that fails a fabricated answer. Every `evals.json` must carry one
(`scripts/check-evals-abstention.sh`); see
[`references/schemas.md`](references/schemas.md#abstention-controls-impossible-tasks).

### Batch evaluate a plugin

```
/evaluate:plugin-batch git-plugin
/evaluate:plugin-batch git-plugin --create-missing-evals
/evaluate:plugin-batch git-plugin --harness headless
```

### View results

```
/evaluate:report git-plugin/git-commit --latest
/evaluate:report git-plugin --history
```

### Get improvement suggestions

```
/evaluate:improve git-plugin/git-commit
/evaluate:improve git-plugin/git-commit --apply
/evaluate:improve git-plugin/git-commit --apply --best-of 3
```

With `--best-of N`, the skill drafts N alternative revisions instead of one,
ranks them by re-running the skill's evals against each candidate (deterministic
grading via `grade_deterministic.py`; `eval-comparator` blind pairwise as
tie-break or as the fallback when no `evals.json` exists), and applies the
winner. The ranking is recorded in `history.json`.

## Data Layout

```
<plugin-name>/skills/<skill-name>/
├── SKILL.md
├── evals.json              # Committed: test case definitions
└── eval-results/           # Gitignored: aggregated outputs
    ├── benchmark.json
    ├── history.json
    ├── model-matrix.json
    └── candidates/         # --best-of candidate revisions
        └── candidate-<i>.md

tmp/eval-runs/<plugin-name>/<skill-name>/   # Gitignored: per-run staging
└── runs/                   # baseline/ for --baseline runs
    └── <eval-id>-run-<N>/
        ├── manifest.json
        ├── grading.json
        ├── comparison.json
        ├── transcript.md
        ├── timing.json
        │   # headless harness only:
        ├── transcript.jsonl    # raw stream-json from the claude -p child
        ├── trace.json          # harness-neutral trace (parse_trace.py)
        ├── workspace/          # snapshot of the child's workdir
        └── rollout-meta.json   # flags as run; prompt as sha256 only
```

- `evals.json` is version-controlled (test definitions)
- `eval-results/` is gitignored (transient aggregated data)
- Run directories are staged by `scripts/prepare_run.sh` under the repo's
  `tmp/eval-runs/` (override with `EVAL_RUNS_ROOT`), deliberately **outside**
  `skills/`: path-scoped rules on `**/skills/**` would otherwise load into every
  eval subagent that writes its transcript (#2667)

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/aggregate_benchmark.sh` | Aggregate benchmark results across a plugin's skills |
| `scripts/eval_report.sh` | Generate formatted markdown report from benchmark data |
| `scripts/inspect_eval.sh` | List a plugin's skills and eval suites (`--plugin-dir <plugin>`), or inspect one skill's suite (`--plugin <p> --skill <s> [--print-evals]`, `NUM_CASES` counted from `.evals`) |
| `scripts/prepare_run.sh` | Stage a run dir under `tmp/eval-runs/` (outside `skills/`, #2667) and print `RUN_DIR=` / `MANIFEST=` / `STARTED_AT=` |
| `scripts/grade_deterministic.py` | Grade typed checks with zero judge tokens — output (regex/substring), trace (`--trace`: skill_triggered, tool_called, command_ran) and workspace (`--workspace`, `--allow-exec`: file/json/run_command) checks; trace/workspace checks without their input are `HARNESS_DEFERRED`, never judged; defers fuzzy ones to `eval-grader` |
| `scripts/rollout_headless.sh` | Run ONE rollout as a real `claude -p` child (`--plugin-dir` repeatable; omit for baseline) in a workdir outside the repo, with a scrubbed env (`--env-mode clean`), a spend cap (`--max-budget-usd`, required) and optional `--stop-on-skill`; writes transcript, `trace.json`, workspace snapshot and a `=== HEADLESS ROLLOUT ===` block |
| `scripts/parse_trace.py` | Parse a stream-json transcript into the harness-neutral `trace.json` v1 (skills invoked, tool calls, bash commands, files written, denials, hooks, cost, stop reason) |
| `scripts/run_trigger_evals.py` | Run an `evals.json` `triggers` block through headless rollouts and score recall / precision / FPR into `triggers.json`; `--dry-run` prints the plan and worst-case cost; per-prompt and total budget caps; `--no-copy` leaves `<skill>/eval-results/triggers.json` untouched |
| `scripts/render_matrix_report.py` | Render the cross-model delta report from a `model-matrix.json` (delta verdict, portability flag, `executable_on_haiku` executability flag, mixed-harness warning) |
| `scripts/apply_fixture.sh` | Apply/tear down an eval's opt-in `fixture` block in an isolated temp workdir so context-needing skills can honestly execute |
| `scripts/check_golden_set_evals.py` | Validate every golden-set canary's `evals.json` (all 13 check types, the `triggers` block) and run recorded probes (`scripts/tests/fixtures/golden-set-probes.json`, with `trace_file` / `workspace_setup` for trace and workspace checks) through the grader, so a suite counted toward `evalCoverageFloor` is shown to grade |
| `skills/evaluate-context-engineering/scripts/check-context-engineering.py` | Channel M scanner — deterministic C1–C6 proxies over the tree (`scripts/check-context-engineering.py` at the repo root is a shim onto it) |

## Context Engineering

`/evaluate:context-engineering` measures the corpus against Anthropic's
[new context-engineering rules for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models):
rules→judgment, examples→interface design, upfront→progressive disclosure,
repetition→single source of truth, always-loaded budget, and specs→rich
references.

It runs the same two-channel design as the marketplace benchmark — a free
deterministic scan (Channel M) and an anchored blind rubric (Channel J) — which
are reported separately and never blended. The frozen rubric and the 2026-07
findings live in
[`docs/benchmarks/2026-07-context-engineering/`](../docs/benchmarks/2026-07-context-engineering/).

## Cross-Model Evaluation

Measuring skill effectiveness reproducibly across opus / sonnet / haiku — to
catch when a skill needs adjusting after a new model ships — is designed in
[`docs/cross-model-evaluation.md`](docs/cross-model-evaluation.md) and driven by
**`/evaluate:matrix`** (the executability gate). The token-frugal grader and
report format run against `git-plugin/skills/git-commit/evals.json` today.

Live smoke for the headless harness (real `claude -p` calls on haiku, asserted
≤ $1.50; never run by CI because it lacks the `test-` prefix):
`EVAL_LIVE=1 bash evaluate-plugin/scripts/tests/live/smoke-headless.sh`. It asserts
the plumbing. Routing is reported as `STATUS=WARN` (`WITH_SKILL_ROUTED=false`,
trigger thresholds missed), not as a failure; haiku at n=1 did not route to
`git-commit` on 2026-10-05.

The two weak-model gates are complementary: `/evaluate:legibility` reads a
SKILL.md cold (comprehension), while `/evaluate:matrix` runs it on a weak model
with real tool execution and grades the artifact (executability).
