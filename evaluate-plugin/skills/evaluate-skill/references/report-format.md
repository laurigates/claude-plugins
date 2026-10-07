# evaluate-skill: grading and report formats

## Summary table (Step 7)

```
## Evaluation Results: <plugin/skill-name>

| Metric | With Skill | Baseline | Delta |
|--------|-----------|----------|-------|
| Pass Rate | 85% | 42% | +43% |
| Duration | 14s | 12s | +2s |
| Runs | 3 | 3 | — |

### Per-Eval Breakdown

| Eval | Description | Pass Rate | Status |
|------|-------------|-----------|--------|
| eval-001 | Basic usage | 100% | PASS |
| eval-002 | Edge case | 67% | PARTIAL |
| eval-003 | Boundary | 100% | PASS |
```

## Grader prompt (Step 6)

```
Task subagent_type: evaluate-plugin:eval-grader
Prompt: Grade this eval run against the assertions.
  Eval case: <eval case from evals.json>
  Transcript: <path to transcript.md>
  Output artifacts: <list of created/modified files>
```

## Aggregate statistics (Step 7)

Compute aggregate statistics across all runs:
- Mean pass rate (assertions passed / total assertions)
- Standard deviation of pass rate
- Mean duration

If `--baseline` was used, also compute:
- Baseline mean pass rate
- Delta (improvement from skill)
