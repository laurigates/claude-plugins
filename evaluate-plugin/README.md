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
```

## Data Layout

```
<plugin-name>/skills/<skill-name>/
├── SKILL.md
├── evals.json              # Committed: test case definitions
└── eval-results/           # Gitignored: run outputs
    ├── benchmark.json
    ├── history.json
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
