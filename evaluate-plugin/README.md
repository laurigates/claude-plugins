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
| `/evaluate:plugin` | Batch evaluate all skills in a plugin |
| `/evaluate:report` | View evaluation results and benchmark reports |
| `/evaluate:improve` | Suggest improvements based on eval results |
| `/evaluate:legibility` | Cold-read a SKILL.md with a zero-context agent reader to check its intent is legible (comprehension gate) |
| `/evaluate:matrix` | Run a skill's evals across pinned models with real execution and grade the artifact (executability gate) |

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
```

### Batch evaluate a plugin

```
/evaluate:plugin git-plugin
/evaluate:plugin git-plugin --create-missing-evals
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
└── eval-results/           # Gitignored: run outputs
    ├── benchmark.json
    ├── history.json
    ├── candidates/         # --best-of candidate revisions
    │   └── candidate-<i>.md
    └── runs/
        └── <eval-id>-<run-id>/
            ├── grading.json
            ├── comparison.json
            ├── transcript.md
            └── timing.json
```

- `evals.json` is version-controlled (test definitions)
- `eval-results/` is gitignored (transient run data)

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/aggregate_benchmark.sh` | Aggregate benchmark results across a plugin's skills |
| `scripts/eval_report.sh` | Generate formatted markdown report from benchmark data |
| `scripts/grade_deterministic.py` | Grade machine-checkable (regex/substring) assertions with zero judge tokens; defers fuzzy ones to `eval-grader` |
| `scripts/render_matrix_report.py` | Render the cross-model delta report from a `model-matrix.json` (delta verdict, portability flag, `executable_on_haiku` executability flag) |
| `scripts/apply_fixture.sh` | Apply/tear down an eval's opt-in `fixture` block in an isolated temp workdir so context-needing skills can honestly execute |

## Cross-Model Evaluation

Measuring skill effectiveness reproducibly across opus / sonnet / haiku — to
catch when a skill needs adjusting after a new model ships — is designed in
[`docs/cross-model-evaluation.md`](docs/cross-model-evaluation.md) and driven by
**`/evaluate:matrix`** (the executability gate). The token-frugal grader and
report format run against `git-plugin/skills/git-commit/evals.json` today.

The two weak-model gates are complementary: `/evaluate:legibility` reads a
SKILL.md cold (comprehension), while `/evaluate:matrix` runs it on a weak model
with real tool execution and grades the artifact (executability).
